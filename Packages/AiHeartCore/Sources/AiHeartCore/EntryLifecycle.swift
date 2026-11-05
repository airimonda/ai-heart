import Foundation
import SwiftData

public enum LifecycleError: Error, Equatable {
    /// Entries about self-harm are never released (CLAUDE.md #8).
    case safetyKeep
    case alreadyReleased
    case notResting
}

/// Entry state is monotonic: kept -> resting(restUntil) -> released (purged).
/// "Bring it back" returns resting to kept before the purge. Each change bumps stateVersion.
public enum EntryLifecycle {
    public static func letGo(_ entry: Entry, restDays: Int, keptLines: [String] = [],
                             by: DecidedBy = .user, now: Date = Date()) throws {
        guard entry.status != .released else { throw LifecycleError.alreadyReleased }
        if SafetyCheck.mentionsSelfHarm(entry) { throw LifecycleError.safetyKeep }
        entry.status = .resting
        entry.decidedBy = by
        entry.keptLines = keptLines
        entry.restUntil = Calendar(identifier: .gregorian).date(byAdding: .day, value: max(0, restDays), to: now)
        // Let go: the note keeps its summary only (the setter strips her lines now that she is not kept).
        if let note = entry.releaseNote { entry.releaseNote = note }
        bump(entry, now: now)
    }

    public static func bringBack(_ entry: Entry, now: Date = Date()) throws {
        guard entry.status == .resting else { throw LifecycleError.notResting }
        entry.status = .kept
        entry.decidedBy = .user
        entry.restUntil = nil
        entry.keptLines = []
        entry.releaseNoteJSON = nil
        bump(entry, now: now)
    }

    /// Really gone (docs/06): text, photo and thumbnail, audio, word, regions and the
    /// embedding link, and her kept lines (owner, 2026-11-05: a let-go entry keeps the summary only, none of
    /// her exact lines). The note stays, as a summary. Numbers stay only if keepNumbers is on.
    /// Writes a tombstone. Returns it so callers can insert it.
    @discardableResult
    public static func purge(_ entry: Entry, in context: ModelContext, now: Date = Date()) throws -> PurgeRecord {
        if SafetyCheck.mentionsSelfHarm(entry) { throw LifecycleError.safetyKeep }
        entry.text = nil
        entry.photoData = nil
        entry.thumbData = nil
        entry.audioData = nil
        entry.audioSeconds = nil
        entry.word = nil
        entry.bodyRegions = []
        entry.sensations = []
        entry.keptLines = []
        entry.embeddingId = nil
        if !entry.keepNumbers {
            entry.valence = nil
            entry.arousal = nil
        }
        entry.status = .released
        if let note = entry.releaseNote { entry.releaseNote = note }
        entry.releasedAt = now
        entry.restUntil = nil
        bump(entry, now: now)
        let record = PurgeRecord(entryId: entry.syncId, purgedAt: now)
        context.insert(record)
        return record
    }

    /// Runs on launch and when a tombstone arrives. Purges resting entries whose rest has
    /// passed, and any entry that has a tombstone. Returns the number purged.
    @discardableResult
    public static func runPurgeJob(in context: ModelContext, now: Date = Date()) throws -> Int {
        let tombstoned = Set(try context.fetch(FetchDescriptor<PurgeRecord>()).map(\.entryId))
        let entries = try context.fetch(FetchDescriptor<Entry>())
        var count = 0
        for entry in entries where entry.status != .released {
            let due = entry.status == .resting && (entry.restUntil.map { $0 <= now } ?? false)
            if due || tombstoned.contains(entry.syncId) {
                if SafetyCheck.mentionsSelfHarm(entry) {
                    // Keep it. Never release.
                    entry.status = .kept
                    entry.restUntil = nil
                    bump(entry, now: now)
                    continue
                }
                try purge(entry, in: context, now: now)
                count += 1
            }
        }
        // Notes on let-go entries written before summaries-only (owner, 2026-11-05) lose her lines too.
        for entry in entries where entry.status != .kept {
            if let note = entry.releaseNote, note.summaryOnly != true { entry.releaseNote = note }
        }
        // Released before kept lines were cleared at purge: clear them now.
        for entry in entries where entry.status == .released && !entry.keptLines.isEmpty {
            entry.keptLines = []
            entry.updatedAt = now
        }
        try context.save()
        return count
    }

    /// Merge rule for two copies of one entry's state (docs/11): a tombstone always wins,
    /// then the higher stateVersion, then the later stateChangedAt.
    public static func winningStatus(local: (EntryStatus, Int, Date), remote: (EntryStatus, Int, Date),
                                     hasTombstone: Bool) -> EntryStatus {
        if hasTombstone || local.0 == .released || remote.0 == .released { return .released }
        if local.1 != remote.1 { return local.1 > remote.1 ? local.0 : remote.0 }
        return local.2 >= remote.2 ? local.0 : remote.0
    }

    static func bump(_ entry: Entry, now: Date) {
        entry.stateVersion += 1
        entry.stateChangedAt = now
        entry.updatedAt = now
    }
}

/// Keyword screen for self-harm or suicide. Conservative on purpose: a false positive only
/// means an entry is kept. English and Japanese.
public enum SafetyCheck {
    static let terms = [
        "suicide", "suicidal", "kill myself", "killing myself", "end my life", "ending my life",
        "self-harm", "self harm", "selfharm", "hurt myself", "hurting myself", "cut myself", "cutting myself",
        "want to die", "wanna die", "ideation", "suicidal thoughts", "thoughts of dying", "don't want to be alive", "dont want to be alive", "not want to live",
        "overdose", "自殺", "死にたい", "自傷", "リスカ", "消えたい",
    ]

    /// One list for typed entries, Listen and notes (English, Japanese, Tagalog): the core terms plus
    /// the indirect phrases. Case-, width- and apostrophe-insensitive.
    public static func mentionsSelfHarm(_ text: String) -> Bool {
        let t = normalised(text)
        return (terms + ListenSafety.extra).contains { t.contains(normalised($0)) }
    }

    static func normalised(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    public static func mentionsSelfHarm(_ entry: Entry) -> Bool {
        let parts = [entry.text, entry.word] + entry.keptLines.map(Optional.some)
            + (entry.releaseNote?.allText ?? []).map(Optional.some)
        return parts.compactMap { $0 }.contains(where: mentionsSelfHarm)
    }
}

public enum JournalSearch {
    /// Search kept text only, and never match a quiet topic.
    public static func matches(_ entry: Entry, query: String, quietTopics: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        guard entry.status == .kept else { return false }
        let lowered = q.lowercased()
        if quietTopics.contains(where: { !$0.isEmpty && lowered.contains($0.lowercased()) }) { return false }
        let haystack = [entry.text, entry.word].compactMap { $0 }.joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(q)
    }
}

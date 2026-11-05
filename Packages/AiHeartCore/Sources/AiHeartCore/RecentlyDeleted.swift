import Foundation
import SwiftData

/// A deleted entry, held for 30 days so she can bring it back (owner, 2026-11-04: "I wish I can
/// retrieve deleted entries at will"; docs/22). The whole entry is moved here (fields as JSON, media
/// as files) and the Entry itself is removed, so nothing else in the app (journal, charts, notes,
/// retrieval, exports, the model) can see it. After 30 days, or when she taps Delete now, it is
/// removed for good and a tombstone is written. Let-go entries are different: they rest, then are
/// really gone (CLAUDE.md #7).
@Model
public final class DeletedEntry {
    public var syncId: UUID = UUID()
    public var entryId: UUID = UUID()
    public var deletedAt: Date = Date()
    public var createdAt: Date = Date()
    @Attribute(.allowsCloudEncryption) public var payload: Data = Data()
    @Attribute(.allowsCloudEncryption) public var preview: String = ""
    @Attribute(.externalStorage) public var photoData: Data?
    @Attribute(.externalStorage) public var thumbData: Data?
    @Attribute(.externalStorage) public var audioData: Data?

    public init(entryId: UUID, deletedAt: Date, createdAt: Date, payload: Data, preview: String) {
        self.entryId = entryId; self.deletedAt = deletedAt; self.createdAt = createdAt
        self.payload = payload; self.preview = preview
    }
}

public enum RecentlyDeleted {
    public static let days = 30

    /// Moves an entry into Recently deleted. No tombstone yet, so it can come back.
    @discardableResult
    public static func move(_ e: Entry, in context: ModelContext, now: Date = Date()) -> DeletedEntry {
        let dto = BackupArchive.dto(e)
        let payload = (try? JSONEncoder().encode(dto)) ?? Data()
        let firstLine = (e.text ?? e.word ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let d = DeletedEntry(entryId: e.syncId, deletedAt: now, createdAt: e.createdAt, payload: payload,
                             preview: String(firstLine.prefix(120)))
        d.photoData = e.photoData; d.thumbData = e.thumbData; d.audioData = e.audioData
        context.insert(d)
        context.delete(e)
        try? context.save()
        return d
    }

    /// Puts it back exactly as it was (same id, text, media, notes, status).
    @discardableResult
    public static func restore(_ d: DeletedEntry, in context: ModelContext) -> Entry? {
        guard let dto = try? JSONDecoder().decode(BackupArchive.EntryDTO.self, from: d.payload) else { return nil }
        let e = BackupArchive.entry(from: dto, photo: d.photoData, thumb: d.thumbData, audio: d.audioData)
        context.insert(e)
        context.delete(d)
        try? context.save()
        return e
    }

    /// Gone for good: removed, with a tombstone so no synced copy can return.
    public static func purge(_ d: DeletedEntry, in context: ModelContext, now: Date = Date()) {
        context.insert(PurgeRecord(entryId: d.entryId, purgedAt: now))
        context.delete(d)
        try? context.save()
    }

    /// Run on launch and whenever the app becomes active: anything past its final date is removed for good.
    /// A deleted entry that was resting is finished the way a let-go is (owner, 2026-11-05): her text, media,
    /// kept lines and the rest are gone, and only the summary note (and numbers, if she keeps them) remain.
    @discardableResult
    public static func purgeExpired(in context: ModelContext, now: Date = Date()) -> Int {
        let all = (try? context.fetch(FetchDescriptor<DeletedEntry>())) ?? []
        let due = all.filter { daysLeft($0, now: now) <= 0 }
        for d in due {
            if wasResting(d) { finishLetGo(d, in: context, now: now) } else { purge(d, in: context, now: now) }
        }
        return due.count
    }

    /// The earlier of 30 days after she deleted it and, for a resting (let-go) entry, the end of its rest.
    public static func finalDate(_ d: DeletedEntry) -> Date {
        let thirty = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: d.deletedAt) ?? d.deletedAt
        if let rest = decoded(d), rest.statusRaw == EntryStatus.resting.rawValue, let until = rest.restUntil { return min(thirty, until) }
        return thirty
    }

    public static func daysLeft(_ d: DeletedEntry, now: Date = Date()) -> Int {
        max(0, Int(ceil(finalDate(d).timeIntervalSince(now) / 86400)))
    }

    static func decoded(_ d: DeletedEntry) -> BackupArchive.EntryDTO? {
        try? JSONDecoder().decode(BackupArchive.EntryDTO.self, from: d.payload)
    }

    static func wasResting(_ d: DeletedEntry) -> Bool { decoded(d)?.statusRaw == EntryStatus.resting.rawValue }

    /// Let-go rules for a deleted resting entry: rebuilt without its media, purged like any let-go (which writes
    /// the tombstone), and the held copy removed. An entry about self-harm is never released: plain removal.
    static func finishLetGo(_ d: DeletedEntry, in context: ModelContext, now: Date) {
        guard let dto = decoded(d) else { purge(d, in: context, now: now); return }
        let e = BackupArchive.entry(from: dto, photo: nil, thumb: nil, audio: nil)
        context.insert(e)
        do {
            try EntryLifecycle.purge(e, in: context, now: now)
        } catch {
            context.delete(e)
            purge(d, in: context, now: now)
            return
        }
        context.delete(d)
        try? context.save()
    }
}

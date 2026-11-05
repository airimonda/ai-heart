import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic data only. Never the owner's real data.

@Suite struct DayAnchorTests {
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let manila = TimeZone(identifier: "Asia/Manila")!

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func lateNightBelongsToPreviousDay() {
        let d = DayAnchor.day(for: date(2026, 10, 31, 2, 30, tz: tokyo), timeZone: tokyo)
        #expect(d == AnchoredDay(year: 2026, month: 10, day: 30))
    }

    @Test func afterStartHourIsSameDay() {
        let d = DayAnchor.day(for: date(2026, 10, 31, 4, 0, tz: tokyo), timeZone: tokyo)
        #expect(d == AnchoredDay(year: 2026, month: 10, day: 31))
    }

    @Test func usesEntryTimeZone() {
        // 03:30 in Tokyo is 02:30 in Manila: both before 04:00, both previous day.
        let instant = date(2026, 12, 15, 3, 30, tz: tokyo)
        #expect(DayAnchor.day(for: instant, timeZone: tokyo) == AnchoredDay(year: 2026, month: 12, day: 14))
        #expect(DayAnchor.day(for: instant, timeZone: manila) == AnchoredDay(year: 2026, month: 12, day: 14))
        // 04:30 Tokyo is 03:30 Manila: different anchored days.
        let later = date(2026, 12, 15, 4, 30, tz: tokyo)
        #expect(DayAnchor.day(for: later, timeZone: tokyo) == AnchoredDay(year: 2026, month: 12, day: 15))
        #expect(DayAnchor.day(for: later, timeZone: manila) == AnchoredDay(year: 2026, month: 12, day: 14))
    }
}

@Suite struct MoodWordTests {
    @Test func suggestionsAreBalanced() {
        let pts = MoodWords.staticSuggestions.compactMap(MoodWords.point(for:))
        #expect(pts.count == MoodWords.staticSuggestions.count)
        #expect(pts.contains { $0.valence > 0 })
        #expect(pts.contains { $0.valence < 0 })
        #expect(pts.contains { $0.arousal > 0 })
        #expect(pts.contains { $0.arousal < 0 })
    }

    @Test func pointsClamp() {
        let p = MoodPoint(valence: 3, arousal: -2)
        #expect(p.valence == 1 && p.arousal == -1)
    }

    @Test func regionLabelsUniqueAndStableRawValues() {
        let labels = BodyRegion.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        // Raw values already stored in entries must keep working.
        for raw in ["head", "throat", "chest", "stomach", "pelvis", "arms", "legs"] {
            #expect(BodyRegion(rawValue: raw) != nil)
        }
        #expect(BodyRegion.label(for: "wholeBody") == "Whole body")
    }

    @Test func everyRegionIsOnASideAndBestSideFollowsSelection() {
        #expect(BodyRegion.allCases.allSatisfy { !$0.sides.isEmpty })
        #expect(BodyRegion.regions(on: .back).contains(.lowerBack))
        #expect(!BodyRegion.regions(on: .front).contains(.lowerBack))
        #expect(BodyRegion.bestSide(for: [.lowerBack, .shoulders]) == .back)
        #expect(BodyRegion.bestSide(for: [.chest, .lowerBack]) == .front)
        #expect(BodyRegion.bestSide(for: []) == .front)
    }

    @Test func sensationWordsUnique() {
        #expect(Set(Sensations.all).count == Sensations.all.count)
        #expect(Sensations.common.allSatisfy(Sensations.all.contains))
    }

    @Test func lookupIsCaseInsensitive() {
        #expect(MoodWords.point(for: "calm") == MoodWords.point(for: "Calm"))
        #expect(MoodWords.point(for: "my own word") == nil)
    }
}

@Suite @MainActor struct LifecycleTests {
    func context() throws -> ModelContext {
        ModelContext(try AiHeartStore.makeContainer(inMemory: true))
    }

    func sampleEntry(_ ctx: ModelContext, text: String = "[synthetic] a slow grey afternoon") -> Entry {
        let e = Entry(kind: .photo)
        e.text = text
        e.word = "Flat"
        e.valence = -0.2
        e.arousal = -0.3
        e.photoData = Data([1, 2, 3])
        e.thumbData = Data([4])
        e.audioData = Data([5])
        e.bodyRegions = ["chest"]
        e.sensations = ["Heavy"]
        e.embeddingId = UUID()
        ctx.insert(e)
        return e
    }

    @Test func letGoThenBringBack() throws {
        let ctx = try context()
        let e = sampleEntry(ctx)
        let now = Date()
        try EntryLifecycle.letGo(e, restDays: 7, now: now)
        #expect(e.status == .resting)
        #expect(e.stateVersion == 1)
        #expect(e.restUntil! > now)
        try EntryLifecycle.bringBack(e, now: now)
        #expect(e.status == .kept)
        #expect(e.stateVersion == 2)
        #expect(e.text != nil)
    }

    @Test func purgeRemovesContentAndWritesTombstone() throws {
        let ctx = try context()
        let e = sampleEntry(ctx)
        let marker = "[synthetic] a slow grey afternoon"
        try EntryLifecycle.letGo(e, restDays: 7, keptLines: ["[synthetic] tea helped"])
        let later = Date().addingTimeInterval(8 * 86400)
        let n = try EntryLifecycle.runPurgeJob(in: ctx, now: later)
        #expect(n == 1)
        #expect(e.status == .released)
        #expect(e.text == nil && e.photoData == nil && e.thumbData == nil && e.audioData == nil)
        #expect(e.word == nil && e.bodyRegions.isEmpty && e.embeddingId == nil)
        #expect(e.keptLines.isEmpty)  // owner, 2026-11-05: a let-go entry keeps the summary only
        #expect(e.valence == -0.2) // keepNumbers defaults to true
        let tombs = try ctx.fetch(FetchDescriptor<PurgeRecord>())
        #expect(tombs.map(\.entryId) == [e.syncId])
        // Nothing in the store still holds the purged text.
        let all = try ctx.fetch(FetchDescriptor<Entry>())
        #expect(!all.contains { ($0.text ?? "").contains(marker) || $0.keptLines.contains(marker) })
        #expect(!all.contains { JournalSearch.matches($0, query: "grey", quietTopics: []) })
    }

    @Test func purgeDropsNumbersWhenAsked() throws {
        let ctx = try context()
        let e = sampleEntry(ctx)
        e.keepNumbers = false
        try EntryLifecycle.purge(e, in: ctx)
        #expect(e.valence == nil && e.arousal == nil)
    }

    @Test func restingNotYetDueIsNotPurged() throws {
        let ctx = try context()
        let e = sampleEntry(ctx)
        try EntryLifecycle.letGo(e, restDays: 7)
        #expect(try EntryLifecycle.runPurgeJob(in: ctx, now: Date().addingTimeInterval(86400)) == 0)
        #expect(e.status == .resting)
    }

    @Test func tombstonePurgesStaleCopy() throws {
        let ctx = try context()
        let e = sampleEntry(ctx)
        ctx.insert(PurgeRecord(entryId: e.syncId))
        #expect(try EntryLifecycle.runPurgeJob(in: ctx) == 1)
        #expect(e.status == .released && e.text == nil)
    }

    @Test func selfHarmIsNeverReleased() throws {
        let ctx = try context()
        let e = sampleEntry(ctx, text: "[synthetic] I thought about self-harm today")
        #expect(throws: LifecycleError.safetyKeep) { try EntryLifecycle.letGo(e, restDays: 7) }
        #expect(e.status == .kept)
        // Even if a copy arrived resting, the purge job keeps it.
        e.status = .resting
        e.restUntil = Date().addingTimeInterval(-1)
        #expect(try EntryLifecycle.runPurgeJob(in: ctx) == 0)
        #expect(e.status == .kept && e.text != nil)
    }

    @Test func japaneseSafetyTerms() {
        #expect(SafetyCheck.mentionsSelfHarm("[synthetic] 今日は死にたいと思った"))
        #expect(!SafetyCheck.mentionsSelfHarm("[synthetic] 今日は疲れた"))
    }

    @Test func mergeRule() {
        let t = Date()
        #expect(EntryLifecycle.winningStatus(local: (.kept, 3, t), remote: (.resting, 2, t), hasTombstone: false) == .kept)
        #expect(EntryLifecycle.winningStatus(local: (.kept, 3, t), remote: (.resting, 4, t), hasTombstone: false) == .resting)
        #expect(EntryLifecycle.winningStatus(local: (.kept, 9, t), remote: (.kept, 1, t), hasTombstone: true) == .released)
        #expect(EntryLifecycle.winningStatus(local: (.kept, 9, t), remote: (.released, 1, t), hasTombstone: false) == .released)
    }

    @Test func searchRespectsQuietTopicsAndKeptOnly() throws {
        let ctx = try context()
        let e = sampleEntry(ctx, text: "[synthetic] coffee with work friends")
        #expect(JournalSearch.matches(e, query: "coffee", quietTopics: []))
        #expect(!JournalSearch.matches(e, query: "work", quietTopics: ["Work"]))
        try EntryLifecycle.letGo(e, restDays: 7)
        #expect(!JournalSearch.matches(e, query: "coffee", quietTopics: []))
    }
}

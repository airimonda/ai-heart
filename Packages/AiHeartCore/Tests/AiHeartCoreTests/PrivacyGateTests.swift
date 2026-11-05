import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic text only. Owner decisions of 2026-11-05: the self-harm gate before every cloud call, feature
// routing, "unsure" when a check cannot run, summary-only let-go, the earlier-date purge, memory recency.

/// A model that records what it was asked.
final class RecordingModel: LanguageModel, @unchecked Sendable {
    let name: String
    var canSeeImages: Bool { false }
    private(set) var count = 0
    init(_ name: String) { self.name = name }
    func generate(_ request: GenerationRequest) async throws -> String { count += 1; return name }
}

struct FailingModel: LanguageModel {
    var name: String { "failing" }
    var canSeeImages: Bool { false }
    func generate(_ request: GenerationRequest) async throws -> String { throw URLError(.notConnectedToInternet) }
}

@Suite struct CloudGateTests {
    @Test func ordinaryTextGoesToTheCloud() async throws {
        let cloud = RecordingModel("cloud"), local = RecordingModel("local")
        let m = GatedCloudModel(cloud: cloud, local: local)
        let out = try await m.generate(GenerationRequest(system: "s", prompt: "p", ownText: "[synthetic] A quiet walk by the river."))
        #expect(out == "cloud" && cloud.count == 1 && local.count == 0)
    }

    @Test func selfHarmTextNeverGoesToTheCloudAndFallsBackToTheDevice() async throws {
        let cloud = RecordingModel("cloud"), local = RecordingModel("local")
        let m = GatedCloudModel(cloud: cloud, local: local)
        let out = try await m.generate(GenerationRequest(system: "s", prompt: "p", ownText: "[synthetic] I want to kill myself."))
        #expect(out == "local" && cloud.count == 0 && local.count == 1)
    }

    @Test func ideationPhrasesAreGatedToo() async throws {
        let cloud = RecordingModel("cloud"), local = RecordingModel("local")
        let m = GatedCloudModel(cloud: cloud, local: local)
        _ = try await m.generate(GenerationRequest(system: "s", prompt: "p", ownText: "[synthetic] I wish i was dead."))
        #expect(cloud.count == 0 && local.count == 1)
    }

    @Test func refusesWithNoDeviceModel() async {
        let cloud = RecordingModel("cloud")
        let m = GatedCloudModel(cloud: cloud, local: nil)
        await #expect(throws: CloudRefusal.self) {
            _ = try await m.generate(GenerationRequest(system: "s", prompt: "p", ownText: "[synthetic] I want to kill myself."))
        }
        #expect(cloud.count == 0)
    }

    @Test func undeclaredOwnTextFailsClosed() async throws {
        let cloud = RecordingModel("cloud"), local = RecordingModel("local")
        let m = GatedCloudModel(cloud: cloud, local: local)
        _ = try await m.generate(GenerationRequest(system: "s", prompt: "[synthetic] hello"))
        #expect(cloud.count == 0 && local.count == 1)
    }

    @Test func aboutMeInThePromptDoesNotBlock() async throws {
        // The gate reads only her own text, not the About me block that travels in the prompt.
        let cloud = RecordingModel("cloud"), local = RecordingModel("local")
        let m = GatedCloudModel(cloud: cloud, local: local)
        let prompt = "About me: [synthetic] a past hard time with thoughts of suicide.\nConversation:\nHer: [synthetic] A slow day."
        _ = try await m.generate(GenerationRequest(system: "s", prompt: prompt, ownText: "[synthetic] A slow day."))
        #expect(cloud.count == 1)
    }

    @Test func aCloudErrorIsNotHidden() async {
        let m = GatedCloudModel(cloud: FailingModel(), local: RecordingModel("local"))
        await #expect(throws: URLError.self) {
            _ = try await m.generate(GenerationRequest(system: "s", prompt: "p", ownText: "[synthetic] fine"))
        }
    }

    @Test func talkNeverSendsAFlaggedTurnInHistoryOrSummary() async {
        let turns = [TalkTurn(.her, "[synthetic] I want to kill myself."), TalkTurn(.her, "[synthetic] Work was long today.")]
        let p = TalkItThrough.prompt(turns: turns, snippets: [])
        #expect(!p.contains("kill myself") && p.contains("Work was long today."))
        #expect(!TalkItThrough.notesPrompt(turns: turns).contains("kill myself"))
        let cloud = RecordingModel("A question about the long day, maybe?")
        _ = await TalkItThrough.reply(model: GatedCloudModel(cloud: cloud, local: nil), turns: turns, snippets: [], quietTopics: [])
        #expect(cloud.count >= 1)
    }

    @Test func routingAllowListHoldsPhotosAndMediaOnThePhone() {
        let cloud = Set(LLMFeature.allCases.filter(\.mayUseCloud))
        #expect(cloud == [.notes, .talk, .outlook, .tone, .words, .aboutMe, .decide, .listen])
        #expect(!LLMFeature.photo.mayUseCloud && !LLMFeature.media.mayUseCloud && !LLMFeature.other.mayUseCloud)
    }
}

@Suite struct UnsureWhenModelCannotRunTests {
    @Test func aHardEntryIsKeptWhenTheCheckCannotRun() async {
        let text = "[synthetic] I yelled at my coworker and I feel ashamed and humiliated, terrible day."
        guard case .letGo = KeepOrRelease.decide(text: text, word: nil, valence: -0.8) else { return }  // rules must say let go
        var asked = 0
        let d = await ModelChecks.decideChecked(text: text, word: nil, valence: -0.8) { _ in asked += 1; return .unavailable }
        #expect(d == .keep)
        #expect(asked == 1)  // after the first failure nothing more is asked
    }

    @Test func unclearAnswersStillFollowTheRules() async {
        let text = "[synthetic] I yelled at my coworker and I feel ashamed and humiliated, terrible day."
        let rules = KeepOrRelease.decide(text: text, word: nil, valence: -0.8)
        let d = await ModelChecks.decideChecked(text: text, word: nil, valence: -0.8) { _ in .unclear }
        #expect(d == rules)
    }

    @Test func aYesStillMakesItSafer() async {
        let d = await ModelChecks.decideChecked(text: "[synthetic] Nothing I do changes anything at all.", word: nil, valence: nil) { q in
            q.hasPrefix("Does the writer sound hopeless") ? .yes : .no
        }
        #expect(d == .heavyKeep)
    }
}

@Suite struct LetGoKeepsSummaryOnlyTests {
    @Test func purgeClearsKeptLines() throws {
        let c = ModelContext(try exportContainer())
        let e = Entry(kind: .write)
        e.text = "[synthetic] A hard evening. A bath helped. I needed to stop early."
        c.insert(e)
        try EntryLifecycle.letGo(e, restDays: 3, keptLines: ["[synthetic] A bath helped."])
        #expect(e.keptLines == ["[synthetic] A bath helped."])  // allowed while it rests
        try EntryLifecycle.purge(e, in: c)
        #expect(e.keptLines.isEmpty && e.text == nil && e.status == .released)
    }

    @Test func theLaunchJobClearsKeptLinesOnEntriesReleasedEarlier() throws {
        let c = ModelContext(try exportContainer())
        let old = Entry(kind: .write)
        old.status = .released
        old.keptLines = ["[synthetic] An old kept line."]
        let kept = Entry(kind: .write)
        kept.keptLines = ["[synthetic] A kept entry may keep its lines."]
        c.insert(old); c.insert(kept)
        try EntryLifecycle.runPurgeJob(in: c)
        #expect(old.keptLines.isEmpty)
        #expect(!kept.keptLines.isEmpty)
    }

    @Test func aDueRestingEntryEndsWithNoKeptLines() throws {
        let c = ModelContext(try exportContainer())
        let e = Entry(kind: .write)
        e.text = "[synthetic] A hard evening. A walk helped."
        c.insert(e)
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        try EntryLifecycle.letGo(e, restDays: 1, keptLines: ["[synthetic] A walk helped."], now: t0)
        #expect(try EntryLifecycle.runPurgeJob(in: c, now: t0.addingTimeInterval(86400 * 2)) == 1)
        #expect(e.keptLines.isEmpty)
    }
}

@Suite struct DeletedRestingEntryTests {
    func resting(_ c: ModelContext, restDays: Int, at t0: Date) throws -> Entry {
        let e = Entry(kind: .write, createdAt: t0)
        e.text = "[synthetic] A hard evening. A bath helped."
        e.photoData = Data([9])
        e.valence = -0.5
        e.keepNumbers = false
        var n = ReleaseNote(); n.feelings = [.calm]; n.parts = [NotePart.trigger.rawValue: ["[synthetic] A line of hers."]]
        e.releaseNote = n
        c.insert(e)
        try EntryLifecycle.letGo(e, restDays: restDays, keptLines: ["[synthetic] A bath helped."], now: t0)
        try c.save()
        return e
    }

    @Test func theEarlierDateWins() throws {
        let c = ModelContext(try exportContainer())
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let e = try resting(c, restDays: 3, at: t0)
        let d = RecentlyDeleted.move(e, in: c, now: t0.addingTimeInterval(86400))
        // Rest ends on day 3, well before 30 days after the delete.
        #expect(RecentlyDeleted.daysLeft(d, now: t0.addingTimeInterval(86400)) == 2)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: t0.addingTimeInterval(86400 * 2)) == 0)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: t0.addingTimeInterval(86400 * 3 + 60)) == 1)
        #expect(try c.fetch(FetchDescriptor<DeletedEntry>()).isEmpty)
    }

    @Test func letGoRulesApplyWhenItEnds() throws {
        let c = ModelContext(try exportContainer())
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let e = try resting(c, restDays: 3, at: t0)
        let id = e.syncId
        RecentlyDeleted.move(e, in: c, now: t0)
        RecentlyDeleted.purgeExpired(in: c, now: t0.addingTimeInterval(86400 * 4))
        let all = try c.fetch(FetchDescriptor<Entry>())
        let back = try #require(all.first { $0.syncId == id })
        #expect(back.status == .released && back.text == nil && back.photoData == nil)
        #expect(back.keptLines.isEmpty && back.valence == nil)
        #expect(back.releaseNote?.summaryOnly == true && back.releaseNote?.parts == nil)
        #expect(try c.fetch(FetchDescriptor<PurgeRecord>()).map(\.entryId) == [id])
    }

    @Test func aLongRestStillEndsAtThirtyDays() throws {
        let c = ModelContext(try exportContainer())
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let e = try resting(c, restDays: 90, at: t0)
        let d = RecentlyDeleted.move(e, in: c, now: t0)
        #expect(RecentlyDeleted.daysLeft(d, now: t0) == 30)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: t0.addingTimeInterval(86400 * 31)) == 1)
        let back = try #require(try c.fetch(FetchDescriptor<Entry>()).first)
        #expect(back.status == .released && back.text == nil)
    }

    @Test func aKeptEntryIsStillRemovedWithJustATombstone() throws {
        let c = ModelContext(try exportContainer())
        let e = Entry(kind: .write)
        e.text = "[synthetic] A good morning."
        c.insert(e)
        let t0 = Date()
        RecentlyDeleted.move(e, in: c, now: t0)
        #expect(RecentlyDeleted.purgeExpired(in: c, now: t0.addingTimeInterval(86400 * 31)) == 1)
        #expect(try c.fetch(FetchDescriptor<Entry>()).isEmpty)
    }
}

@Suite struct MemoryRecencyTests {
    @Test func weightHalvesEveryNinetyDaysWithAFloor() {
        #expect(MemoryRecency.weight(ageDays: 0) == 1)
        #expect(abs(MemoryRecency.weight(ageDays: 90) - 0.5) < 1e-9)
        #expect(abs(MemoryRecency.weight(ageDays: 180) - 0.25) < 1e-9)
        #expect(MemoryRecency.weight(ageDays: 3650) == 0.15)
        #expect(MemoryRecency.weight(ageDays: -5) == 1)
    }

    @Test func ageWordsAreApproximate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(MemoryRecency.ageText(of: now.addingTimeInterval(-86400 * 90), now: now) == "from about 3 months ago")
        #expect(MemoryRecency.ageText(of: now.addingTimeInterval(-86400 * 21), now: now) == "from about 3 weeks ago")
        #expect(MemoryRecency.ageText(of: now, now: now) == "from today or yesterday")
        #expect(MemoryRecency.ageText(of: now.addingTimeInterval(-86400 * 800), now: now) == "from about 2 years ago")
    }

    @Test func anOlderMemoryRanksLowerButIsStillFound() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = "[synthetic] The garden path was quiet and the tomatoes were ripe."
        let docs = [
            RetrievalDocument(id: "old-k0", entryId: UUID(), date: now.addingTimeInterval(-86400 * 360), text: text, fromTalk: true),
            RetrievalDocument(id: "new-k0", entryId: UUID(), date: now.addingTimeInterval(-86400 * 5), text: text, fromTalk: true),
        ]
        let index = LocalRetrieval.Index(documents: docs, embedder: nil)
        let found = index.search("garden tomatoes quiet", k: 4, now: now)
        #expect(found.map(\.id) == ["new-k0", "old-k0"])
        #expect(found[1].score < found[0].score && found[1].score > 0)
    }

    @Test func talkPromptCarriesTheAgeNotAnExactQuote() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let s = Snippet(id: "k", entryId: UUID(), date: now.addingTimeInterval(-86400 * 90), text: "[synthetic] A calm walk.", fromTalk: true)
        let p = TalkItThrough.prompt(turns: [TalkTurn(.her, "[synthetic] Hello")], snippets: [s], now: now)
        #expect(p.contains("from about 3 months ago"))
    }
}

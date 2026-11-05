import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct LetGoSummaryTests {
    func note() -> ReleaseNote {
        var n = ReleaseNote()
        n.version = 2
        n.happened = "[synthetic] A plan changed at the last minute."
        n.feelings = [.calm]
        n.thought = "[synthetic] a thought"
        n.intensity = .strong
        n.intensityQuote = "[synthetic] strong words"
        n.needs = [NeedNote(need: CoreNeed.allCases[0], met: false, quote: "[synthetic] a need line")]
        n.helped = ["[synthetic] a walk"]
        n.parts = [NotePart.trigger.rawValue: ["[synthetic] The bus was late."]]
        return n
    }

    @Test func keptEntryKeepsHerWords() {
        let e = Entry(kind: .write)
        e.releaseNote = note()
        #expect(e.releaseNote?.parts != nil && e.releaseNote?.summaryOnly == nil)
    }

    @Test func lettingGoKeepsOnlyTheSummary() throws {
        let e = Entry(kind: .write)
        e.text = "[synthetic] The bus was late. I walked home."
        e.releaseNote = note()
        try EntryLifecycle.letGo(e, restDays: 7)
        let n = try #require(e.releaseNote)
        #expect(n.summaryOnly == true)
        #expect(n.happened == "[synthetic] A plan changed at the last minute.")
        #expect(n.feelings == [.calm] && n.intensity != nil && n.needs.count == 1)
        #expect(n.parts == nil && n.thought == nil && n.intensityQuote == nil && n.helped.isEmpty)
        #expect(n.needs.map(\.quote) == [""])
        let quoted = ReleaseNotes.reportLines(n).filter { $0.contains("\u{201C}") }
        #expect(quoted.isEmpty)
    }

    @Test func notesWrittenAfterLetGoAreSummaries() throws {
        let e = Entry(kind: .write)
        e.text = "[synthetic] The bus was late."
        try EntryLifecycle.letGo(e, restDays: 7)
        e.releaseNote = note()
        #expect(e.releaseNote?.summaryOnly == true && e.releaseNote?.parts == nil)
    }

    @Test func purgeJobStripsOlderLetGoNotes() throws {
        let c = ModelContext(try exportContainer())
        let e = Entry(kind: .write)
        e.text = "[synthetic] The bus was late."
        c.insert(e)
        try EntryLifecycle.letGo(e, restDays: 7)
        e.releaseNoteJSON = note().encoded()  // as stored before this change
        try EntryLifecycle.runPurgeJob(in: c)
        #expect(e.status == .resting && e.releaseNote?.summaryOnly == true && e.releaseNote?.parts == nil)
    }
}

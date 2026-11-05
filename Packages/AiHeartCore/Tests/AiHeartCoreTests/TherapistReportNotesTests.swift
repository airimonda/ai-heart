import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct TherapistReportNotesTests {
    let tz = TimeZone(identifier: "Asia/Tokyo")!

    func at(_ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))!
    }

    func note(_ needs: [CoreNeed], _ feelings: [NoteFeeling]) -> ReleaseNote {
        var n = ReleaseNote()
        n.feelings = feelings
        n.needs = needs.map { NeedNote(need: $0, met: false, quote: "[synthetic] words") }
        return n
    }

    func entry(_ d: Int, _ status: EntryStatus, _ n: ReleaseNote?) -> ReportEntry {
        ReportEntry(createdAt: at(d), tz: tz, status: status, word: nil, valence: nil, arousal: nil, regions: [], sensations: [],
                    text: nil, keptLines: [], note: n)
    }

    func build(_ es: [ReportEntry], notes: Bool = true) -> TherapistReportData {
        TherapistReport.build(entries: es, from: AnchoredDay(year: 2026, month: 10, day: 1), to: AnchoredDay(year: 2026, month: 10, day: 31),
                              dayStartHour: 4, includeWriting: false, includeNotes: notes, weekStart: { $0 })
    }

    @Test func notesFromLetGoEntriesAreTallied() {
        let data = build([
            entry(3, .released, note([.understood, .rest], [.hurt])),
            entry(5, .resting, note([.understood], [.hurt, .tired])),
            entry(7, .kept, note([.understood], [.scared])),        // kept entries have notes too now
        ])
        #expect(data.notes.count == 3)
        #expect(data.missingNeeds.first?.0 == .understood && data.missingNeeds.first?.1 == 3)
        #expect(data.feelings.first?.0 == .hurt)
        #expect(data.entryCount == 2)                                // released still not counted
    }

    @Test func worthWritingNotes() {
        #expect(!ReleaseNotes.worthWriting(nil))
        #expect(!ReleaseNotes.worthWriting("[synthetic] Coffee by the window."))
        #expect(ReleaseNotes.worthWriting("[synthetic] We had a fight and I cried in the car."))
        #expect(ReleaseNotes.worthWriting(String(repeating: "word ", count: 25)))
        #expect(ReleaseNotes.worthWriting(String(repeating: "疲", count: 75)))
    }

    @Test func notesOffMeansNone() {
        #expect(build([entry(3, .released, note([.rest], []))], notes: false).notes.isEmpty)
    }

    @Test func reportLinesQuoteHerWords() {
        var n = note([.understood], [.hurt])
        n.thought = "[synthetic] a thought"
        let lines = ReleaseNotes.reportLines(n)
        #expect(lines.contains("Thought: \u{201C}[synthetic] a thought\u{201D}"))
        #expect(lines.contains("Felt: hurt"))
        #expect(lines.contains { $0.hasPrefix("Need that seemed missing: to be heard and understood") })
    }
}

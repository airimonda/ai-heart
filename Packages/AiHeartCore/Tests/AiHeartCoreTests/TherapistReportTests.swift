import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct TherapistReportTests {
    let tz = TimeZone(identifier: "Asia/Tokyo")!
    let from = AnchoredDay(year: 2026, month: 10, day: 1)
    let to = AnchoredDay(year: 2026, month: 10, day: 31)

    func at(_ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 10, day: d, hour: 12))!
    }

    func e(_ d: Int, _ status: EntryStatus, word: String? = "Calm", v: Double = 0.5, text: String? = "[synthetic] text", kept: [String] = []) -> ReportEntry {
        ReportEntry(createdAt: at(d), tz: tz, status: status, word: word, valence: v, arousal: 0, regions: ["chest"],
                    sensations: ["Tight"], text: text, keptLines: kept)
    }

    func build(_ entries: [ReportEntry], writing: Bool) -> TherapistReportData {
        TherapistReport.build(entries: entries, from: from, to: to, dayStartHour: 4, includeWriting: writing,
                              weekStart: { AnchoredDay(ordinal: $0.ordinal - (($0.ordinal + 3) % 7)) })
    }

    @Test func releasedNeverAppears() {
        let r = build([e(2, .kept), e(3, .released, word: "Gone", text: "[synthetic] secret", kept: ["[synthetic] gone line"])], writing: true)
        #expect(r.entryCount == 1)
        #expect(!r.topWords.contains { $0.0 == "Gone" })
        #expect(!r.writing.contains { $0.text.contains("secret") })
        #expect(!r.keptLines.contains { $0.1.contains("gone line") })
    }

    @Test func restingOnlyContributesKeptLines() {
        let r = build([e(5, .resting, word: "Heavy", text: "[synthetic] hard day", kept: ["[synthetic] a bath helped"])], writing: true)
        #expect(r.keptLines.map(\.1) == ["[synthetic] a bath helped"])
        #expect(r.writing.isEmpty)
        #expect(r.topWords.isEmpty)
    }

    @Test func writingOnlyWhenAsked() {
        #expect(build([e(2, .kept)], writing: false).writing.isEmpty)
        #expect(build([e(2, .kept)], writing: true).writing.count == 1)
    }

    @Test func rangeAndCounts() {
        let r = build([e(2, .kept, word: "Calm"), e(2, .kept, word: "Calm"), e(9, .kept, word: "Tired", v: -0.5)], writing: false)
        #expect(r.entryCount == 3)
        #expect(r.daysWithEntries == 2)
        #expect(r.topWords.first! == ("Calm", 2))
        #expect(r.weeks.count == 2)
        #expect(r.topRegions.first! == ("chest", 3))
    }
}

import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic data only.

@Suite struct BaselineTests {
    @Test func medianAndMad() {
        let b = Baselines.baseline(values: [60, 61, 62, 63, 64, 65, 66])!
        #expect(b.median == 63)
        #expect(b.mad == 2)
        #expect(b.n == 7)
    }

    @Test func gateBelowMinDays() {
        #expect(Baselines.baseline(values: [1, 2, 3, 4, 5, 6]) == nil)
    }

    @Test func spreadIsFloored() {
        let b = Baselines.baseline(values: Array(repeating: 60, count: 10), minSpread: 1.5)!
        #expect(b.spread == 1.5)
        #expect(b.reading(60.5) == .within)
        #expect(b.reading(62) == .littleAbove)
        #expect(b.reading(56) == .below)
    }

    @Test @MainActor func windowExcludesTodayAndOldDays() throws {
        let today = AnchoredDay(year: 2026, month: 10, day: 31)
        var rows: [DaySummary] = []
        for back in 1...40 {
            let s = DaySummary(day: today.adding(days: -back))
            s.restingHR = back <= 28 ? 60 : 90 // older than the window: ignored
            rows.append(s)
        }
        let t = DaySummary(day: today); t.restingHR = 200; rows.append(t)
        let b = Baselines.baseline(for: .restingHR, on: today, from: rows)!
        #expect(b.median == 60)
        #expect(b.n == 28)
    }

    @Test func dayOrdinalRoundTrip() {
        let d = AnchoredDay(year: 2026, month: 12, day: 31)
        #expect(AnchoredDay(ordinal: d.ordinal) == d)
        #expect(d.adding(days: 1) == AnchoredDay(year: 2027, month: 1, day: 1))
        #expect(AnchoredDay(key: d.key) == d)
    }
}

@Suite struct SleepMathTests {
    let tz = TimeZone(identifier: "Asia/Tokyo")!

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    @Test func overlappingSourcesAreNotDoubleCounted() {
        let watch = SleepMath.Interval(start: at(30, 23), end: at(31, 6))
        let phone = SleepMath.Interval(start: at(31, 0), end: at(31, 7))
        #expect(SleepMath.minutes([watch, phone]) == 8 * 60)
    }

    @Test func gapsStaySeparate() {
        let a = SleepMath.Interval(start: at(31, 0), end: at(31, 3))
        let b = SleepMath.Interval(start: at(31, 4), end: at(31, 6))
        #expect(SleepMath.minutes([a, b]) == 5 * 60)
    }

    @Test func wakeDay() {
        #expect(SleepMath.wakeDay(end: at(31, 7), timeZone: tz) == AnchoredDay(year: 2026, month: 10, day: 31))
        #expect(SleepMath.wakeDay(end: at(31, 2), timeZone: tz) == AnchoredDay(year: 2026, month: 10, day: 31))
        #expect(SleepMath.wakeDay(end: at(31, 15), timeZone: tz) == AnchoredDay(year: 2026, month: 10, day: 31))
        #expect(SleepMath.wakeDay(end: at(30, 23, 30), timeZone: tz) == AnchoredDay(year: 2026, month: 10, day: 31))
    }
}

@Suite struct BodyWordsTests {
    func quadrants(_ words: [String]) -> Set<String> {
        Set(words.compactMap { w -> String? in
            guard let p = MoodWords.point(for: w) else { return nil }
            return "\(p.valence >= 0 ? "+" : "-")\(p.arousal >= 0 ? "+" : "-")"
        })
    }

    @Test func noDataGivesStaticSet() {
        let s = BodyWords.suggest(nil)
        #expect(s.words == MoodWords.staticSuggestions)
        #expect(!s.fromBody)
    }

    @Test func pausedGivesStaticSet() {
        #expect(!BodyWords.suggest(BodyToday(sleepZ: -3), paused: true).fromBody)
    }

    @Test(arguments: [
        BodyToday(sleepZ: -2.5, restingHRZ: 1.5, hrvZ: -1.5),
        BodyToday(sleepZ: 0, restingHRZ: 0, hrvZ: 0),
        BodyToday(sleepZ: 1, restingHRZ: -2, hrvZ: 2),
        BodyToday(sleepZ: -2),
        BodyToday(restingHRZ: 3),
    ])
    func alwaysBalancedFourQuadrants(_ body: BodyToday) {
        let s = BodyWords.suggest(body)
        #expect(s.words.count == 4)
        #expect(quadrants(s.words).count == 4)
    }

    @Test func shortSleepAndStirredLeadsWithWired() {
        let s = BodyWords.suggest(BodyToday(sleepZ: -2.5, restingHRZ: 1.5, hrvZ: -1.5))
        #expect(s.words.first == "Wired")
        #expect(s.notes.first == "sleep under your usual")
        #expect(BodyWords.stripLine(s) == "Sleep under your usual.")
    }

    @Test func usualDayHasCalmNote() {
        let s = BodyWords.suggest(BodyToday(sleepZ: 0.2, restingHRZ: -0.3, hrvZ: 0.5))
        #expect(s.notes.isEmpty)
        #expect(BodyWords.stripLine(s) == "Your body looks like your usual.")
    }

    @Test func noLabelsInNotes() {
        let s = BodyWords.suggest(BodyToday(sleepZ: -3, restingHRZ: 3, hrvZ: -3))
        let banned = ["anxious", "manic", "depress", "disorder", "stress"]
        for word in banned { #expect(!BodyWords.caption(s).lowercased().contains(word)) }
    }
}

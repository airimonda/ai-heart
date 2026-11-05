import Foundation
import Testing
@testable import AiHeartCore

// Synthetic days only.

@Suite struct EarlyWarningTests {
    let today = AnchoredDay(year: 2026, month: 8, day: 30)
    let utc = TimeZone(identifier: "UTC")!
    /// Usual midpoint 03:30, in minutes after noon.
    let usualMid = 930.0

    /// `usualDays` of 8 h sleep before the last 3 nights. Each recent night is (sleep hours, midpoint shift in hours).
    func nights(usualDays: Int = 28, recent: [(Double, Double)] = [(8, 0), (8, 0), (8, 0)]) -> [NightSample] {
        var out: [NightSample] = []
        for i in 0..<usualDays {
            // Tiny wobble so the spread is not exactly zero.
            let wobble = Double(i % 3) * 5
            out.append(NightSample(day: today.adding(days: -3 - i), sleepMin: 480 + wobble, midpoint: usualMid + wobble))
        }
        for (i, r) in recent.enumerated() {
            out.append(NightSample(day: today.adding(days: -2 + i), sleepMin: r.0 * 60, midpoint: usualMid + r.1 * 60))
        }
        return out
    }

    func energy(usualDays: Int = 28, recent: [Double] = [0, 0, 0]) -> [EarlyWarning.EnergyPoint] {
        var out = (0..<usualDays).map { EarlyWarning.EnergyPoint(day: today.adding(days: -3 - $0), arousal: $0 % 2 == 0 ? 0.05 : -0.05) }
        for (i, a) in recent.enumerated() { out.append(.init(day: today.adding(days: -2 + i % 3), arousal: a)) }
        return out
    }

    @Test func quietWhenNothingChanged() {
        #expect(EarlyWarning.notices(nights: nights(), energy: energy(), today: today).isEmpty)
    }

    @Test func noNoticeUnder14DaysOfData() {
        let n = nights(usualDays: 13, recent: [(5.5, 3), (5.5, 3), (8, 0)])
        let e = energy(usualDays: 13, recent: [0.9, 0.9, 0.9])
        #expect(EarlyWarning.notices(nights: n, energy: e, today: today).isEmpty)
        // Exactly 14 days is enough.
        let n14 = nights(usualDays: 14, recent: [(5.5, 3), (5.5, 3), (8, 0)])
        #expect(!EarlyWarning.notices(nights: n14, energy: [], today: today).isEmpty)
    }

    @Test func shortNightsRule() {
        let two = EarlyWarning.notices(nights: nights(recent: [(6.4, 0), (8, 0), (6.5, 0)]), energy: [], today: today)
        #expect(two.map(\.kind) == [.shortNights])
        #expect(two[0].text == "Two short nights: about 1.5 h under your usual")
        // One short night is not enough.
        #expect(EarlyWarning.notices(nights: nights(recent: [(5, 0), (8, 0), (8, 0)]), energy: [], today: today).isEmpty)
        // 1.4 h under does not count.
        #expect(EarlyWarning.notices(nights: nights(recent: [(6.6, 0), (6.6, 0), (8, 0)]), energy: [], today: today).isEmpty)
    }

    @Test func timingShiftRule() {
        let later = EarlyWarning.notices(nights: nights(recent: [(8, 2), (8, 0), (8, 2)]), energy: [], today: today)
        #expect(later.map(\.kind) == [.timingShift])
        #expect(later[0].text.contains("later"))
        let earlier = EarlyWarning.notices(nights: nights(recent: [(8, -2), (8, -2), (8, 0)]), energy: [], today: today)
        #expect(earlier[0].text.contains("earlier"))
        // One night, opposite directions, or under 1.5 h: nothing.
        #expect(EarlyWarning.notices(nights: nights(recent: [(8, 3), (8, 0), (8, 0)]), energy: [], today: today).isEmpty)
        #expect(EarlyWarning.notices(nights: nights(recent: [(8, 2), (8, -2), (8, 0)]), energy: [], today: today).isEmpty)
        #expect(EarlyWarning.notices(nights: nights(recent: [(8, 1.2), (8, 1.2), (8, 1.2)]), energy: [], today: today).isEmpty)
    }

    @Test func missingBedAndWakeTimesSkipTimingRuleOnly() {
        let n = nights(recent: [(6, 0), (6, 0), (8, 0)]).map { NightSample(day: $0.day, sleepMin: $0.sleepMin, midpoint: nil) }
        #expect(EarlyWarning.notices(nights: n, energy: [], today: today).map(\.kind) == [.shortNights])
    }

    @Test func energyRule() {
        let up = EarlyWarning.notices(nights: [], energy: energy(recent: [0.5, 0.45, 0.5]), today: today)
        #expect(up.map(\.kind) == [.energyUp])
        #expect(up[0].text == "Your energy taps have been higher than usual")
        // Under 0.4 above, or fewer than 3 taps.
        #expect(EarlyWarning.notices(nights: [], energy: energy(recent: [0.3, 0.3, 0.3]), today: today).isEmpty)
        #expect(EarlyWarning.notices(nights: [], energy: energy(recent: [0.9, 0.9]), today: today).isEmpty)
        // Fewer than 14 days of taps before: nothing.
        #expect(EarlyWarning.notices(nights: [], energy: energy(usualDays: 10, recent: [0.9, 0.9, 0.9]), today: today).isEmpty)
    }

    @Test func guessedPointsAreNotEnergyTaps() {
        func entry(_ dayOffset: Int, a: Double, guessed: Bool) -> Entry {
            let e = Entry(kind: .feeling, createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(dayOffset) * 86_400), timeZone: utc)
            e.valence = 0.2; e.arousal = a; e.moodGuessed = guessed
            return e
        }
        let pts = EarlyWarning.energyPoints([entry(0, a: 0.9, guessed: true), entry(1, a: 0.1, guessed: false)], dayStart: 4)
        #expect(pts.map(\.arousal) == [0.1])
    }

    @Test func oneNoticePerStretch() {
        #expect(EarlyWarning.isDue(watch: true, paused: false, lastNoticedDay: 0, today: today))
        #expect(!EarlyWarning.isDue(watch: true, paused: false, lastNoticedDay: today.ordinal - 6, today: today))
        #expect(EarlyWarning.isDue(watch: true, paused: false, lastNoticedDay: today.ordinal - 7, today: today))
        #expect(!EarlyWarning.isDue(watch: false, paused: false, lastNoticedDay: 0, today: today))
        #expect(!EarlyWarning.isDue(watch: true, paused: true, lastNoticedDay: 0, today: today))
    }

    @Test func midpointFromBedAndWake() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)).addingTimeInterval(23.5 * 3600)
        #expect(NightSample.midpoint(bed: start, wake: start.addingTimeInterval(8 * 3600), tz: utc) == 930) // 03:30
        #expect(NightSample.midpoint(bed: start, wake: start.addingTimeInterval(-60), tz: utc) == nil)
        #expect(NightSample.midpoint(bed: nil, wake: start, tz: utc) == nil)
    }

    @Test func summariesGiveNights() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let day = AnchoredDay(year: 2026, month: 8, day: 30)
        let s = DaySummary(day: day, timeZone: utc)
        s.sleepMin = 450
        let bed = cal.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 23, minute: 30))!
        s.bedtime = bed; s.wakeTime = bed.addingTimeInterval(8 * 3600)
        let n = NightSample.from([s]).first
        #expect(n?.sleepMin == 450)
        #expect(n?.midpoint == 930)
    }

    @Test func splitsOlderNotes() {
        #expect(EarlyWarning.splitOlderNotes("- sleeping less\n• talking fast; spending\n\n  ") == ["sleeping less", "talking fast", "spending"])
        #expect(EarlyWarning.splitOlderNotes("   ").isEmpty)
    }

    @Test func noticeWordsNeverLabel() {
        let all = EarlyWarning.notices(nights: nights(recent: [(5, 3), (5, 3), (5, 3)]), energy: energy(recent: [0.9, 0.9, 0.9]), today: today)
        #expect(all.count == 3)
        for n in all {
            let t = n.text.lowercased()
            for bad in ["manic", "episode", "relapse", "depress", "hypoman", "!", "should", "must"] { #expect(!t.contains(bad)) }
        }
    }
}

@Suite struct TrainingMoodTests {
    let utc = TimeZone(identifier: "UTC")!

    func entry(_ day: Int, v: Double?, a: Double?, guessed: Bool) -> Entry {
        let e = Entry(kind: .feeling, createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400), timeZone: utc)
        e.valence = v; e.arousal = a; e.moodGuessed = guessed
        return e
    }

    @Test func guessedPointsNeverTrain() {
        let r = TrainingMood.perDay([entry(0, v: 0.9, a: 0.9, guessed: true), entry(1, v: 0.2, a: nil, guessed: false),
                                     entry(1, v: 0.4, a: 0.6, guessed: false)], dayStart: 4)
        #expect(r.count == 1)
        let d = r.values.first!
        #expect(abs(d.valence - 0.3) < 1e-9)
        #expect(d.arousal == 0.6)
    }

    @Test func dayWithOnlyGuessedPointsIsMissing() {
        #expect(TrainingMood.perDay([entry(0, v: 0.5, a: 0.5, guessed: true)], dayStart: 4).isEmpty)
    }
}

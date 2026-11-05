import Foundation
import Testing
@testable import AiHeartCore

// Synthetic dates only.

@Suite struct QuietCheckTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    func day(_ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }

    @Test func defaultUntilEnoughHistory() {
        #expect(QuietCheck.thresholdDays(activity: [day(1), day(2)], now: day(3), calendar: cal) == 3)
    }

    @Test func dailyLoggerGetsShortThreshold() {
        let a = (1...30).map { day($0) }
        #expect(QuietCheck.thresholdDays(activity: a, now: day(31), calendar: cal) == 2)
    }

    @Test func sporadicLoggerIsNotPingedOnANormalGap() {
        // Logs every 3 days: usual gap 3, so the check-in waits 4 days.
        let a = stride(from: 1, through: 30, by: 3).map { day($0) }
        #expect(QuietCheck.thresholdDays(activity: a, now: day(31), calendar: cal) == 4)
    }

    @Test func neverLongerThanAWeek() {
        let a = stride(from: 1, through: 31, by: 3).map { day($0) } + [day(1, 13)]
        let sparse = (0..<10).map { cal.date(byAdding: .day, value: $0 * 9, to: day(1))! }
        #expect(QuietCheck.thresholdDays(activity: sparse, now: cal.date(byAdding: .day, value: 89, to: day(1))!, calendar: cal) == 7)
        #expect(QuietCheck.thresholdDays(activity: a, now: day(31), calendar: cal) <= 7)
    }

    @Test func firesOnceAtHerHourAfterTheThreshold() {
        let f = QuietCheck.fireDate(lastActivity: day(10, 9), thresholdDays: 3, hour: 19, now: day(10, 10),
                                    enabled: true, paused: false, alreadySentFor: nil, plannedAt: nil, calendar: cal)
        #expect(f == day(13, 19))
    }

    @Test func offPausedOrNewInstallMeansNothing() {
        for (on, paused, last) in [(false, false, Optional(day(1))), (true, true, Optional(day(1))), (true, false, nil)] {
            #expect(QuietCheck.fireDate(lastActivity: last, thresholdDays: 3, hour: 19, now: day(2), enabled: on, paused: paused,
                                        alreadySentFor: nil, plannedAt: nil, calendar: cal) == nil)
        }
    }

    @Test func neverTwiceInOneStretch() {
        let last = day(1, 9)
        let f = QuietCheck.fireDate(lastActivity: last, thresholdDays: 3, hour: 19, now: day(6), enabled: true, paused: false,
                                    alreadySentFor: last, plannedAt: day(4, 19), calendar: cal)
        #expect(f == nil)
        // A new log starts a new stretch.
        let g = QuietCheck.fireDate(lastActivity: day(6, 8), thresholdDays: 3, hour: 19, now: day(6, 9), enabled: true, paused: false,
                                    alreadySentFor: last, plannedAt: day(4, 19), calendar: cal)
        #expect(g == day(9, 19))
    }

    @Test func overdueWithoutASendGoesOutOnceSoon() {
        // Threshold passed while the app was never opened: plan the next possible hour, not the past.
        let f = QuietCheck.fireDate(lastActivity: day(1, 9), thresholdDays: 3, hour: 19, now: day(6, 20), enabled: true, paused: false,
                                    alreadySentFor: nil, plannedAt: nil, calendar: cal)
        #expect(f == day(7, 19))
        let g = QuietCheck.fireDate(lastActivity: day(1, 9), thresholdDays: 3, hour: 19, now: day(6, 10), enabled: true, paused: false,
                                    alreadySentFor: nil, plannedAt: nil, calendar: cal)
        #expect(g == day(6, 19))
    }

    @Test func bodyIsNonDemanding() {
        let l = QuietCheck.body.lowercased()
        for banned in ["log", "write", "miss", "streak", "should", "haven't", "forgot"] { #expect(!l.contains(banned), "\(banned)") }
    }
}

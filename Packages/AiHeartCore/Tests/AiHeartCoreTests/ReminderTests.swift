import Foundation
import Testing
@testable import AiHeartCore

@Suite struct ReminderTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }

    func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))! } // Nov 2 2026 is a Monday

    @Test func weekAheadAtChosenTime() {
        let ds = ReminderPlan.dates(from: at(2, 10), days: Set(1...7), hour: 21, minute: 0, wroteToday: false,
                                    skipIfWritten: true, paused: false, calendar: cal)
        #expect(ds.count == 7)
        #expect(ds.first == at(2, 21))
    }

    @Test func skipsTodayIfWritten() {
        let ds = ReminderPlan.dates(from: at(2, 10), days: Set(1...7), hour: 21, minute: 0, wroteToday: true,
                                    skipIfWritten: true, paused: false, calendar: cal)
        #expect(ds.count == 6)
        #expect(ds.first == at(3, 21))
    }

    @Test func onlyChosenDays() {
        // Monday (2) and Thursday (5)
        let ds = ReminderPlan.dates(from: at(2, 10), days: [2, 5], hour: 21, minute: 0, wroteToday: false,
                                    skipIfWritten: true, paused: false, calendar: cal)
        #expect(ds == [at(2, 21), at(5, 21)])
    }

    @Test func pastTimeTodayIsSkipped() {
        let ds = ReminderPlan.dates(from: at(2, 22), days: Set(1...7), hour: 21, minute: 0, wroteToday: false,
                                    skipIfWritten: true, paused: false, calendar: cal)
        #expect(ds.first == at(3, 21))
    }

    @Test func pausedMeansNone() {
        #expect(ReminderPlan.dates(from: at(2, 10), days: Set(1...7), hour: 21, minute: 0, wroteToday: false,
                                   skipIfWritten: true, paused: true, calendar: cal).isEmpty)
    }

    @Test func textIsNeutral() {
        let t = ReminderPlan.body.lowercased()
        for w in ["streak", "don't forget", "you haven't", "missed", "!"] { #expect(!t.contains(w)) }
    }
}

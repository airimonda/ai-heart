import Foundation
import Testing
@testable import AiHeartCore

// Synthetic sessions only.

@Suite struct ExerciseTimeTests {
    let tz = TimeZone(identifier: "UTC")!
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func oneLiftCounts() {
        let m = ExerciseTime.minutesByDay([(at(2, 18), 3600)], timeZone: tz, dayStartHour: 4)
        #expect(m[AnchoredDay(year: 2026, month: 11, day: 2)] == 60)
    }

    @Test func overlapsCountOnce() {
        // A lift and a Health session that overlap by 30 minutes: 90 minutes, not 120.
        let m = ExerciseTime.minutesByDay([(at(2, 18), 3600), (at(2, 18, 30), 3600)], timeZone: tz, dayStartHour: 4)
        #expect(m[AnchoredDay(year: 2026, month: 11, day: 2)] == 90)
    }

    @Test func separateSessionsAdd() {
        let m = ExerciseTime.minutesByDay([(at(2, 7), 1200), (at(2, 18), 3600)], timeZone: tz, dayStartHour: 4)
        #expect(m[AnchoredDay(year: 2026, month: 11, day: 2)] == 80)
    }

    @Test func lateNightBelongsToTheDayBefore() {
        let m = ExerciseTime.minutesByDay([(at(3, 1), 1800)], timeZone: tz, dayStartHour: 4)
        #expect(m[AnchoredDay(year: 2026, month: 11, day: 2)] == 30)
    }

    @Test func largerSourceWins() {
        #expect(ExerciseTime.combined(apple: nil, workouts: 45) == 45)
        #expect(ExerciseTime.combined(apple: 50, workouts: 45) == 50)
        #expect(ExerciseTime.combined(apple: 10, workouts: nil) == 10)
        #expect(ExerciseTime.combined(apple: nil, workouts: nil) == nil)
    }
}

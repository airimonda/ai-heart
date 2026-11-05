import Testing
@testable import AiHeartCore

// Synthetic days only.

@Suite struct MonthlyTableTests {
    @Test func meansSkipMissingAndCountDays() {
        let d = AnchoredDay(year: 2026, month: 9, day: 28)
        let days = (0..<6).map { i in
            MonthlyTable.DayRow(day: d.adding(days: i), sleepH: i == 0 ? nil : 7, restingHR: 60, mood: i % 2 == 0 ? 0.5 : nil,
                                workoutMin: i == 1 ? 45 : 0, workouts: i == 1 ? 1 : 0)
        }
        let m = MonthlyTable.months(days)
        #expect(m.map(\.key) == ["2026-09", "2026-10"])
        #expect(m[0].sleepH == .init(value: 7, days: 2))
        #expect(m[0].workouts == 1 && m[0].workoutMin == 45)
        #expect(m[1].mood?.days == 1)
        let w = MonthlyTable.weeks(days) { $0.adding(days: -(($0.ordinal + 3) % 7)) }
        #expect(w.reduce(0) { $0 + ($1.sleepH?.days ?? 0) } == 5)
    }
}

import Foundation

/// Exercise minutes per day from her workouts (owner, 2026-11-02).
///
/// Apple's "Exercise minutes" are recorded only by an Apple Watch, so without one the day showed
/// "–" even after a logged session. A day's exercise is the larger of Apple's minutes and the time
/// covered by her workouts (Health and Hevy, already merged into one row each). Overlapping
/// sessions count once. Display-only sources (Strava, CLAUDE.md #6) are left out by the caller.
public enum ExerciseTime {
    /// Minutes covered by workouts, per anchored day of each session's start.
    public static func minutesByDay(_ sessions: [(start: Date, durationSec: Double)], timeZone: TimeZone,
                                    dayStartHour: Int) -> [AnchoredDay: Double] {
        var byDay: [AnchoredDay: [(Date, Date)]] = [:]
        for s in sessions where s.durationSec > 0 {
            let d = DayAnchor.day(for: s.start, timeZone: timeZone, dayStartHour: dayStartHour)
            byDay[d, default: []].append((s.start, s.start.addingTimeInterval(s.durationSec)))
        }
        return byDay.mapValues { union($0) / 60 }
    }

    /// Seconds covered by the intervals, counting overlaps once.
    static func union(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total = 0.0
        var cur: (Date, Date)?
        for (a, b) in sorted {
            if let c = cur, a <= c.1 {
                cur = (c.0, max(c.1, b))
            } else {
                if let c = cur { total += c.1.timeIntervalSince(c.0) }
                cur = (a, b)
            }
        }
        if let c = cur { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    /// The day's exercise: Apple's minutes or workout minutes, whichever is larger.
    public static func combined(apple: Double?, workouts: Double?) -> Double? {
        switch (apple, workouts) {
        case let (a?, w?): max(a, w)
        case let (a?, nil): a
        case let (nil, w?): w
        default: nil
        }
    }
}

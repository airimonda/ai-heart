import Foundation

/// A "day" is anchored to sleep, not midnight (docs/02). Until sleep data exists (M2),
/// a moment before `dayStartHour` in the entry's own time zone belongs to the previous day.
public struct AnchoredDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: AnchoredDay, b: AnchoredDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    /// Noon on this day in the given calendar, for display and calendar math.
    public func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}

public enum DayAnchor {
    public static func day(for date: Date, timeZone: TimeZone, dayStartHour: Int = 4) -> AnchoredDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let shifted = date.addingTimeInterval(-Double(dayStartHour) * 3600)
        let c = cal.dateComponents([.year, .month, .day], from: shifted)
        return AnchoredDay(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }
}

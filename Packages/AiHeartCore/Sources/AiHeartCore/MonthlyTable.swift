import Foundation

/// Monthly and weekly roll-ups for the "My data" report (M11, owner 2026-11-01: tables and
/// charts instead of raw files). Means skip missing days; every cell carries its day count.
public enum MonthlyTable {
    public struct DayRow: Sendable {
        public let day: AnchoredDay
        public var sleepH: Double?, restingHR: Double?, hrv: Double?, steps: Double?
        public var mood: Double?
        public var workoutMin: Double
        public var workouts: Int
        public init(day: AnchoredDay, sleepH: Double? = nil, restingHR: Double? = nil, hrv: Double? = nil, steps: Double? = nil,
                    mood: Double? = nil, workoutMin: Double = 0, workouts: Int = 0) {
            self.day = day; self.sleepH = sleepH; self.restingHR = restingHR; self.hrv = hrv; self.steps = steps
            self.mood = mood; self.workoutMin = workoutMin; self.workouts = workouts
        }
    }

    public struct Mean: Sendable, Equatable {
        public let value: Double
        public let days: Int
    }

    public struct Row: Sendable, Identifiable {
        public var id: String { key }
        public let key: String          // "2026-10" or a week's Monday key
        public let start: AnchoredDay
        public let sleepH: Mean?, restingHR: Mean?, hrv: Mean?, steps: Mean?, mood: Mean?
        public let workouts: Int
        public let workoutMin: Double
    }

    static func mean(_ xs: [Double?]) -> Mean? {
        let v = xs.compactMap { $0 }
        return v.isEmpty ? nil : Mean(value: v.reduce(0, +) / Double(v.count), days: v.count)
    }

    static func row(_ key: String, _ start: AnchoredDay, _ g: [DayRow]) -> Row {
        Row(key: key, start: start, sleepH: mean(g.map(\.sleepH)), restingHR: mean(g.map(\.restingHR)), hrv: mean(g.map(\.hrv)),
            steps: mean(g.map(\.steps)), mood: mean(g.map(\.mood)),
            workouts: g.reduce(0) { $0 + $1.workouts }, workoutMin: g.reduce(0) { $0 + $1.workoutMin })
    }

    public static func months(_ days: [DayRow]) -> [Row] {
        Dictionary(grouping: days) { String(format: "%04d-%02d", $0.day.year, $0.day.month) }
            .map { k, g in row(k, AnchoredDay(year: g[0].day.year, month: g[0].day.month, day: 1), g) }
            .sorted { $0.start < $1.start }
    }

    /// Weeks keyed by the Monday given by `weekStart`.
    public static func weeks(_ days: [DayRow], weekStart: (AnchoredDay) -> AnchoredDay) -> [Row] {
        Dictionary(grouping: days) { weekStart($0.day) }
            .map { m, g in row(m.key, m, g) }
            .sorted { $0.start < $1.start }
    }
}

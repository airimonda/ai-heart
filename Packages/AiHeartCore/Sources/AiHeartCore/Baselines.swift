import Foundation

/// Her usual range for one signal: rolling 28-day median and MAD (docs/03).
/// Never population norms. Cycle-adjusted baselines arrive with M4; until then this is the
/// global baseline and is labeled so.
public struct Baseline: Equatable, Sendable {
    public let median: Double
    public let mad: Double
    /// Days with data inside the window.
    public let n: Int
    public let window: Int
    let minSpread: Double

    /// Robust standard deviation (MAD scaled to match a normal SD), floored.
    public var spread: Double { max(mad * 1.4826, minSpread) }

    /// The "usual range" band: median ± one robust SD.
    public var low: Double { median - spread }
    public var high: Double { median + spread }

    public func z(_ x: Double) -> Double { (x - median) / spread }

    public func reading(_ x: Double) -> Reading {
        let z = z(x)
        switch z {
        case ..<(-2): return .below
        case ..<(-1): return .littleBelow
        case ...1: return .within
        case ...2: return .littleAbove
        default: return .above
        }
    }
}

public enum Reading: Equatable, Sendable {
    case within, littleAbove, littleBelow, above, below

    /// Plain description. Sleep uses over/under; the rest use above/below.
    public func phrase(for signal: Signal) -> String {
        let (up, down) = signal == .sleep ? ("over", "under") : ("above", "below")
        switch self {
        case .within: return "Within your usual"
        case .littleAbove: return "A little \(up)"
        case .littleBelow: return "A little \(down)"
        case .above: return signal == .sleep ? "Over your usual" : "Above your usual"
        case .below: return signal == .sleep ? "Under your usual" : "Below your usual"
        }
    }

    public var direction: Int {
        switch self {
        case .within: 0
        case .littleAbove, .above: 1
        case .littleBelow, .below: -1
        }
    }
}

public enum Baselines {
    public static let window = 28
    /// Minimum days of data before a usual range is shown (docs/03: honest gates).
    public static let minDays = 7

    /// Baseline for `day` from the `window` days before it (the day itself is excluded,
    /// so today is compared against her usual, not against itself).
    public static func baseline(for signal: Signal, on day: AnchoredDay, from summaries: [DaySummary]) -> Baseline? {
        let end = day.ordinal
        let values: [Double] = summaries.compactMap { s in
            guard let d = s.day, d.ordinal < end, d.ordinal >= end - window else { return nil }
            return s.value(signal)
        }
        return baseline(values: values, minSpread: signal.minSpread)
    }

    public static func baseline(values: [Double], minSpread: Double = 0) -> Baseline? {
        guard values.count >= minDays else { return nil }
        let m = median(values)
        let mad = median(values.map { abs($0 - m) })
        return Baseline(median: m, mad: mad, n: values.count, window: window, minSpread: minSpread)
    }

    public static func median(_ xs: [Double]) -> Double {
        precondition(!xs.isEmpty)
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    /// Days with data in the window before `day`, for "learning your usual · n of 7".
    public static func daysWithData(_ signal: Signal, before day: AnchoredDay, in summaries: [DaySummary]) -> Int {
        let end = day.ordinal
        return summaries.filter { s in
            guard let d = s.day else { return false }
            return d.ordinal < end && d.ordinal >= end - window && s.value(signal) != nil
        }.count
    }
}

/// Sleep math. Several sources (Watch, iPhone, other apps) can record the same night,
/// so asleep time is the union of intervals, never the sum.
public enum SleepMath {
    public struct Interval: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public init(start: Date, end: Date) { self.start = start; self.end = end }
        public var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    public static func merged(_ intervals: [Interval]) -> [Interval] {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var out: [Interval] = []
        for i in sorted {
            if let last = out.last, i.start <= last.end {
                out[out.count - 1] = Interval(start: last.start, end: max(last.end, i.end))
            } else {
                out.append(i)
            }
        }
        return out
    }

    public static func minutes(_ intervals: [Interval]) -> Double {
        merged(intervals).reduce(0) { $0 + $1.minutes }
    }

    /// The day a stretch of sleep belongs to: the day she wakes into. Sleep ending in the
    /// evening (after 18:00) belongs to the next day, so an early night counts for the
    /// morning it leads to. Naps in the afternoon stay on their own day.
    public static func wakeDay(end: Date, timeZone: TimeZone) -> AnchoredDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: end.addingTimeInterval(6 * 3600))
        return AnchoredDay(year: c.year!, month: c.month!, day: c.day!)
    }
}

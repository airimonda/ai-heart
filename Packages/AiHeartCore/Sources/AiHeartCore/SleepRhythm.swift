import Foundation

/// One night of sleep as the mood outlook and the early-signs check see it: how long, and where
/// the middle of it fell. Plain values so it is easy to test with synthetic data.
public struct NightSample: Equatable, Sendable {
    public let day: AnchoredDay
    public let sleepMin: Double?
    /// Middle of the sleep, in minutes after noon (0 to 1439), so a night that crosses midnight
    /// stays on one side of the scale. Nil when bed or wake time is missing.
    public let midpoint: Double?

    public init(day: AnchoredDay, sleepMin: Double?, midpoint: Double?) {
        self.day = day; self.sleepMin = sleepMin; self.midpoint = midpoint
    }

    public init?(_ s: DaySummary) {
        guard let d = s.day else { return nil }
        self.day = d
        self.sleepMin = s.sleepMin
        self.midpoint = Self.midpoint(bed: s.bedtime, wake: s.wakeTime, tz: TimeZone(identifier: s.tz) ?? .current)
    }

    /// Minutes after noon of the middle of bed to wake, in the zone she slept in.
    /// Nil if wake is not after bed or the span is over 16 hours (a bad reading).
    public static func midpoint(bed: Date?, wake: Date?, tz: TimeZone) -> Double? {
        guard let bed, let wake, wake > bed, wake.timeIntervalSince(bed) <= 16 * 3600 else { return nil }
        let mid = bed.addingTimeInterval(wake.timeIntervalSince(bed) / 2)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: mid)
        let minutes = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return (minutes - 720 + 1440).truncatingRemainder(dividingBy: 1440)
    }

    public static func from(_ summaries: [DaySummary]) -> [NightSample] {
        var seen = Set<AnchoredDay>()
        return summaries.compactMap { s in
            guard let n = NightSample(s), seen.insert(n.day).inserted else { return nil }
            return n
        }
    }
}

/// Sleep timing and regularity for the mood outlook (docs/12: "add sleep timing and variability").
/// Both are compared with her own previous 28 days, never with a population norm.
public enum SleepRhythm {
    /// Smallest spread treated as meaningful, in minutes, so a very steady sleeper does not make
    /// small changes look large.
    public static let midpointFloorMin = 30.0
    public static let irregularFloorMin = 15.0
    /// Nights in the window the irregularity is measured over, and the least needed inside it.
    public static let spreadWindow = 7
    public static let spreadMinNights = 4

    /// Outlook inputs per day: how far the middle of last night's sleep sits from her usual
    /// (absolute z), and how uneven the last 7 nights' length was against her usual unevenness.
    /// Nil where there is not enough of her own data (`Baselines.minDays`).
    public static func outlookZ(_ nights: [NightSample], days: [AnchoredDay]) -> [AnchoredDay: (shiftZ: Double?, irregularZ: Double?)] {
        var mids: [Int: Double] = [:], mins: [Int: Double] = [:]
        for n in nights {
            if let m = n.midpoint { mids[n.day.ordinal] = m }
            if let s = n.sleepMin { mins[n.day.ordinal] = s }
        }
        // Spread of the last 7 nights ending on each day.
        var spread: [Int: Double] = [:]
        for o in mins.keys {
            let xs = (o - spreadWindow + 1...o).compactMap { mins[$0] }
            if xs.count >= spreadMinNights { spread[o] = sd(xs) }
        }
        var out: [AnchoredDay: (shiftZ: Double?, irregularZ: Double?)] = [:]
        for d in days {
            let o = d.ordinal
            var shift: Double?
            if let m = mids[o],
               let b = Baselines.baseline(values: (o - Baselines.window...o - 1).compactMap { mids[$0] }, minSpread: midpointFloorMin) {
                shift = abs(b.z(m))
            }
            var irregular: Double?
            if let s = spread[o],
               let b = Baselines.baseline(values: (o - Baselines.window...o - 1).compactMap { spread[$0] }, minSpread: irregularFloorMin) {
                irregular = b.z(s)
            }
            out[d] = (shift, irregular)
        }
        return out
    }

    static func sd(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = xs.reduce(0, +) / Double(xs.count)
        return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count - 1)).squareRoot()
    }
}

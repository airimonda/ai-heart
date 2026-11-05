import Foundation

public enum CyclePhase: String, CaseIterable, Sendable {
    case period, follicular, fertile, luteal

    public var label: String { rawValue.capitalized }
}

public enum OvulationMethod: String, Sendable {
    /// From the sleeping wrist-temperature shift (retrospective, about 1 to 2 days of error).
    case temp
    /// Cycle length minus 14 days. Rougher.
    case calendar
}

public struct CycleInfo: Equatable, Sendable {
    public let start: AnchoredDay
    /// Last day of bleeding in this cycle.
    public let periodEnd: AnchoredDay
    /// Nil for the current, unfinished cycle.
    public let length: Int?
    public let ovulation: AnchoredDay?
    public let method: OvulationMethod?

    public func contains(_ day: AnchoredDay) -> Bool {
        guard day >= start else { return false }
        guard let length else { return true }
        return day.ordinal < start.ordinal + length
    }
}

public struct CycleToday: Equatable, Sendable {
    public let day: Int
    /// Expected length of this cycle (her median, or 28 until she has cycles).
    public let expectedLength: Int
    public let phase: CyclePhase
    public let periodDays: Int
    /// 1-based cycle days of the fertile window and ovulation, estimated.
    public let fertileStart: Int
    public let fertileEnd: Int
    public let ovulationDay: Int
    /// Days until the next period is expected. Zero or less means any day now.
    public let nextPeriodIn: Int
    public let method: OvulationMethod
}

/// Cycle engine (docs/03). Starts from menstrual flow in Apple Health. Estimates ovulation
/// from the wrist-temperature shift when there is one, otherwise by calendar. Every phase
/// is an estimate and is labeled so in the UI.
public struct CycleAnalysis: Sendable {
    public let cycles: [CycleInfo]
    public let medianLength: Int?
    public let today: AnchoredDay

    /// Plausible cycle lengths used for her median. Outliers are kept as cycles but do
    /// not shape the prediction.
    static let plausible = 18...50

    public var completedCycles: Int { cycles.filter { $0.length != nil }.count }

    public var expectedLength: Int { medianLength ?? 28 }

    public func cycle(containing day: AnchoredDay) -> CycleInfo? {
        cycles.last { $0.contains(day) }
    }

    /// 1-based day within its cycle.
    public func cycleDay(_ day: AnchoredDay) -> Int? {
        cycle(containing: day).map { day.ordinal - $0.start.ordinal + 1 }
    }

    public func ovulation(of c: CycleInfo) -> (AnchoredDay, OvulationMethod) {
        if let o = c.ovulation, let m = c.method { return (o, m) }
        return (c.start.adding(days: (c.length ?? expectedLength) - 15), .calendar)
    }

    public func phase(_ day: AnchoredDay) -> CyclePhase? {
        guard let c = cycle(containing: day) else { return nil }
        if day <= c.periodEnd { return .period }
        let (ov, _) = ovulation(of: c)
        let d = day.ordinal - ov.ordinal
        if d >= -5 && d <= 1 { return .fertile }
        if d > 1 { return .luteal }
        return .follicular
    }

    public var current: CycleToday? {
        guard let c = cycles.last, c.contains(today) else { return nil }
        let day = today.ordinal - c.start.ordinal + 1
        // A cycle running past twice her usual length is probably missing data; say nothing.
        guard day <= expectedLength * 2 else { return nil }
        let (ov, method) = ovulation(of: c)
        let ovDay = ov.ordinal - c.start.ordinal + 1
        return CycleToday(
            day: day,
            expectedLength: max(expectedLength, day),
            phase: phase(today) ?? .follicular,
            periodDays: c.periodEnd.ordinal - c.start.ordinal + 1,
            fertileStart: max(1, ovDay - 5),
            fertileEnd: ovDay + 1,
            ovulationDay: ovDay,
            nextPeriodIn: expectedLength - day + 1,
            method: method
        )
    }

    /// Luteal versus the rest. Resting HR, HRV and wrist temperature shift after ovulation,
    /// so baselines compare like with like once there are enough cycles.
    public func isLuteal(_ day: AnchoredDay) -> Bool? {
        phase(day).map { $0 == .luteal }
    }
}

public enum CycleEngine {
    /// Bleeding days at most this far apart belong to the same period.
    static let periodGap = 2

    /// - Parameters:
    ///   - flowDays: days with any recorded bleeding.
    ///   - wristTemps: sleeping wrist temperature by day, °C.
    public static func analyze(flowDays: Set<AnchoredDay>, wristTemps: [AnchoredDay: Double], today: AnchoredDay) -> CycleAnalysis {
        let days = flowDays.sorted()
        var periods: [(start: AnchoredDay, end: AnchoredDay)] = []
        for d in days {
            if let last = periods.last, d.ordinal - last.end.ordinal <= periodGap {
                periods[periods.count - 1].end = d
            } else {
                periods.append((d, d))
            }
        }

        var cycles: [CycleInfo] = []
        for (i, p) in periods.enumerated() {
            let length = i + 1 < periods.count ? periods[i + 1].start.ordinal - p.start.ordinal : nil
            let end = length.map { p.start.adding(days: $0 - 1) } ?? today
            let ov = temperatureShift(in: p.end.adding(days: 1), through: end, temps: wristTemps)
            cycles.append(CycleInfo(start: p.start, periodEnd: p.end, length: length,
                                    ovulation: ov, method: ov == nil ? nil : .temp))
        }

        let lengths = cycles.compactMap(\.length).filter { CycleAnalysis.plausible.contains($0) }
        let median = lengths.isEmpty ? nil : Int(Baselines.median(lengths.map(Double.init)).rounded())
        return CycleAnalysis(cycles: cycles, medianLength: median, today: today)
    }

    /// Three-over-six rule on wrist temperature: the first day whose next three readings all
    /// sit at least 0.2 °C above the mean of the six before it. Ovulation is the day before.
    /// Needs readings on most days; returns nil when the shift is unclear.
    static func temperatureShift(in start: AnchoredDay, through end: AnchoredDay, temps: [AnchoredDay: Double]) -> AnchoredDay? {
        guard end.ordinal - start.ordinal >= 9 else { return nil }
        for o in (start.ordinal + 6)...(end.ordinal - 2) {
            let before = (1...6).compactMap { temps[AnchoredDay(ordinal: o - $0)] }
            let after = (0...2).compactMap { temps[AnchoredDay(ordinal: o + $0)] }
            guard before.count >= 4, after.count == 3 else { continue }
            let base = before.reduce(0, +) / Double(before.count)
            if after.allSatisfy({ $0 >= base + 0.2 }) {
                return AnchoredDay(ordinal: o - 1)
            }
        }
        return nil
    }
}

extension Baselines {
    /// Minimum completed cycles before baselines are adjusted for the phase (docs/03).
    public static let minCyclesForAdjustment = 3
    /// Look-back for phase-matched baselines: about three cycles.
    public static let phaseWindow = 84

    /// Cycle-adjusted baseline for signals that shift after ovulation. Falls back to nil
    /// when there are too few cycles or too few matched days; callers then use the global one.
    public static func cycleBaseline(for signal: Signal, on day: AnchoredDay, from summaries: [DaySummary],
                                     cycle: CycleAnalysis) -> Baseline? {
        guard [.restingHR, .hrv, .wristTemp, .breathing].contains(signal),
              cycle.completedCycles >= minCyclesForAdjustment,
              let luteal = cycle.isLuteal(day) else { return nil }
        let end = day.ordinal
        let values: [Double] = summaries.compactMap { s in
            guard let d = s.day, d.ordinal < end, d.ordinal >= end - phaseWindow,
                  cycle.isLuteal(d) == luteal else { return nil }
            return s.value(signal)
        }
        return baseline(values: values, minSpread: signal.minSpread)
    }
}

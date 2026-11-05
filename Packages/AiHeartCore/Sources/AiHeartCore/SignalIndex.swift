import Foundation

/// Fast lookups over years of day summaries. Same answers as `Baselines.baseline` and
/// `Baselines.cycleBaseline`, but each query touches only the days in its window.
public struct SignalIndex: Sendable {
    /// Per signal: (day ordinal, value), sorted by day.
    let series: [Signal: [(Int, Double)]]
    /// Luteal or not, per day ordinal, when a cycle is known.
    let luteal: [Int: Bool]
    let completedCycles: Int

    public init(_ summaries: [DaySummary], cycle: CycleAnalysis?) {
        var s: [Signal: [(Int, Double)]] = [:]
        var seen = Set<String>()
        for row in summaries {
            guard let d = row.day, seen.insert(row.dayKey).inserted else { continue }
            for sig in Signal.allCases { if let v = row.value(sig) { s[sig, default: []].append((d.ordinal, v)) } }
        }
        series = s.mapValues { $0.sorted { $0.0 < $1.0 } }
        var l: [Int: Bool] = [:]
        if let cycle {
            for c in cycle.cycles {
                let end = c.length.map { c.start.ordinal + $0 } ?? cycle.today.ordinal + 1
                for o in c.start.ordinal..<end {
                    if let p = cycle.phase(AnchoredDay(ordinal: o)) { l[o] = p == .luteal }
                }
            }
        }
        luteal = l
        completedCycles = cycle?.completedCycles ?? 0
    }

    /// Values with ordinal in [from, to).
    func window(_ signal: Signal, from: Int, to: Int) -> ArraySlice<(Int, Double)> {
        guard let arr = series[signal], !arr.isEmpty else { return [] }
        func lowerBound(_ x: Int) -> Int {
            var lo = 0, hi = arr.count
            while lo < hi { let mid = (lo + hi) / 2; if arr[mid].0 < x { lo = mid + 1 } else { hi = mid } }
            return lo
        }
        return arr[lowerBound(from)..<lowerBound(to)]
    }

    public func value(_ signal: Signal, on day: AnchoredDay) -> Double? {
        window(signal, from: day.ordinal, to: day.ordinal + 1).first?.1
    }

    public func globalBaseline(_ signal: Signal, on day: AnchoredDay) -> Baseline? {
        let vals = window(signal, from: day.ordinal - Baselines.window, to: day.ordinal).map(\.1)
        return Baselines.baseline(values: vals, minSpread: signal.minSpread)
    }

    public func cycleBaseline(_ signal: Signal, on day: AnchoredDay) -> Baseline? {
        guard [.restingHR, .hrv, .wristTemp, .breathing].contains(signal),
              completedCycles >= Baselines.minCyclesForAdjustment,
              let isLuteal = luteal[day.ordinal] else { return nil }
        let vals = window(signal, from: day.ordinal - Baselines.phaseWindow, to: day.ordinal)
            .filter { luteal[$0.0] == isLuteal }.map(\.1)
        return Baselines.baseline(values: vals, minSpread: signal.minSpread)
    }

    public func daysWithData(_ signal: Signal, before day: AnchoredDay) -> Int {
        window(signal, from: day.ordinal - Baselines.window, to: day.ordinal).count
    }

    /// Up to `days` values ending at `day`, with gaps left out.
    public func series(_ signal: Signal, endingAt day: AnchoredDay, days: Int) -> [(offset: Int, value: Double)] {
        let start = day.ordinal - days + 1
        return window(signal, from: start, to: day.ordinal + 1).map { (offset: $0.0 - start, value: $0.1) }
    }
}

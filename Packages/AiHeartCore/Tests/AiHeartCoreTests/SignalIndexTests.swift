import Foundation
import Testing
@testable import AiHeartCore

// The index must give exactly what the plain functions give. Synthetic data.

@Suite @MainActor struct SignalIndexTests {
    let today = AnchoredDay(year: 2026, month: 10, day: 31)

    func data(days: Int) -> ([DaySummary], CycleAnalysis) {
        var rng = Stats.RNG(seed: 21)
        var rows: [DaySummary] = []
        var flow = Set<AnchoredDay>()
        for back in 0..<days {
            let d = today.adding(days: -back)
            if rng.int(10) == 0 { continue }
            let s = DaySummary(day: d)
            s.restingHR = 55 + Double(rng.int(100)) / 10
            s.hrvSDNN = 40 + Double(rng.int(200)) / 10
            s.sleepMin = 360 + Double(rng.int(120))
            rows.append(s)
            if (back % 28) >= 23 { for k in 0..<5 { flow.insert(today.adding(days: -back + k)) } }
        }
        let cycle = CycleEngine.analyze(flowDays: Set(flow.filter { $0 <= today }), wristTemps: [:], today: today)
        return (rows, cycle)
    }

    @Test func matchesPlainBaselines() {
        let (rows, cycle) = data(days: 400)
        let idx = SignalIndex(rows, cycle: cycle)
        for back in stride(from: 0, to: 300, by: 7) {
            let d = today.adding(days: -back)
            for sig in [Signal.restingHR, .hrv, .sleep] {
                #expect(idx.globalBaseline(sig, on: d) == Baselines.baseline(for: sig, on: d, from: rows))
                #expect(idx.cycleBaseline(sig, on: d) == Baselines.cycleBaseline(for: sig, on: d, from: rows, cycle: cycle))
                #expect(idx.daysWithData(sig, before: d) == Baselines.daysWithData(sig, before: d, in: rows))
            }
        }
    }

    @Test func seriesAndValue() {
        let (rows, cycle) = data(days: 60)
        let idx = SignalIndex(rows, cycle: cycle)
        let row = rows.first!
        #expect(idx.value(.restingHR, on: row.day!) == row.restingHR)
        let s = idx.series(.restingHR, endingAt: today, days: 7)
        #expect(s.allSatisfy { (0..<7).contains($0.offset) })
    }

    @Test func fiveYearsIsFast() {
        let (rows, cycle) = data(days: 1825)
        let idx = SignalIndex(rows, cycle: cycle)
        let start = Date()
        for back in 0..<365 { _ = idx.cycleBaseline(.restingHR, on: today.adding(days: -back)) }
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}

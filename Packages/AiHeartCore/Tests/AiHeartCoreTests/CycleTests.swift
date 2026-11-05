import Foundation
import Testing
@testable import AiHeartCore

// Synthetic cycles only.

@Suite struct CycleTests {
    let today = AnchoredDay(year: 2026, month: 10, day: 31)

    /// Four starts 28 days apart, 5 bleeding days each, last start 21 days ago (so today is day 22).
    func flow(starts: [Int] = [-105, -77, -49, -21], length: Int = 5) -> Set<AnchoredDay> {
        Set(starts.flatMap { s in (0..<length).map { today.adding(days: s + $0) } })
    }

    /// Temperature 36.0, stepping to 36.35 the day after ovulation (cycle day 15).
    func temps(starts: [Int] = [-105, -77, -49, -21]) -> [AnchoredDay: Double] {
        var t: [AnchoredDay: Double] = [:]
        for back in 0...110 {
            let d = today.adding(days: -back)
            guard let s = starts.last(where: { $0 <= -back }) else { continue }
            let cd = -back - s + 1
            t[d] = cd >= 16 ? 36.35 : 36.0
        }
        return t
    }

    @Test func dayAndPhaseWithTemperature() {
        let a = CycleEngine.analyze(flowDays: flow(), wristTemps: temps(), today: today)
        #expect(a.completedCycles == 3)
        #expect(a.medianLength == 28)
        let c = a.current!
        #expect(c.day == 22)
        #expect(c.phase == .luteal)
        #expect(c.method == .temp)
        #expect(c.ovulationDay == 15)
        #expect(c.nextPeriodIn == 7)
        #expect(a.phase(today.adding(days: -21)) == .period)
        #expect(a.phase(today.adding(days: -21 + 9)) == .fertile)   // day 10
        #expect(a.phase(today.adding(days: -21 + 6)) == .follicular) // day 7
    }

    @Test func calendarFallbackWithoutTemperature() {
        let a = CycleEngine.analyze(flowDays: flow(), wristTemps: [:], today: today)
        let c = a.current!
        #expect(c.method == .calendar)
        #expect(c.ovulationDay == 14)
        #expect(c.phase == .luteal)
    }

    @Test func spottingTwoDaysApartIsOnePeriod() {
        let days: Set<AnchoredDay> = [today.adding(days: -10), today.adding(days: -8), today.adding(days: -6)]
        let a = CycleEngine.analyze(flowDays: days, wristTemps: [:], today: today)
        #expect(a.cycles.count == 1)
        #expect(a.current?.periodDays == 5)
    }

    @Test func noFlowNoCycle() {
        let a = CycleEngine.analyze(flowDays: [], wristTemps: [:], today: today)
        #expect(a.current == nil)
        #expect(a.phase(today) == nil)
    }

    @Test func implausibleLengthDoesNotShapeMedian() {
        let a = CycleEngine.analyze(flowDays: flow(starts: [-150, -80, -52, -24]), wristTemps: [:], today: today)
        #expect(a.medianLength == 28)
    }

    @Test func veryLongGapSaysNothing() {
        let a = CycleEngine.analyze(flowDays: flow(starts: [-90]), wristTemps: [:], today: today)
        #expect(a.current == nil)
    }

    @Test @MainActor func phaseMatchedBaseline() {
        let a = CycleEngine.analyze(flowDays: flow(), wristTemps: temps(), today: today)
        var rows: [DaySummary] = []
        for back in 1...100 {
            let d = today.adding(days: -back)
            let s = DaySummary(day: d)
            s.restingHR = a.isLuteal(d) == true ? 62 : 58
            rows.append(s)
        }
        let adjusted = Baselines.cycleBaseline(for: .restingHR, on: today, from: rows, cycle: a)!
        #expect(adjusted.median == 62)
        // Steps never get a cycle adjustment.
        #expect(Baselines.cycleBaseline(for: .steps, on: today, from: rows, cycle: a) == nil)
        // Fewer than three completed cycles: no adjustment.
        let short = CycleEngine.analyze(flowDays: flow(starts: [-49, -21]), wristTemps: temps(), today: today)
        #expect(Baselines.cycleBaseline(for: .restingHR, on: today, from: rows, cycle: short) == nil)
    }
}

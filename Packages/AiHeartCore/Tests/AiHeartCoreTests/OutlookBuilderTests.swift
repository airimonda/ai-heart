import Testing
@testable import AiHeartCore

// Synthetic days only.

@Suite struct OutlookBuilderTests {
    let start = AnchoredDay(year: 2026, month: 6, day: 1)

    func inputs(_ n: Int, seed: UInt64 = 3) -> [OutlookBuilder.DayInput] {
        var rng = Stats.RNG(seed: seed)
        func r() -> Double { Double(rng.int(2000)) / 1000 - 1 }
        var out: [OutlookBuilder.DayInput] = []
        for i in 0..<n {
            let sleepZ = r() * 1.5
            let v = max(-1, min(1, 0.25 * sleepZ + 0.1 * r()))
            out.append(.init(day: start.adding(days: i), sleepZ: sleepZ, restingHRZ: r(), hrvZ: r(), luteal: i % 28 > 14,
                             liftedYesterdayMin: i % 3 == 0 ? 50 : 0, valence: v, arousal: -0.4 * sleepZ * 0.3))
        }
        return out
    }

    @Test func gated() {
        let few = inputs(10)
        #expect(OutlookBuilder.build(few, today: few.last!.day) == nil)
        #expect(OutlookBuilder.daysUntilReady(few) > 0)
    }

    @Test func buildsThreeDaysWithBands() {
        let days = inputs(90)
        let r = OutlookBuilder.build(days, today: days.last!.day)!
        #expect(r.points.count == 3)
        for p in r.points { #expect(p.low <= p.valence && p.valence <= p.high) }
        #expect(r.points[2].high - r.points[2].low >= r.points[0].high - r.points[0].low)
        #expect(r.drivers.first?.feature == .shortSleep)
        #expect(r.facts["days_with_mood"] == "90")
    }

    @Test func togglesDropFeatures() {
        let days = inputs(60)
        let r = OutlookBuilder.build(days, today: days.last!.day, options: .init(useCycle: false, useDoses: false, useTraining: false))!
        #expect(!r.drivers.contains { [.luteal, .doseChange, .lifted].contains($0.feature) })
    }

    // MARK: sleep timing and regularity

    func nights(_ n: Int, mid: (Int) -> Double, mins: (Int) -> Double) -> [NightSample] {
        (0..<n).map { NightSample(day: start.adding(days: $0), sleepMin: mins($0), midpoint: mid($0)) }
    }

    @Test func newFeaturesHaveGentleWords() {
        #expect(OutlookBuilder.Feature.sleepShift.label == "Sleep timing shifted")
        #expect(OutlookBuilder.Feature.sleepIrregular.phrase == "sleep less regular")
    }

    @Test func shiftIsAbsoluteAndNeedsHerOwnHistory() {
        let late = nights(40, mid: { $0 == 35 ? 930 + 180 : 930 + Double($0 % 3) * 10 }, mins: { _ in 480 })
        let z = SleepRhythm.outlookZ(late, days: [start.adding(days: 3), start.adding(days: 34), start.adding(days: 35)])
        #expect(z[start.adding(days: 3)]!.shiftZ == nil)             // under 7 earlier days
        #expect(z[start.adding(days: 34)]!.shiftZ! < 1)
        #expect(z[start.adding(days: 35)]!.shiftZ! > 3)              // 3 h from her usual
        // Earlier by the same amount is also a large size.
        let early = nights(40, mid: { $0 == 35 ? 930 - 180 : 930 + Double($0 % 3) * 10 }, mins: { _ in 480 })
        let ze = SleepRhythm.outlookZ(early, days: [start.adding(days: 35)])
        #expect(ze[start.adding(days: 35)]!.shiftZ! > 3)
    }

    @Test func irregularRisesWhenNightsAreUneven() {
        // Steady 8 h with a small wobble, then a week of 5 h / 10 h swings.
        let ns = nights(45, mid: { _ in 930 }, mins: { i in i < 38 ? 480 + Double(i % 3) * 5 : (i % 2 == 0 ? 300 : 600) })
        let z = SleepRhythm.outlookZ(ns, days: [start.adding(days: 30), start.adding(days: 44)])
        #expect(z[start.adding(days: 30)]!.irregularZ! < 1)
        #expect(z[start.adding(days: 44)]!.irregularZ! > 3)
        // With fewer than 4 nights in the last 7 there is no reading.
        let sparse = SleepRhythm.outlookZ(ns.filter { $0.day.ordinal % 3 == 0 }, days: [start.adding(days: 44)])
        #expect(sparse[start.adding(days: 44)]?.irregularZ == nil)
    }

    @Test func outlookUsesTheNewFeatures() {
        var days = inputs(90)
        // Big timing shifts pull the next day's valence down in this synthetic world.
        for i in days.indices {
            let shift = i % 5 == 0 ? 3.0 : 0.0
            days[i].sleepShiftZ = shift
            days[i].sleepIrregularZ = 0.2 * shift
            if i + 1 < days.count { days[i + 1].valence = (days[i + 1].valence ?? 0) - 0.12 * shift }
        }
        let r = OutlookBuilder.build(days, today: days.last!.day)!
        let shift = r.drivers.first { $0.feature == .sleepShift }
        #expect(shift != nil)
        #expect(r.drivers.contains { $0.feature == .sleepIrregular })
        // Without the inputs the columns are flat and pull nothing.
        let plain = inputs(90)
        let off = OutlookBuilder.build(plain, today: plain.last!.day)!
        #expect(off.drivers.first { $0.feature == .sleepShift }!.size < 0.01)
    }

    @Test func fallbackUsesOnlyFactNumbers() {
        let days = inputs(60)
        let r = OutlookBuilder.build(days, today: days.last!.day)!
        let read = OutlookBuilder.fallbackRead(r)
        #expect(OutputValidator.check(read, OutputPolicy(input: OutlookBuilder.factsJSON(r))).isEmpty)
        #expect(OutlookBuilder.whatIfMoreSleep(days, today: days.last!.day) != nil)
    }
}

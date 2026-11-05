import Foundation
import Testing
@testable import AiHeartCore

// Synthetic days only.

@Suite struct OutlookTests {
    let start = AnchoredDay(year: 2026, month: 6, day: 1)

    /// Valence = 0.3 × sleep feature + noise; the second feature is pure noise.
    func days(_ n: Int, signal: Double, noise: Double, seed: UInt64 = 4) -> [Outlook.Day] {
        var rng = Stats.RNG(seed: seed)
        func r() -> Double { Double(rng.int(2000)) / 1000 - 1 }
        return (0..<n).map { i in
            let sleep = r() * 2
            let v = max(-1, min(1, signal * sleep + noise * r()))
            return Outlook.Day(day: start.adding(days: i), features: [sleep, r()], valence: v, arousal: 0)
        }
    }

    @Test func gatedWithFewDays() {
        #expect(Outlook.fit(days(10, signal: 0.3, noise: 0.1), horizon: 0, target: \.valence) == nil)
    }

    @Test func learnsARealSignal() {
        let m = Outlook.fit(days(120, signal: 0.3, noise: 0.1), horizon: 0, target: \.valence)!
        #expect(m.coef[0] > 0.15)
        #expect(abs(m.coef[1]) < 0.05)
        #expect(m.predict([1, 0]) > m.predict([-1, 0]))
    }

    @Test func shrinksTowardMeanWithNoSignal() {
        let m = Outlook.fit(days(40, signal: 0, noise: 0.4), horizon: 0, target: \.valence)!
        #expect(abs(m.coef[0]) < 0.1 && abs(m.coef[1]) < 0.1)
    }

    @Test func honestRecord() {
        let good = Outlook.backtest(days(120, signal: 0.35, noise: 0.08), target: \.valence)
        #expect(good.n >= 28)
        #expect(good.beatsBaselines)
        let noise = Outlook.backtest(days(120, signal: 0, noise: 0.5, seed: 9), target: \.valence)
        // With nothing to learn it must not claim to beat the baselines.
        #expect(!noise.beatsBaselines || noise.modelError < noise.weekError)
        let short = Outlook.backtest(days(30, signal: 0.35, noise: 0.08), target: \.valence)
        #expect(!short.beatsBaselines)
        #expect(short.daysNeeded > 0)
    }

    @Test func words() {
        #expect(Outlook.valenceWord(0.3, usual: 0) == "leans more pleasant")
        #expect(Outlook.valenceWord(0.05, usual: 0) == "near your usual")
        #expect(Outlook.arousalWord(0.3, usual: 0) == "a bit stirred")
        #expect(Outlook.arousalWord(0, usual: 0) == nil)
    }
}

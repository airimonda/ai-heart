import Foundation
import Testing
@testable import AiHeartCore

// Synthetic data only.

@Suite struct StatsTests {
    @Test func ranksShareTies() {
        #expect(Stats.ranks([10, 20, 20, 30]) == [1, 2.5, 2.5, 4])
    }

    @Test func spearmanMonotone() {
        let x = (1...20).map(Double.init)
        #expect(abs(Stats.spearman(x, x.map { $0 * $0 }) - 1) < 1e-9)
        #expect(abs(Stats.spearman(x, x.map { -$0 }) + 1) < 1e-9)
    }

    @Test func intervalIsDeterministicAndContainsEstimate() {
        var rng = Stats.RNG(seed: 3)
        let pairs: [(Double, Double)] = (0..<40).map { i in
            let x = Double(i)
            return (x, x * 0.05 + Double(rng.int(100)) / 100)
        }
        let a = Stats.spearmanInterval(pairs)!
        let b = Stats.spearmanInterval(pairs)!
        #expect(a == b)
        #expect(a.low <= a.estimate && a.estimate <= a.high)
        #expect(a.excludesZero) // a real upward trend over 40 days
    }

    @Test func noiseIsUnclear() {
        var rng = Stats.RNG(seed: 99)
        let pairs: [(Double, Double)] = (0..<20).map { _ in (Double(rng.int(1000)), Double(rng.int(1000))) }
        let iv = Stats.spearmanInterval(pairs)!
        #expect(!iv.excludesZero)
    }

    @Test func meanInterval() {
        let iv = Stats.meanInterval([1, 2, 3, 4, 5])!
        #expect(iv.estimate == 3)
        #expect(iv.low >= 1 && iv.high <= 5 && iv.low < 3 && iv.high > 3)
    }

    @Test func fitRecoversLine() {
        let f = Stats.linearFit((0..<10).map { (Double($0), 2 + 0.5 * Double($0)) })!
        #expect(abs(f.slope - 0.5) < 1e-9 && abs(f.intercept - 2) < 1e-9)
    }
}

@Suite struct PatternTests {
    let today = AnchoredDay(year: 2026, month: 10, day: 31)

    func input(days: Int, sleepEffect: Double, liftBoost: Double = 0) -> PatternInput {
        var rng = Stats.RNG(seed: 5)
        var mood: [AnchoredDay: Double] = [:], sleep: [AnchoredDay: Double] = [:], steps: [AnchoredDay: Double] = [:]
        var lifts = Set<AnchoredDay>()
        for i in 0..<days {
            let d = today.adding(days: -i)
            let s = 360 + Double(rng.int(180))
            sleep[d] = s
            steps[d] = 5000
            let lift = i % 3 == 0
            if lift { lifts.insert(d) }
            mood[d] = sleepEffect * (s - 450) / 90 + (lift ? liftBoost : 0) + (Double(rng.int(100)) - 50) / 250
        }
        return PatternInput(mood: mood, signals: [.sleep: sleep, .steps: steps], load: [:], liftDays: lifts,
                            phase: { _ in nil }, today: today)
    }

    @Test func gatedBelowMinimum() {
        let s = Patterns.sleepScatter(input(days: 10, sleepEffect: 0.5))
        #expect(s.interval == nil)
        #expect(Patterns.describeSleep(s).hasPrefix("Not yet."))
    }

    @Test func clearSleepLinkIsDescribedAsClear() {
        let s = Patterns.sleepScatter(input(days: 40, sleepEffect: 0.6))
        #expect(s.interval?.excludesZero == true)
        #expect(Patterns.describeSleep(s).contains("clearer than chance"))
    }

    @Test func liftComparisonGatesAndDescribes() {
        let g = Patterns.liftGroups(input(days: 40, sleepEffect: 0, liftBoost: 0.4))
        #expect(g.count == 2)
        let text = Patterns.describeLift(g)
        #expect(text.contains("higher"))
        #expect(Patterns.describeLift(Patterns.liftGroups(input(days: 6, sleepEffect: 0))).hasPrefix("Not yet"))
    }

    @Test func descriptionsNeverPrescribe() {
        let i = input(days: 40, sleepEffect: 0.6, liftBoost: 0.4)
        let texts = [Patterns.describeSleep(Patterns.sleepScatter(i)), Patterns.describeLift(Patterns.liftGroups(i)),
                     Patterns.describePhases(Patterns.phaseGroups(i)), Patterns.describeWeeks(Patterns.weeks(i))]
        for t in texts.map({ $0.lowercased() }) {
            for banned in ["you should", "try to", "make sure", "aim for", "need to sleep", "disorder", "depress"] {
                #expect(!t.contains(banned), "\(banned) in \(t)")
            }
        }
    }

    @Test func linksCoverAllQuestions() {
        let l = Patterns.links(input(days: 40, sleepEffect: 0.6))
        #expect(l.map(\.title) == Patterns.questions.map(\.1))
        #expect(l.first { $0.title == "Sleep" }?.interval != nil)
        #expect(l.first { $0.title == "HRV" }?.interval == nil) // no HRV data
    }
}

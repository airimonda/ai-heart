import Foundation

/// Small, honest statistics (docs/03): rank correlation with block-bootstrap intervals,
/// means with intervals, minimum-sample gates. Deterministic, so the same data always
/// gives the same picture.
public enum Stats {
    public struct Interval: Equatable, Sendable {
        public let estimate: Double
        public let low: Double
        public let high: Double
        public let n: Int

        /// The interval excludes zero (for correlations) — "clearer than chance".
        public var excludesZero: Bool { low > 0 || high < 0 }
    }

    /// Seeded generator (SplitMix64) so bootstraps are reproducible.
    public struct RNG: Sendable {
        var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        public mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    public static func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }

    /// Average ranks, ties shared.
    public static func ranks(_ xs: [Double]) -> [Double] {
        let order = xs.indices.sorted { xs[$0] < xs[$1] }
        var r = [Double](repeating: 0, count: xs.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count && xs[order[j + 1]] == xs[order[i]] { j += 1 }
            let avg = Double(i + j) / 2 + 1
            for k in i...j { r[order[k]] = avg }
            i = j + 1
        }
        return r
    }

    public static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let mx = mean(x), my = mean(y)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in x.indices {
            sxy += (x[i] - mx) * (y[i] - my)
            sxx += (x[i] - mx) * (x[i] - mx)
            syy += (y[i] - my) * (y[i] - my)
        }
        guard sxx > 0, syy > 0 else { return 0 }
        return sxy / sqrt(sxx * syy)
    }

    public static func spearman(_ x: [Double], _ y: [Double]) -> Double {
        pearson(ranks(x), ranks(y))
    }

    /// Spearman's rho with a moving-block bootstrap 95% interval. Pairs must be in time
    /// order; blocks keep runs of neighbouring days together, because days are not independent.
    public static func spearmanInterval(_ pairs: [(Double, Double)], block: Int = 5, resamples: Int = 800,
                                        seed: UInt64 = 7) -> Interval? {
        let n = pairs.count
        guard n >= 4 else { return nil }
        let est = spearman(pairs.map(\.0), pairs.map(\.1))
        let b = max(1, min(block, n / 2))
        var rng = RNG(seed: seed)
        var boots: [Double] = []
        boots.reserveCapacity(resamples)
        for _ in 0..<resamples {
            var xs: [Double] = [], ys: [Double] = []
            while xs.count < n {
                let start = rng.int(n - b + 1)
                for k in start..<(start + b) where xs.count < n {
                    xs.append(pairs[k].0); ys.append(pairs[k].1)
                }
            }
            boots.append(spearman(xs, ys))
        }
        boots.sort()
        return Interval(estimate: est, low: boots[Int(0.025 * Double(resamples))],
                        high: boots[Int(0.975 * Double(resamples)) - 1], n: n)
    }

    /// Mean with a bootstrap 95% interval.
    public static func meanInterval(_ xs: [Double], resamples: Int = 800, seed: UInt64 = 11) -> Interval? {
        guard xs.count >= 2 else { return nil }
        var rng = RNG(seed: seed)
        var boots: [Double] = []
        for _ in 0..<resamples {
            var s = 0.0
            for _ in xs { s += xs[rng.int(xs.count)] }
            boots.append(s / Double(xs.count))
        }
        boots.sort()
        return Interval(estimate: mean(xs), low: boots[Int(0.025 * Double(resamples))],
                        high: boots[Int(0.975 * Double(resamples)) - 1], n: xs.count)
    }

    public struct Fit: Sendable {
        public let slope: Double
        public let intercept: Double
        let n: Int
        let mx: Double
        let sxx: Double
        let s: Double

        public func y(_ x: Double) -> Double { intercept + slope * x }

        /// 95% band for the fitted line at x (normal approximation).
        public func band(_ x: Double) -> (Double, Double) {
            let se = s * sqrt(1 / Double(n) + (x - mx) * (x - mx) / sxx)
            return (y(x) - 1.96 * se, y(x) + 1.96 * se)
        }
    }

    public static func linearFit(_ pairs: [(Double, Double)]) -> Fit? {
        guard pairs.count >= 3 else { return nil }
        let x = pairs.map(\.0), y = pairs.map(\.1)
        let mx = mean(x), my = mean(y)
        let sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let rss = zip(x, y).reduce(0) { $0 + pow($1.1 - (intercept + slope * $1.0), 2) }
        let s = sqrt(rss / Double(pairs.count - 2))
        return Fit(slope: slope, intercept: intercept, n: pairs.count, mx: mx, sxx: sxx, s: s)
    }
}

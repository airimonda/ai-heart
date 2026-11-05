import Foundation

/// Mood outlook (M10, docs/03). Ridge regression on her own days with strong shrinkage
/// toward her recent mean; one model per horizon (today, +1, +2). Judged by rolling-origin
/// backtests against two naive baselines; it says "Not yet" until it beats both.
public enum Outlook {
    public struct Day: Sendable {
        public let day: AnchoredDay
        /// Features known on this day (last night's sleep, yesterday's signals, cycle, ...).
        public let features: [Double]
        public let valence: Double?
        public let arousal: Double?
        public init(day: AnchoredDay, features: [Double], valence: Double?, arousal: Double?) {
            self.day = day; self.features = features; self.valence = valence; self.arousal = arousal
        }
    }

    public struct Model: Sendable {
        let mean: [Double]
        let scale: [Double]
        let coef: [Double]
        let intercept: Double
        public let residualSD: Double

        public func predict(_ x: [Double]) -> Double {
            var y = intercept
            for i in x.indices { y += coef[i] * ((x[i] - mean[i]) / scale[i]) }
            return max(-1, min(1, y))
        }

        /// Each feature's pull on the prediction, in the target's units.
        public func contributions(_ x: [Double]) -> [Double] {
            x.indices.map { coef[$0] * ((x[$0] - mean[$0]) / scale[$0]) }
        }
    }

    /// Strong shrinkage: with little data the model stays near her recent mean.
    public static let lambda = 8.0
    public static let minTrain = 21
    public static let recent = 28

    /// Fits target(day t + horizon) from features(day t). Intercept is her recent mean.
    public static func fit(_ days: [Day], horizon: Int, target: KeyPath<Day, Double?>) -> Model? {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let pairs: [([Double], Double)] = days.compactMap { d in
            guard let y = byDay[d.day.adding(days: horizon)]?[keyPath: target] else { return nil }
            return (d.features, y)
        }
        guard pairs.count >= minTrain, let k = pairs.first?.0.count, k > 0 else { return nil }
        let recentYs = pairs.suffix(recent).map(\.1)
        let intercept = recentYs.reduce(0, +) / Double(recentYs.count)
        var mean = [Double](repeating: 0, count: k), scale = [Double](repeating: 1, count: k)
        for j in 0..<k {
            let col = pairs.map { $0.0[j] }
            mean[j] = col.reduce(0, +) / Double(col.count)
            let sd = sqrt(col.map { ($0 - mean[j]) * ($0 - mean[j]) }.reduce(0, +) / Double(col.count))
            scale[j] = sd > 1e-9 ? sd : 1
        }
        let X = pairs.map { p in p.0.indices.map { (p.0[$0] - mean[$0]) / scale[$0] } }
        let y = pairs.map { $0.1 - intercept }
        // (XᵀX + λI) b = Xᵀy
        var A = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var b = [Double](repeating: 0, count: k)
        for r in X.indices {
            for i in 0..<k {
                b[i] += X[r][i] * y[r]
                for j in 0..<k { A[i][j] += X[r][i] * X[r][j] }
            }
        }
        for i in 0..<k { A[i][i] += lambda }
        guard let coef = solve(A, b) else { return nil }
        let preds = X.map { row in intercept + zip(row, coef).map(*).reduce(0, +) }
        let res = zip(preds, pairs.map(\.1)).map { $0 - $1 }
        let sd = sqrt(res.map { $0 * $0 }.reduce(0, +) / Double(max(1, res.count - 1)))
        return Model(mean: mean, scale: scale, coef: coef, intercept: intercept, residualSD: max(sd, 0.05))
    }

    static func solve(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        var M = A, v = b
        let n = v.count
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(M[$0][c]) < abs(M[$1][c]) }), abs(M[p][c]) > 1e-12 else { return nil }
            M.swapAt(c, p); v.swapAt(c, p)
            for r in 0..<n where r != c {
                let f = M[r][c] / M[c][c]
                for k in c..<n { M[r][k] -= f * M[c][k] }
                v[r] -= f * v[c]
            }
        }
        return (0..<n).map { v[$0] / M[$0][$0] }
    }

    // MARK: Track record

    public struct Record: Sendable {
        public let n: Int
        public let modelError: Double
        public let yesterdayError: Double
        public let weekError: Double
        /// Close: within 0.2 on the pleasant scale.
        public let close: Int
        public let points: [(expected: Double, actual: Double)]
        /// True only when it beats both baselines by at least 5% over 28+ days.
        public var beatsBaselines: Bool { n >= 28 && modelError < 0.95 * min(yesterdayError, weekError) }
        /// Rough days still needed before it can be judged.
        public var daysNeeded: Int { max(0, 28 - n) }
    }

    /// Rolling origin: for each day, fit on days before it only, predict it, compare.
    public static func backtest(_ days: [Day], target: KeyPath<Day, Double?>, maxPoints: Int = 60) -> Record {
        let sorted = days.sorted { $0.day < $1.day }
        var mErr: [Double] = [], yErr: [Double] = [], wErr: [Double] = [], pts: [(Double, Double)] = []
        let labeled = sorted.filter { $0[keyPath: target] != nil }
        for d in labeled.suffix(maxPoints) {
            guard let actual = d[keyPath: target] else { continue }
            let past = sorted.filter { $0.day < d.day }
            guard let m = fit(past, horizon: 0, target: target) else { continue }
            let pastY = past.compactMap { $0[keyPath: target] }
            guard let last = pastY.last else { continue }
            let week = Array(pastY.suffix(7))
            let p = m.predict(d.features)
            mErr.append(abs(p - actual))
            yErr.append(abs(last - actual))
            wErr.append(abs(week.reduce(0, +) / Double(week.count) - actual))
            pts.append((p, actual))
        }
        func mean(_ x: [Double]) -> Double { x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count) }
        return Record(n: mErr.count, modelError: mean(mErr), yesterdayError: mean(yErr), weekError: mean(wErr),
                      close: mErr.filter { $0 <= 0.2 }.count, points: pts.map { (expected: $0.0, actual: $0.1) })
    }

    // MARK: Words

    public static func valenceWord(_ v: Double, usual: Double) -> String {
        v > usual + 0.12 ? "leans more pleasant" : v < usual - 0.12 ? "leans lower" : "near your usual"
    }

    public static func arousalWord(_ a: Double, usual: Double) -> String? {
        a > usual + 0.15 ? "a bit stirred" : a < usual - 0.15 ? "a bit still" : nil
    }
}

import Foundation

/// The Patterns tab (docs/03): a small, pre-specified set of questions, never all pairs.
/// Each answer carries n and an interval, is gated on a minimum sample, and is worded as a
/// description with its uncertainty. Nothing here advises.
public struct PatternInput: Sendable {
    /// Mean valence per anchored day, from entries that still have numbers.
    public var mood: [AnchoredDay: Double]
    /// Signal values per anchored day.
    public var signals: [Signal: [AnchoredDay: Double]]
    /// Training load per day: minutes × effort when rated, otherwise minutes × 5.
    public var load: [AnchoredDay: Double]
    public var liftDays: Set<AnchoredDay>
    /// What she did each day, as activity groups (owner, 2026-11-01): walking or jogging,
    /// lifting, aerobics or dance, yoga, other. A day with none is a quiet day.
    public var activityDays: [AnchoredDay: Set<ActivityGroup>] = [:]
    public var phase: @Sendable (AnchoredDay) -> CyclePhase?
    public var today: AnchoredDay

    public init(mood: [AnchoredDay: Double], signals: [Signal: [AnchoredDay: Double]], load: [AnchoredDay: Double],
                liftDays: Set<AnchoredDay>, phase: @escaping @Sendable (AnchoredDay) -> CyclePhase?, today: AnchoredDay) {
        self.mood = mood; self.signals = signals; self.load = load
        self.liftDays = liftDays; self.phase = phase; self.today = today
    }
}

public enum ActivityGroup: String, CaseIterable, Sendable {
    case walk, lift, aerobics, yoga, other

    public var label: String {
        switch self {
        case .walk: "Walk or jog"
        case .lift: "Lift"
        case .aerobics: "Aerobics or dance"
        case .yoga: "Yoga"
        case .other: "Other"
        }
    }

    public static func of(_ k: WorkoutKind) -> ActivityGroup {
        switch k {
        case .walk, .run: .walk
        case .strength: .lift
        case .aerobics, .dance, .hiit: .aerobics
        case .yoga: .yoga
        case .cycle, .swim, .other: .other
        }
    }

    /// A day counts as a walking day without a logged workout when the phone saw enough
    /// movement: 7,000 steps or 20 exercise minutes.
    public static func movedEnough(steps: Double?, exerciseMin: Double?) -> Bool {
        (steps ?? 0) >= 7000 || (exerciseMin ?? 0) >= 20
    }
}

public enum Patterns {
    /// docs/03: gate correlations at 14 paired days.
    public static let minPairs = 14
    /// Each group in a comparison needs at least this many days.
    public static let minGroup = 5

    // MARK: Signals and next-day mood (forest plot)

    public struct Link: Sendable, Identifiable {
        public let id: String
        public let title: String
        /// Nil until there are enough pairs.
        public let interval: Stats.Interval?
        public let pairs: Int
    }

    /// The pre-specified questions. Sleep is the night before the day, so it pairs with the
    /// same anchored day's mood; the rest pair a day's signal with the next day's mood.
    public static let questions: [(Signal?, String, Int)] = [
        (.sleep, "Sleep", 0),
        (.restingHR, "Resting HR", 1),
        (.hrv, "HRV", 1),
        (.wristTemp, "Wrist temp", 1),
        (nil, "Training load", 1),
        (.steps, "Steps", 1),
    ]

    public static func pairs(_ x: [AnchoredDay: Double], mood: [AnchoredDay: Double], lag: Int) -> [(Double, Double)] {
        x.keys.sorted().compactMap { d in
            guard let v = x[d], let m = mood[d.adding(days: lag)] else { return nil }
            return (v, m)
        }
    }

    public static func links(_ input: PatternInput) -> [Link] {
        questions.map { signal, title, lag in
            let x: [AnchoredDay: Double]
            if let signal { x = input.signals[signal] ?? [:] } else {
                // Training load: rest days count as zero, but only on days with any body data.
                var l: [AnchoredDay: Double] = [:]
                for d in (input.signals[.steps] ?? [:]).keys { l[d] = input.load[d] ?? 0 }
                x = l
            }
            let p = pairs(x, mood: input.mood, lag: lag)
            let iv = p.count >= minPairs ? Stats.spearmanInterval(p) : nil
            return Link(id: title, title: title, interval: iv, pairs: p.count)
        }
    }

    // MARK: Sleep and the next day (scatter)

    public struct Scatter: Sendable {
        public let points: [(hours: Double, mood: Double)]
        public let fit: Stats.Fit?
        public let interval: Stats.Interval?
    }

    public static func sleepScatter(_ input: PatternInput) -> Scatter {
        let p = pairs(input.signals[.sleep] ?? [:], mood: input.mood, lag: 0).map { ($0.0 / 60, $0.1) }
        let iv = p.count >= minPairs ? Stats.spearmanInterval(p) : nil
        return Scatter(points: p.map { (hours: $0.0, mood: $0.1) }, fit: p.count >= minPairs ? Stats.linearFit(p) : nil, interval: iv)
    }

    public static func describeSleep(_ s: Scatter) -> String {
        guard let iv = s.interval else { return notYet(s.points.count, minPairs, "nights with an entry the next day") }
        if iv.excludesZero {
            return iv.estimate > 0
                ? "Longer nights went with more pleasant days, and the link is clearer than chance across \(iv.n) nights. It describes your past days, not a rule."
                : "Longer nights went with less pleasant days across \(iv.n) nights, and the link is clearer than chance. That is unusual, so read it with care."
        }
        if abs(iv.estimate) < 0.1 { return "No clear link between sleep and the next day so far, across \(iv.n) nights." }
        return "A gentle \(iv.estimate > 0 ? "upward" : "downward") link, with a wide band. Sleep seems to matter some, but \(iv.n) nights cannot say how much yet."
    }

    // MARK: Group comparisons

    public struct Group: Sendable, Identifiable {
        public let id: String
        public let label: String
        public let interval: Stats.Interval?
        public let n: Int
    }

    public static func liftGroups(_ input: PatternInput) -> [Group] {
        var lift: [Double] = [], rest: [Double] = []
        for (d, m) in input.mood { if input.liftDays.contains(d) { lift.append(m) } else { rest.append(m) } }
        return [group("Lift days", lift), group("Rest days", rest)]
    }

    /// "Any activity" against "Quiet day", then each kind she has enough days of.
    public static func activityGroups(_ input: PatternInput) -> [Group] {
        var moved: [Double] = [], quiet: [Double] = []
        var by: [ActivityGroup: [Double]] = [:]
        for (d, m) in input.mood {
            let acts = input.activityDays[d] ?? []
            if acts.isEmpty { quiet.append(m) } else { moved.append(m) }
            for a in acts { by[a, default: []].append(m) }
        }
        var out = [group("Active days", moved), group("Quiet days", quiet)]
        for a in ActivityGroup.allCases where (by[a]?.count ?? 0) >= minGroup { out.append(group(a.label, by[a]!)) }
        return out
    }

    public static func describeActivity(_ g: [Group]) -> String {
        guard g.count >= 2, let a = g[0].interval, let b = g[1].interval else {
            return "Not yet. This needs at least \(minGroup) active days and \(minGroup) quiet days with entries; there are \(g.first?.n ?? 0) and \(g.count > 1 ? g[1].n : 0)."
        }
        let diff = a.estimate - b.estimate
        var s: String
        if abs(diff) < 0.05 { s = "Mood sat about the same on active days and quiet days." }
        else {
            let word = diff > 0 ? "higher" : "lower"
            s = (a.low > b.high || b.low > a.high)
                ? "Mood sat \(word) on days you moved, and the ranges do not overlap across \(a.n + b.n) days."
                : "Mood sat a little \(word) on days you moved. The ranges overlap, so this is a hint that needs more days."
        }
        let kinds = g.dropFirst(2).compactMap { k in k.interval.map { (k.label, $0.estimate) } }
        if kinds.count >= 2, let best = kinds.max(by: { $0.1 < $1.1 }) {
            s += " Of the kinds with enough days, \(best.0.lowercased()) sat highest."
        }
        return s + " It describes these days, not a rule."
    }

    public static func phaseGroups(_ input: PatternInput) -> [Group] {
        var by: [CyclePhase: [Double]] = [:]
        for (d, m) in input.mood { if let p = input.phase(d) { by[p, default: []].append(m) } }
        return [CyclePhase.follicular, .fertile, .luteal, .period].map { group($0.label, by[$0] ?? []) }
    }

    static func group(_ label: String, _ xs: [Double]) -> Group {
        Group(id: label, label: label, interval: xs.count >= minGroup ? Stats.meanInterval(xs) : nil, n: xs.count)
    }

    public static func describeLift(_ g: [Group]) -> String {
        guard g.count == 2, let a = g[0].interval, let b = g[1].interval else {
            return "Not yet. This needs at least \(minGroup) lift days and \(minGroup) rest days with entries; there are \(g.first?.n ?? 0) and \(g.last?.n ?? 0)."
        }
        let diff = a.estimate - b.estimate
        if abs(diff) < 0.05 { return "Mood sat about the same on lift days and rest days." }
        let word = diff > 0 ? "higher" : "lower"
        if a.low > b.high || b.low > a.high {
            return "Mood sat \(word) on days you lifted, and the ranges do not overlap across \(a.n + b.n) days. It describes these days, not a rule."
        }
        return "Mood sat a little \(word) on days you lifted. The ranges overlap, so this is a hint that needs more days."
    }

    public static func describePhases(_ g: [Group]) -> String {
        let ready = g.filter { $0.interval != nil }
        guard ready.count >= 3 else {
            return "Not yet. Each phase needs at least \(minGroup) days with entries."
        }
        let low = ready.min { $0.interval!.estimate < $1.interval!.estimate }!
        let others = ready.filter { $0.id != low.id }
        let apart = others.allSatisfy { $0.interval!.low > low.interval!.high }
        if apart {
            return "\(low.label) days sat lower, and the range does not overlap the others across \(low.n) days. Cycle effects on mood differ a lot between people; this is yours."
        }
        if others.contains(where: { $0.interval!.estimate - low.interval!.estimate > 0.1 }) {
            return "\(low.label) days sat lower in this sample. The ranges overlap and \(low.n) days is not many, so read it as a hint."
        }
        return "No phase stands apart so far."
    }

    // MARK: Training and recovery (8 weeks)

    public struct Week: Sendable, Identifiable {
        public let index: Int   // 0 = oldest
        public let load: Double
        public let hrv: Double?
        public var id: Int { index }
    }

    public static func weeks(_ input: PatternInput, count: Int = 8) -> [Week] {
        (0..<count).map { w in
            let end = input.today.adding(days: -7 * (count - 1 - w))
            let days = (0..<7).map { end.adding(days: -$0) }
            let load = days.reduce(0) { $0 + (input.load[$1] ?? 0) }
            let hrvs = days.compactMap { input.signals[.hrv]?[$0] }
            return Week(index: w, load: load, hrv: hrvs.isEmpty ? nil : Stats.mean(hrvs))
        }
    }

    public static func describeWeeks(_ w: [Week]) -> String {
        let paired = w.compactMap { x in x.hrv.map { (x.load, $0) } }.filter { $0.0 > 0 }
        guard paired.count >= 6 else { return "Not yet. This needs six weeks with training and HRV readings." }
        let rho = Stats.spearman(paired.map(\.0), paired.map(\.1))
        // Eight points cannot carry an interval worth showing, so this stays a description.
        if rho < -0.3 { return "In heavier weeks your HRV tended to run lower, and higher in lighter ones. That is a common shape. Cycle phase can shift HRV too." }
        if rho > 0.3 { return "In heavier weeks your HRV tended to run higher. Eight weeks is a short window, so read it loosely." }
        return "No clear shape between weekly training and HRV over these eight weeks."
    }

    static func notYet(_ n: Int, _ need: Int, _ what: String) -> String {
        "Not yet. This needs \(need) \(what); there are \(n)."
    }
}

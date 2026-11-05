import Foundation

/// Turns her days into outlook features, fits one model per horizon, and produces what the
/// Mood outlook screen shows (M10, docs/03). Statistics only; the words the LLM writes are
/// checked against `facts`.
public enum OutlookBuilder {
    public enum Feature: String, CaseIterable, Sendable {
        case shortSleep, sleepShift, sleepIrregular, restingHR, lowHRV, luteal, lifted, doseChange

        /// Mid-sentence form: first letter lowered, acronyms kept.
        public var phrase: String {
            label.hasPrefix("HRV") ? label : label.prefix(1).lowercased() + label.dropFirst()
        }

        public var label: String {
            switch self {
            case .shortSleep: "Short sleep"
            case .sleepShift: "Sleep timing shifted"
            case .sleepIrregular: "Sleep less regular"
            case .restingHR: "Resting heart rate up"
            case .lowHRV: "HRV a bit low"
            case .luteal: "Luteal day"
            case .lifted: "Lifted yesterday"
            case .doseChange: "Dose change"
            }
        }
    }

    /// What is known about one day. z values are against her own usual; nil is missing.
    public struct DayInput: Sendable {
        public var day: AnchoredDay
        public var sleepZ: Double?
        /// How far the middle of last night's sleep sits from her usual, as a size (z, 0 or more).
        public var sleepShiftZ: Double?
        /// How uneven the last 7 nights were against her usual unevenness (z).
        public var sleepIrregularZ: Double?
        public var restingHRZ: Double?
        public var hrvZ: Double?
        public var luteal: Bool?
        /// Strength or hard training minutes the day before.
        public var liftedYesterdayMin: Double
        /// Days since the latest dose change, if any.
        public var daysSinceDose: Int?
        public var valence: Double?
        public var arousal: Double?
        public init(day: AnchoredDay, sleepZ: Double? = nil, restingHRZ: Double? = nil, hrvZ: Double? = nil, luteal: Bool? = nil,
                    sleepShiftZ: Double? = nil, sleepIrregularZ: Double? = nil, liftedYesterdayMin: Double = 0, daysSinceDose: Int? = nil, valence: Double? = nil, arousal: Double? = nil) {
            self.day = day; self.sleepZ = sleepZ; self.restingHRZ = restingHRZ; self.hrvZ = hrvZ; self.luteal = luteal
            self.sleepShiftZ = sleepShiftZ; self.sleepIrregularZ = sleepIrregularZ
            self.liftedYesterdayMin = liftedYesterdayMin; self.daysSinceDose = daysSinceDose; self.valence = valence; self.arousal = arousal
        }
    }

    public struct Options: Sendable {
        public var useCycle = true, useDoses = true, useTraining = true
        public init(useCycle: Bool = true, useDoses: Bool = true, useTraining: Bool = true) {
            self.useCycle = useCycle; self.useDoses = useDoses; self.useTraining = useTraining
        }
        var features: [Feature] {
            Feature.allCases.filter {
                switch $0 {
                case .luteal: useCycle
                case .doseChange: useDoses
                case .lifted: useTraining
                default: true
                }
            }
        }
    }

    /// Missing signals count as "at her usual" (0), so a day without a watch reading still
    /// counts; the screen says how many days had each signal.
    static func value(_ f: Feature, _ d: DayInput) -> Double {
        switch f {
        case .shortSleep: -(d.sleepZ ?? 0)
        // Only the unusual side counts: later or earlier than usual, and more uneven than usual.
        case .sleepShift: max(0, d.sleepShiftZ ?? 0)
        case .sleepIrregular: max(0, d.sleepIrregularZ ?? 0)
        case .restingHR: d.restingHRZ ?? 0
        case .lowHRV: -(d.hrvZ ?? 0)
        case .luteal: (d.luteal ?? false) ? 1 : 0
        case .lifted: min(d.liftedYesterdayMin, 120) / 60
        case .doseChange: d.daysSinceDose.map { $0 >= 0 && $0 < 42 ? 1 : 0 } ?? 0
        }
    }

    public struct Point: Sendable {
        public let day: AnchoredDay
        public let valence: Double
        public let arousal: Double
        /// 80% band on valence.
        public let low: Double, high: Double
        public let valenceWord: String
        public let arousalWord: String?
    }

    public struct Driver: Sendable, Identifiable {
        public var id: String { feature.rawValue }
        public let feature: Feature
        /// Signed pull on valence and arousal.
        public let valence: Double, arousal: Double
        public var direction: String {
            if abs(valence) < 0.01 && abs(arousal) < 0.01 { return feature == .doseChange ? "none recently" : "no pull now" }
            if abs(arousal) > abs(valence) { return arousal > 0 ? "toward stirred" : "toward still" }
            return valence > 0 ? "toward pleasant" : "toward lower"
        }
        public var size: Double { max(abs(valence), abs(arousal)) }
    }

    public struct Result: Sendable {
        public let daysWithMood: Int
        public let usualValence: Double, usualArousal: Double
        public let points: [Point]          // today, +1, +2
        public let drivers: [Driver]
        public let record: Outlook.Record
        public let daysNeeded: Int
        /// Plain facts for the LLM and the fallback read. Every number shown comes from here.
        public let facts: [String: String]
    }

    public static let horizons = [0, 1, 2]

    /// Nil when there is not enough mood history yet (`Outlook.minTrain` days).
    public static func build(_ inputs: [DayInput], today: AnchoredDay, options: Options = .init()) -> Result? {
        let feats = options.features
        let sorted = inputs.sorted { $0.day < $1.day }
        let days = sorted.map { d in Outlook.Day(day: d.day, features: feats.map { f in value(f, d) }, valence: d.valence, arousal: d.arousal) }
        let withMood = sorted.filter { $0.valence != nil }.count
        guard let todayInput = sorted.last(where: { $0.day == today }) ?? sorted.last else { return nil }
        let x = feats.map { value($0, todayInput) }
        var points: [Point] = []
        var v0: Outlook.Model?, a0: Outlook.Model?
        let recentV = sorted.compactMap(\.valence).suffix(Outlook.recent)
        let recentA = sorted.compactMap(\.arousal).suffix(Outlook.recent)
        guard !recentV.isEmpty else { return nil }
        let usualV = recentV.reduce(0, +) / Double(recentV.count)
        let usualA = recentA.isEmpty ? 0 : recentA.reduce(0, +) / Double(recentA.count)
        for h in horizons {
            guard let mv = Outlook.fit(days, horizon: h, target: \.valence) else { return nil }
            let ma = Outlook.fit(days, horizon: h, target: \.arousal)
            if h == 0 { v0 = mv; a0 = ma }
            let v = mv.predict(x), a = ma?.predict(x) ?? usualA
            let half = 1.2816 * mv.residualSD * (1 + 0.15 * Double(h))
            points.append(Point(day: today.adding(days: h), valence: v, arousal: a,
                                low: max(-1, v - half), high: min(1, v + half),
                                valenceWord: Outlook.valenceWord(v, usual: usualV), arousalWord: Outlook.arousalWord(a, usual: usualA)))
        }
        let cv = v0!.contributions(x), ca = a0?.contributions(x) ?? Array(repeating: 0, count: feats.count)
        let drivers = feats.indices.map { Driver(feature: feats[$0], valence: cv[$0], arousal: ca[$0]) }
            .sorted { $0.size > $1.size }
        let record = Outlook.backtest(days, target: \.valence)

        var facts: [String: String] = [
            "days_with_mood": "\(withMood)",
            "today": points[0].valenceWord + (points[0].arousalWord.map { ", " + $0 } ?? ""),
            "tomorrow": points[1].valenceWord + (points[1].arousalWord.map { ", " + $0 } ?? ""),
            "day_after": points[2].valenceWord + (points[2].arousalWord.map { ", " + $0 } ?? ""),
            "track_record_days": "\(record.n)",
            "close_days": "\(record.close)",
            "beats_simple_guesses": record.beatsBaselines ? "yes" : "not yet",
        ]
        for (i, d) in drivers.prefix(3).enumerated() where d.size >= 0.01 {
            facts["driver_\(i + 1)"] = "\(d.feature.phrase) (\(d.direction))"
        }
        if let s = todayInput.sleepZ { facts["sleep_vs_usual"] = s < -0.5 ? "shorter than usual" : s > 0.5 ? "longer than usual" : "near usual" }
        return Result(daysWithMood: withMood, usualValence: usualV, usualArousal: usualA, points: points, drivers: drivers,
                      record: record, daysNeeded: record.daysNeeded, facts: facts)
    }

    /// Days of mood history still needed before the outlook can be fitted.
    public static func daysUntilReady(_ inputs: [DayInput]) -> Int {
        max(0, Outlook.minTrain + 2 - inputs.filter { $0.valence != nil }.count)
    }

    /// "What if I sleep more?": today's inputs with sleep at her usual plus one unit.
    public static func whatIfMoreSleep(_ inputs: [DayInput], today: AnchoredDay, options: Options = .init()) -> (now: Double, more: Double)? {
        let feats = options.features
        let days = inputs.map { d in Outlook.Day(day: d.day, features: feats.map { f in value(f, d) }, valence: d.valence, arousal: d.arousal) }
        guard let m = Outlook.fit(days, horizon: 1, target: \.valence), let t = inputs.first(where: { $0.day == today }) else { return nil }
        var more = t; more.sleepZ = max(t.sleepZ ?? 0, 0) + 1
        return (m.predict(feats.map { value($0, t) }), m.predict(feats.map { value($0, more) }))
    }

    /// The plain read when the on-device model is off or its answer fails the checks.
    public static func fallbackRead(_ r: Result) -> String {
        func sentence(_ p: Point) -> String {
            let v = p.valenceWord == "near your usual" ? "is near your usual" : p.valenceWord
            return v + (p.arousalWord.map { ", \($0)" } ?? "")
        }
        var s = "From \(r.daysWithMood) days of your own entries, today \(sentence(r.points[0]))."
        let ds = r.drivers.filter { $0.size >= 0.01 }.prefix(2)
        if !ds.isEmpty {
            s += " The biggest pulls are " + ds.map { "\($0.feature.phrase) (\($0.direction))" }.joined(separator: " and ") + "."
        }
        s += " Tomorrow \(sentence(r.points[1]))."
        return s
    }

    public static func factsJSON(_ r: Result) -> String {
        let pairs = r.facts.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \"\($0.value)\"" }
        return "{" + pairs.joined(separator: ", ") + "}"
    }
}

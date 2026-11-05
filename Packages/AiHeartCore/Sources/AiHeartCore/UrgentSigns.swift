import Foundation

/// Urgent signs (owner decision, 2026-11-01, CLAUDE.md #3 exception). She asked to be told
/// when what she logs points toward an emergency. This only checks fixed, widely published
/// red-flag thresholds and combinations. It never names a condition, never gives a dose or
/// treatment, and never says she is fine: no alert does not mean all is well.
public enum UrgentSigns {
    public enum Sign: String, CaseIterable, Sendable {
        case chestPain, hardToBreathe, fainted, confused, fever

        public var label: String {
            switch self {
            case .chestPain: "Chest pain or pressure"
            case .hardToBreathe: "Hard to breathe"
            case .fainted: "Fainted or nearly"
            case .confused: "Confused or very drowsy"
            case .fever: "Fever"
            }
        }
    }

    public struct Input: Sendable {
        public var heartRate: Double?
        public var systolic: Double?
        public var diastolic: Double?
        public var signs: Set<Sign>
        /// Body words from today's entries (Sensations vocabulary).
        public var sensations: Set<String>
        public init(heartRate: Double? = nil, systolic: Double? = nil, diastolic: Double? = nil,
                    signs: Set<Sign> = [], sensations: Set<String> = []) {
            self.heartRate = heartRate; self.systolic = systolic; self.diastolic = diastolic
            self.signs = signs; self.sensations = sensations
        }
    }

    public struct Finding: Equatable, Sendable, Identifiable {
        public let id: String
        /// What she logged, described plainly.
        public let what: String
        /// Why it matters, without naming a condition.
        public let why: String
    }

    // Published thresholds: blood pressure 180/120 or higher (AHA "hypertensive crisis"
    // reading); resting heart rate above 120 or below 40 bpm.
    public static let systolicHigh = 180.0, diastolicHigh = 120.0
    public static let hrHigh = 120.0, hrLow = 40.0

    /// What the table rows look at: today's logged heart rate, signs and body words.
    struct Context {
        var heartRate: Double?
        var signs: Set<Sign>
        /// Lowercased.
        var sensations: Set<String>

        func hasAny(_ words: [String]) -> Bool { words.contains { sensations.contains($0) } }
    }

    /// A combination of what she logged that doctors list as a reason to get checked
    /// urgently. Fixed, published rows only, named by what she logged and never by a
    /// condition. Rules here use her logged signs, not lab values, so no row is keyed by a lab marker.
    struct Combination {
        let id: String
        let matches: (Context) -> Bool
        let what: (Context) -> String
        let why: String
        /// Stands in for the plain "confused" finding when it applies.
        let coversConfusion: Bool
    }

    static let combinationWhy = "Doctors ask people to get checked urgently when these show up together."

    static let combinations: [Combination] = [
        Combination(
            id: "racingHeat",
            matches: { c in
                let fastHeart = (c.heartRate.map { $0 > 110 } ?? false) || c.hasAny(["racing"])
                let heat = c.signs.contains(.fever) || c.hasAny(["hot", "sweaty", "flushed"])
                let agitated = c.signs.contains(.confused) || c.hasAny(["shaky", "jittery", "restless"])
                return fastHeart && heat && agitated
            },
            what: { _ in "Racing heart, heat or fever, and shakiness or confusion together" },
            why: combinationWhy, coversConfusion: true),
        Combination(
            id: "drowsyCold",
            matches: { c in
                let slowHeart = c.heartRate.map { $0 < 50 } ?? false
                return c.signs.contains(.confused) && (slowHeart || c.hasAny(["cold", "chilly"]))
            },
            what: { c in
                let slowHeart = c.heartRate.map { $0 < 50 } ?? false
                return "Confusion or heavy drowsiness with \(slowHeart ? "a slow heart" : "feeling very cold")"
            },
            why: combinationWhy, coversConfusion: true),
    ]

    public static func check(_ x: Input) -> [Finding] {
        var out: [Finding] = []
        let s = Set(x.sensations.map { $0.lowercased() })
        func n(_ v: Double) -> String { String(Int(v.rounded())) }

        if let sys = x.systolic, let dia = x.diastolic, sys >= systolicHigh || dia >= diastolicHigh {
            out.append(Finding(id: "bp", what: "Blood pressure \(n(sys))/\(n(dia))",
                               why: "Readings at 180/120 or above can need urgent care, more so with headache, chest pain, changes in vision, or weakness on one side."))
        }
        if let hr = x.heartRate, hr > hrHigh || hr < hrLow {
            out.append(Finding(id: "hr", what: "Heart rate \(n(hr)) at rest",
                               why: "A resting heart rate above 120 or below 40 can need urgent care, more so with dizziness, fainting, or chest pain."))
        }
        if x.signs.contains(.chestPain) {
            out.append(Finding(id: "chest", what: "Chest pain or pressure", why: "Chest pain can need urgent care. It is safest to have it checked now."))
        }
        if x.signs.contains(.hardToBreathe) {
            out.append(Finding(id: "breath", what: "Hard to breathe", why: "Trouble breathing can need urgent care."))
        }
        if x.signs.contains(.fainted) {
            out.append(Finding(id: "faint", what: "Fainted or nearly fainted", why: "Fainting can need urgent care, more so with a racing or very slow heart."))
        }
        let ctx = Context(heartRate: x.heartRate, signs: x.signs, sensations: s)
        for row in combinations where row.matches(ctx) {
            out.append(Finding(id: row.id, what: row.what(ctx), why: row.why))
        }
        let covered = out.contains { f in combinations.contains { $0.id == f.id && $0.coversConfusion } }
        if x.signs.contains(.confused), !covered {
            out.append(Finding(id: "confused", what: "Confused or very drowsy", why: "Sudden confusion can need urgent care."))
        }
        return out
    }

    /// Local emergency number by the phone's region.
    public static func emergencyNumber(region: String?) -> String {
        switch region {
        case "JP": "119"
        case "PH", "US", "CA": "911"
        case "GB": "999"
        case "AU": "000"
        default: "112"
        }
    }

    /// Plausible typed values only; anything else is ignored rather than alarming her.
    public static func plausible(hr: Double?) -> Double? { hr.flatMap { (20...250).contains($0) ? $0 : nil } }
    public static func plausible(systolic: Double?, diastolic: Double?) -> (Double, Double)? {
        guard let s = systolic, let d = diastolic, (60...280).contains(s), (30...180).contains(d), s > d else { return nil }
        return (s, d)
    }
}

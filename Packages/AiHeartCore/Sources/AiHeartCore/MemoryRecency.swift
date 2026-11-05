import Foundation

/// Talk memories are never forgotten, but they fade with age (owner, 2026-11-05): a forget gate with a
/// half-life of 90 days and a floor, so an old memory ranks lower but never vanishes.
public enum MemoryRecency {
    public static let halfLifeDays = 90.0
    public static let floor = 0.15

    /// w = max(0.15, 0.5^(ageDays / 90)). A date in the future counts as today.
    public static func weight(ageDays: Double) -> Double {
        max(floor, pow(0.5, max(0, ageDays) / halfLifeDays))
    }

    public static func weight(of date: Date, now: Date = Date()) -> Double {
        weight(ageDays: now.timeIntervalSince(date) / 86400)
    }

    /// "from about 3 months ago", for the model and the screen. Approximate on purpose: it says how old a
    /// memory is, not what exactly was said.
    public static func ageText(of date: Date, now: Date = Date()) -> String {
        let days = max(0, now.timeIntervalSince(date) / 86400)
        switch days {
        case ..<2: return "from today or yesterday"
        case ..<14: return "from about \(Int(days.rounded())) days ago"
        case ..<60:
            let w = Int((days / 7).rounded())
            return "from about \(w) weeks ago"
        case ..<730:
            let m = max(2, Int((days / 30).rounded()))
            return "from about \(m) months ago"
        default:
            return "from about \(Int((days / 365).rounded())) years ago"
        }
    }
}

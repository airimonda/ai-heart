import Foundation

/// A lean for today's mood from her body, using only links her own history shows clearly
/// (owner's request for Now; the full outlook with a track record is M10). Always worded
/// as a lean, never a prediction, and switchable off (docs/06: expectation effects).
public enum MoodLean {
    public enum Direction: Equatable, Sendable { case morePleasant, lessPleasant, usual }

    public struct Result: Equatable, Sendable {
        public let direction: Direction
        /// Titles of the signals behind it, strongest first.
        public let from: [String]
        public let days: Int
    }

    /// - Parameters:
    ///   - links: her pattern links (rank correlations with next-day mood; sleep same day).
    ///   - z: the z-score each link applies to today: last night's sleep, yesterday's others.
    public static func compute(links: [Patterns.Link], z: [String: Double]) -> Result? {
        let clear = links.compactMap { l -> (String, Double, Int)? in
            guard let iv = l.interval, iv.excludesZero, let zz = z[l.title] else { return nil }
            return (l.title, iv.estimate * max(-2.5, min(2.5, zz)), iv.n)
        }
        guard !clear.isEmpty else { return nil }
        let score = clear.map(\.1).reduce(0, +)
        let direction: Direction = score > 0.15 ? .morePleasant : score < -0.15 ? .lessPleasant : .usual
        let from = clear.filter { abs($0.1) > 0.05 }.sorted { abs($0.1) > abs($1.1) }.map(\.0)
        return Result(direction: direction, from: from, days: clear.map(\.2).max() ?? 0)
    }

    public static func sentence(_ r: Result?) -> String {
        guard let r else { return "Not yet. A lean needs more days where your body and your entries line up clearly." }
        let lead: String
        switch r.direction {
        case .morePleasant: lead = "Days like this have tended to feel a little more pleasant for you."
        case .lessPleasant: lead = "Days like this have tended to feel a little less pleasant for you."
        case .usual: lead = "Days like this have tended to feel like your usual."
        }
        let basis = r.from.isEmpty ? "" : " From \(list(r.from.map { $0.lowercased() == "hrv" ? "HRV" : $0.lowercased().replacingOccurrences(of: "resting hr", with: "resting HR") }))."
        return lead + basis + " A lean, not a rule."
    }

    static func list(_ xs: [String]) -> String {
        switch xs.count {
        case 0: ""
        case 1: xs[0]
        case 2: "\(xs[0]) and \(xs[1])"
        default: xs.dropLast().joined(separator: ", ") + " and " + xs.last!
        }
    }
}

/// One optional thing to write about. Plain, open, no therapy-speak, no guilt. Some follow
/// the body (a short night, a stirred body); most do not.
public enum WritingPrompts {
    public static let general = [
        "What is one thing your body noticed today?",
        "Something small that went okay.",
        "Where did your attention keep going?",
        "A sound, smell or colour from today.",
        "What would you like to remember about today?",
        "Who did you talk to, and how did it feel after?",
        "What did you need today?",
        "A moment you would replay.",
        "What took more energy than you expected?",
        "What is on your mind right now, in a few words?",
        "Something you are looking forward to, however small.",
        "How did today start?",
    ]

    public static func bodyPrompts(_ body: BodyToday?) -> [String] {
        guard let body else { return [] }
        var out: [String] = []
        if (body.sleepZ ?? 0) < -1 { out.append("How did the short night show up today?") }
        if (body.sleepZ ?? 0) > 1 { out.append("You slept longer than usual. How does that feel?") }
        if (body.restingHRZ ?? 0) > 1 || (body.hrvZ ?? 0) < -1 { out.append("Your body looks a little stirred today. Does that match?") }
        if (body.restingHRZ ?? 0) < -1 && (body.hrvZ ?? 0) > 1 { out.append("Your body looks settled today. Does that match?") }
        return out
    }

    /// A body-related prompt first when the body stands out; otherwise one per day.
    /// `skip` moves on when she asks for another.
    public static func pick(day: AnchoredDay, body: BodyToday?, skip: Int = 0) -> String {
        let fromBody = bodyPrompts(body)
        if skip == 0, let first = fromBody.first { return first }
        let pool = fromBody + general
        return pool[(abs(day.ordinal) + skip) % pool.count]
    }
}

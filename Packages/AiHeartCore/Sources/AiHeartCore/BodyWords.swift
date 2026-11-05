import Foundation

/// Today's signals against her own usual (robust z-scores). Nil means no data or no baseline yet.
public struct BodyToday: Equatable, Sendable {
    public var sleep: Reading?
    public var sleepZ: Double?
    public var restingHR: Reading?
    public var restingHRZ: Double?
    public var hrv: Reading?
    public var hrvZ: Double?

    public init(sleepZ: Double? = nil, restingHRZ: Double? = nil, hrvZ: Double? = nil) {
        self.sleepZ = sleepZ
        self.restingHRZ = restingHRZ
        self.hrvZ = hrvZ
        self.sleep = sleepZ.map(BodyToday.reading)
        self.restingHR = restingHRZ.map(BodyToday.reading)
        self.hrv = hrvZ.map(BodyToday.reading)
    }

    static func reading(_ z: Double) -> Reading {
        switch z {
        case ..<(-2): .below
        case ..<(-1): .littleBelow
        case ...1: .within
        case ...2: .littleAbove
        default: .above
        }
    }

    public var hasAny: Bool { sleepZ != nil || restingHRZ != nil || hrvZ != nil }
}

public struct WordSuggestions: Equatable, Sendable {
    /// Always four: one from each quadrant of the pad, so opposites are always offered.
    public let words: [String]
    /// Plain notes about what stood out, e.g. "sleep under your usual". Empty if nothing did.
    public let notes: [String]
    public let fromBody: Bool

    public init(words: [String], notes: [String], fromBody: Bool) {
        self.words = words; self.notes = notes; self.fromBody = fromBody
    }
}

/// Words that might fit, guessed from today's body against her own usual (docs/01).
/// The set stays balanced (one word per quadrant) and nothing is pre-selected; the body
/// only picks which word stands for each quadrant and the order.
/// Suggested words can bias reports (docs/12 #5), so the guess is mild and always explained.
public enum BodyWords {
    public static func suggest(_ body: BodyToday?, paused: Bool = false) -> WordSuggestions {
        guard !paused, let body, body.hasAny else {
            return WordSuggestions(words: MoodWords.staticSuggestions, notes: [], fromBody: false)
        }
        let shortSleep = (body.sleepZ ?? 0) < -1
        // Higher resting HR and lower HRV both point to a more stirred body.
        let stirredParts = [body.restingHRZ, body.hrvZ.map { -$0 }].compactMap { $0 }
        let stirred = stirredParts.isEmpty ? 0 : stirredParts.reduce(0, +) / Double(stirredParts.count)

        let stirredUnpleasant = shortSleep && stirred > 0.5 ? "Wired" : (stirred > 1 ? "Restless" : "Tense")
        let stillUnpleasant = shortSleep ? "Tired" : (stirred < -1 ? "Heavy" : "Flat")
        let stirredPleasant = stirred > 1 ? "Excited" : "Bright"
        let stillPleasant = shortSleep ? "Content" : "Calm"

        // Lead with the side of the pad the body leans toward; keep all four.
        var ordered: [String]
        if stirred > 0.5 || shortSleep && stirred > 0 {
            ordered = [stirredUnpleasant, stillUnpleasant, stirredPleasant, stillPleasant]
        } else if shortSleep || stirred < -0.5 {
            ordered = [stillUnpleasant, stirredUnpleasant, stillPleasant, stirredPleasant]
        } else {
            ordered = [stillPleasant, stirredPleasant, stirredUnpleasant, stillUnpleasant]
        }
        ordered = ordered.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }

        var notes: [String] = []
        if let r = body.sleep, r != .within { notes.append("sleep " + note(r, up: "over", down: "under")) }
        if let r = body.restingHR, r != .within { notes.append("resting HR " + note(r)) }
        if let r = body.hrv, r != .within { notes.append("HRV " + note(r)) }
        return WordSuggestions(words: ordered, notes: notes, fromBody: true)
    }

    static func note(_ r: Reading, up: String = "above", down: String = "below") -> String {
        switch r {
        case .within: "within your usual"
        case .littleAbove: "a little \(up) your usual"
        case .littleBelow: "a little \(down) your usual"
        case .above: "\(up) your usual"
        case .below: "\(down) your usual"
        }
    }

    /// One calm line for the Now strip.
    public static func stripLine(_ s: WordSuggestions) -> String {
        guard s.fromBody else { return "" }
        guard let first = s.notes.first else { return "Your body looks like your usual." }
        return first.prefix(1).uppercased() + first.dropFirst() + "."
    }

    /// Caption above the words.
    public static func caption(_ s: WordSuggestions) -> String {
        guard s.fromBody else { return "Words. One tap saves." }
        // The details sit on the Now strip and on How does it feel; keep this line short (screen 02).
        return "Words that might fit, guessed from your body. One tap saves."
    }
}

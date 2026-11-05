import Foundation

/// The model's part in keep or release (docs/17), shared by the app and the distress eval so both
/// run the same logic. Rules decide first; the model may only make a decision safer (keep, safety,
/// heavy), except one case it has had since M9: a "not mainly a retelling" answer lowers confidence.
public enum ModelChecks {
    public static let system = "Answer with one word: yes or no."

    public static func selfHarmQuestion(_ text: String) -> String {
        "Does this text mention self-harm or suicide? Answer yes or no.\n\n\(text)"
    }
    public static func hopelessQuestion(_ text: String) -> String {
        "Does the writer sound hopeless, at the end of what they can take, or unable to cope? Answer yes or no.\n\n\(text)"
    }
    public static func shameQuestion(_ text: String) -> String {
        "Is this text mainly about something the writer feels embarrassed or ashamed of? Answer yes or no.\n\n\(text)"
    }

    /// "yes" / "no" / nil when unclear.
    public static func yesNo(_ raw: String?) -> Bool? {
        guard let l = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        if l.hasPrefix("yes") { return true }
        if l.hasPrefix("no") { return false }
        return nil
    }

    /// What the model said, or that it could not be asked at all (error, unreachable, not loaded).
    public enum Answer: Equatable, Sendable { case yes, no, unclear, unavailable }

    /// Which questions to ask, given the rule decision. The answers arrive through `ask`.
    /// For callers that cannot tell "unclear" from "could not run" (the eval harness).
    public static func decide(text: String?, word: String?, valence: Double?,
                              ask: (String) async -> Bool?) async -> KeepOrRelease.Decision {
        await decideChecked(text: text, word: word, valence: valence) { prompt in
            switch await ask(prompt) { case .some(true): .yes; case .some(false): .no; case .none: .unclear }
        }
    }

    /// Same, where "the model could not run" counts as unsure (owner, 2026-11-05): an entry the rules
    /// would let go is kept instead, never let go on rules alone. After the first failure nothing more is
    /// asked, so an unreachable model costs one wait, not three.
    public static func decideChecked(text: String?, word: String?, valence: Double?,
                                     ask: (String) async -> Answer) async -> KeepOrRelease.Decision {
        var down = false
        func q(_ prompt: String) async -> Answer {
            if down { return .unavailable }
            let a = await ask(prompt)
            if a == .unavailable { down = true }
            return a
        }
        var decision = KeepOrRelease.decide(text: text, word: word, valence: valence)
        if case .letGo = decision, let text {
            if await q(selfHarmQuestion(text)) == .yes {
                decision = .safetyKeep
            } else if await q(hopelessQuestion(text)) == .yes {
                // Keywords miss heavy entries written in her own words. A wrong yes only keeps an entry.
                decision = .heavyKeep
            } else if await q(shameQuestion(text)) == .no {
                decision = KeepOrRelease.decide(text: text, word: word, valence: valence, themeIsShameful: false)
            }
            if down { return .keep }
        }
        // Kept entries are asked too: the distress eval found short entries with no keywords
        // ("I don't see the point of waking up tomorrow") kept silently while the model said yes.
        // Any entry of three words or more. A yes only ever makes the outcome safer.
        if case .keep = decision, let text, MoodGuess.wordCount(text) >= 3 || MoodGuess.cjkCount(text) >= 6 {
            if await q(selfHarmQuestion(text)) == .yes {
                decision = .safetyKeep
            } else if await q(hopelessQuestion(text)) == .yes {
                decision = .heavyKeep
            } else if await q(shameQuestion(text)) == .yes {
                // Embarrassing in her own words but without the usual words: offered, never automatic.
                decision = KeepOrRelease.decide(text: text, word: word, valence: valence, themeIsShameful: true)
            }
        }
        return decision
    }
}

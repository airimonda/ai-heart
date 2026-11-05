import Foundation

/// Automatic keep or release (M9, docs/03). Default is keep. An entry is let go only when it
/// is confidently hard; unsure means keep. Self-harm is never let go. For a let-go entry only
/// her own sentences are kept (never rewritten): what helped, what she needed, what she
/// learned, a strength or value, or a next small step she named.
public enum KeepOrRelease {
    public enum Decision: Equatable, Sendable {
        case keep
        case letGo(keptLines: [String], confidence: Double)
        /// Mentions self-harm: kept, and the safety page opens.
        case safetyKeep
        /// Reads as hopeless or at the limit: kept (never let go), and the "This looks heavy"
        /// card shows. Hopelessness is a warning sign worth keeping for her clinician (docs/17).
        case heavyKeep
    }

    /// Hopelessness and "at my limit" phrases. Never let go. English, Japanese, Tagalog.
    static let hopeless = [
        "hopeless", "no hope", "no way out", "no point", "pointless", "nothing matters", "worthless", "no future",
        "never get better", "won't get better", "will never change", "trapped", "i'm a burden", "i am a burden",
        "give up", "giving up", "can't go on", "can't take it anymore", "can't do this anymore", "cant do this anymore",
        "what's the use", "whats the use", "ayoko na",
        "絶望", "希望がない", "意味がない", "もう無理", "限界", "生きる意味",
        "wala nang pag-asa", "walang pag-asa", "walang silbi", "suko na ako", "hindi ko na kaya", "di ko na kaya",
    ]

    public static func readsHopeless(_ text: String) -> Bool {
        let t = SafetyCheck.normalised(text)
        return hopeless.contains { t.contains(SafetyCheck.normalised($0)) } || ListenSafety.feelsHeavy(text)
    }

    public static let threshold = 0.8
    /// "Clearly low" on the pleasant axis.
    public static let lowValence = -0.35

    /// Words that read as a hard retelling (English and Japanese). Plain feelings words
    /// alone ("tired") do not count: the entry has to tell a hard story.
    static let hardNarrative = [
        "awful", "terrible", "horrible", "worst", "hate", "hated", "cried", "crying", "fight", "fought", "argument",
        "yelled", "shouted", "panic", "humiliat", "ashamed", "shame", "hopeless", "worthless", "alone", "lonely",
        "furious", "rage", "betray", "hurt me", "broke down", "fell apart", "couldn't stop", "can't stop", "nightmare",
        "ruined", "miserable", "exhausted", "overwhelmed", "dread", "scared", "afraid", "anxious", "grief", "lost it",
        // "hopeless" and "worthless" stay here for confidence, but readsHopeless keeps those entries first.
        "最悪", "泣いた", "つらい", "辛い", "喧嘩", "怖い", "不安", "孤独", "悲しい", "苦しい",
    ]

    static let pleasantCues = ["happy", "grateful", "glad", "lovely", "fun", "proud", "laughed", "enjoyed", "good day", "嬉しい", "楽しい", "幸せ"]

    /// Cues for sentences worth keeping, by tag. Her words, kept as written.
    static let keepCues: [(String, [String])] = [
        ("helped", ["helped", "what helps", "it helps", "made it better", "felt better after", "calmed me", "助かった", "楽になった"]),
        ("needed", ["i needed", "i need ", "what i need", "i wanted someone", "必要"]),
        ("learned", ["i learned", "i realised", "i realized", "i noticed that", "lesson", "next time", "気づいた", "学んだ"]),
        ("strength", ["i'm proud", "i am proud", "i managed", "i still", "i did it", "i matter", "i value", "頑張った"]),
        ("step", ["tomorrow i", "i will ", "i'll ", "i want to try", "small step", "my plan", "明日"]),
    ]

    /// Owner, 2026-11-04: "I'm OK with keeping heavy stuff. The thing I have issues with are
    /// embarrassing or shameful entries." Heavy entries are kept. An entry is offered for letting go
    /// (or for keeping without the embarrassing parts) only when it reads as embarrassing or shameful:
    /// her own shame words, or the model saying so (`themeIsShameful`). Self-harm is never let go.
    public static func decide(text: String?, word: String?, valence: Double?, themeIsShameful: Bool? = nil) -> Decision {
        let body = [text, word].compactMap { $0 }.joined(separator: "\n")
        if SafetyCheck.mentionsSelfHarm(body) { return .safetyKeep }
        if readsHopeless(body) { return .heavyKeep }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .keep }
        let hits = shameHits(body)
        if themeIsShameful == false && hits < 2 { return .keep }
        guard hits > 0 || themeIsShameful == true else { return .keep }
        return .letGo(keptLines: keptLines(text), confidence: min(1, 0.8 + 0.05 * Double(hits)))
    }

    /// Embarrassment and shame in her own words. English, Japanese, Tagalog.
    static let shameCues = [
        "embarrass", "ashamed", "shame", "humiliat", "mortif", "cringe", "so stupid", "i'm an idiot", "im an idiot",
        "what an idiot", "can't believe i said", "cant believe i said", "can't believe i did", "cant believe i did",
        "made a fool", "fool of myself", "awkward", "wish i hadn't", "wish i hadnt", "regret saying", "regret doing",
        "nobody can know", "no one can know", "never tell anyone", "so gross", "disgusting of me",
        "恥ずかしい", "恥", "黒歴史", "情けない", "nakakahiya", "hiyang-hiya", "napahiya", "kahihiyan",
    ]

    public static func shameHits(_ text: String) -> Int {
        let t = SafetyCheck.normalised(text)
        return Set(shameCues.filter { t.contains(SafetyCheck.normalised($0)) }).count
    }

    /// 0...1. Needs a clearly low mood point AND hard-narrative content. Without a mood point
    /// (writing only), the text alone must be clearly hard: two or more signs. The model's
    /// theme label can add a little, never decide alone.
    public static func confidence(text: String, word: String?, valence: Double?, themeIsHard: Bool?) -> Double {
        let lower = text.lowercased()
        let hits = Set(hardNarrative.filter { lower.contains($0) }).count
        guard hits > 0 else { return 0 }
        if pleasantCues.contains(where: { lower.contains($0) }) { return 0.4 } // mixed: keep
        guard let v = valence else {
            guard hits >= 2 else { return 0 }
            var c = 0.6 + min(0.3, Double(hits) * 0.1)
            if themeIsHard == true { c += 0.05 }
            if themeIsHard == false { c -= 0.3 }
            return max(0, min(1, c))
        }
        guard v <= lowValence else { return 0 }
        var c = 0.45
        c += min(0.3, Double(hits) * 0.1)                 // how clearly hard the story is
        c += min(0.2, (lowValence - v) / 0.65 * 0.2)       // how low the mood point is
        if themeIsHard == true { c += 0.1 }
        if themeIsHard == false { c -= 0.3 }
        return max(0, min(1, c))
    }

    /// Sentences in her own words, by cue. Never a sentence that retells the hard part.
    public static func keptLines(_ text: String) -> [String] {
        sentences(text).filter { s in
            let l = s.lowercased()
            guard keepCues.contains(where: { $0.1.contains(where: l.contains) }) else { return false }
            // A sentence that also carries the painful detail is not kept.
            return Set(hardNarrative.filter { l.contains($0) }).count <= 1
        }
    }

    public static func tag(_ sentence: String) -> String? {
        let l = sentence.lowercased()
        return keepCues.first { $0.1.contains(where: l.contains) }?.0
    }

    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out
    }
}

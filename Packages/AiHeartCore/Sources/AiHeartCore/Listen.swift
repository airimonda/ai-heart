import Foundation
import SwiftData

// Listen (M17, docs/13). A quiet place to get something out. No persona, no memory of past
// sessions, no advice, no labels, no reassurance, never a crisis responder. This file holds the
// rules the UI calls: the prompt, the validator, the no-model fallback, the pacing, the safety
// check, and the one tiny record of a session (length and choices, never words).

/// How often Listen may say a tiny line on its own after a long pause (My rules > Listen).
public enum ListenOffers: String, CaseIterable, Sendable {
    case ask, sometimes, often

    public var label: String {
        switch self {
        case .ask: "Only when I ask"
        case .sometimes: "Sometimes"
        case .often: "Often"
        }
    }
}

/// One line per session, for her only (docs/13 Evaluation). Length, which offer she chose, and
/// the optional "did it help" answer. Never the transcript, never a summary of it.
/// offerRaw: "reflect", "word", "body", "keep", "letGo", "nothing". helpedRaw: "yes", "aBit", "no".
@Model
public final class ListenSession {
    public var syncId: UUID = UUID()
    public var date: Date = Date()
    public var seconds: Double = 0
    @Attribute(.allowsCloudEncryption) public var offerRaw: String?
    @Attribute(.allowsCloudEncryption) public var helpedRaw: String?
    public var deviceId: String = ""

    public init(date: Date = Date(), seconds: Double = 0, offerRaw: String? = nil, helpedRaw: String? = nil, deviceId: String = "") {
        self.date = date
        self.seconds = seconds
        self.offerRaw = offerRaw
        self.helpedRaw = helpedRaw
        self.deviceId = deviceId
    }
}

public enum ListenRules {
    // MARK: Prompts

    /// System prompt for every Listen reply.
    public static let system = """
    You are a quiet listener on a phone. You have no name, no personality and no history with her, and you never \
    pretend to be a person, a friend or a therapist. She is talking to get something out. Reflect only what she said.
    Rules:
    - At most 2 short sentences. At most 1 question, and only if it really helps.
    - Use her own words. Do not add new ideas, causes, reasons or details she did not say.
    - Never give advice, tips, suggestions or instructions. No "you should", no "try", no "have you tried".
    - Never name or label a state, condition or diagnosis. Never say what she "is" or "has".
    - Never reassure. Never say it will be okay, never say she is doing well, never say you understand how she feels.
    - Never explain why she feels this way. Never judge anyone, and never take a side.
    - Do not bring up the past, other people or any topic she did not bring up herself.
    - Reply in the language she used. Plain words. No lists, no emojis.
    """

    /// "Say it back to me": a short reflection of the transcript in her own words.
    public static func reflectionPrompt(transcript: String) -> String {
        let body = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).suffix(3000))
        return """
        What she said:
        \"\"\"
        \(body)
        \"\"\"
        Say back what she said in one or two short sentences, using her own words, shortened. Say only that.
        Do not add anything she did not say. No advice, no labels, no reassurance, no explanation of why.
        Do not comment on yourself or on how sure you are: the screen already says that.
        """
    }

    // MARK: Reflection

    /// The hedge lives in the screen's fixed footnote. It is never the reflection itself.
    static let selfHedges = ["i may have it wrong", "i may not have it right", "i might have it wrong", "i might not have it right", "i could be wrong", "i may be wrong", "i might be wrong"]
    static let commonWords: Set<String> = [
        "that", "this", "with", "have", "what", "said", "says", "your", "just", "about", "from", "were", "they", "them", "then", "when",
        "been", "very", "really", "there", "their", "would", "could", "should", "some", "much", "because", "will", "like", "also", "into", "more",
        "something",
    ]

    /// Drops sentences that are only about how sure the model is, so what is left is her words.
    public static func cleanedReflection(_ raw: String) -> String {
        sentences(in: raw).filter { s in
            let l = normalised(s)
            return !selfHedges.contains { l.contains($0) }
        }.joined(separator: " ")
    }

    /// True if a reply carries something she said: a shared word of 4+ letters, or for Japanese a shared
    /// pair of characters. A reply that passes every rule but says nothing of hers fails this.
    public static func echoesHer(_ reply: String, transcript: String) -> Bool {
        if isCJK(reply) {
            let letters = Array(reply.filter(\.isLetter))
            guard letters.count >= 2 else { return false }
            return (0..<(letters.count - 1)).contains { transcript.contains(String(letters[$0...($0 + 1)])) }
        }
        func words(_ s: String) -> Set<String> {
            Set(normalised(s).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !commonWords.contains($0) })
        }
        return !words(reply).isDisjoint(with: words(transcript))
    }

    // MARK: Validation

    /// Advice and instructions. Whole-word matches, lower case, straight apostrophes.
    static let adviceTerms = [
        "you should", "you need to", "you have to", "you ought", "you must", "you might want to", "you could try", "you might try",
        "maybe you could", "perhaps you could", "why don't you", "why not try", "try to", "try ", "have you tried", "make sure",
        "consider", "remember to", "it's important", "it is important", "i recommend", "i suggest", "i'd suggest", "it might help",
        "it may help", "it would help", "it could help", "what helps is", "take a deep breath", "take a break", "take some time",
        "give yourself", "allow yourself", "let yourself", "be gentle with", "be kind to", "breathe in", "reach out to", "talk to someone",
        "talk to a ", "see a therapist", "seek help", "get some rest", "go for a walk",
        "please call", "call a ", "call 9", "call the ", "crisis line", "hotline", "helpline", "emergency services",
    ]
    /// Labels never used unless she said them herself (on top of OutputValidator.labels).
    static let labelTerms = [
        "triggered", "dissociat", "trauma response", "traumatized", "trauma", "manic", "depressed", "depression", "anxiety disorder",
        "burnout", "burned out", "burnt out", "ptsd", "adhd", "panic attack", "anxiety attack", "toxic", "narcissis", "gaslight",
        "breakdown", "mental illness", "unstable", "overreact",
    ]
    /// Explaining causes or telling her what her state is. Never.
    static let interpretationTerms = [
        "this sounds like", "that sounds like", "sounds like you are", "sounds like you're", "it seems like you", "it seems that you",
        "you seem to be", "you are probably", "you're probably", "you must be", "which means", "this means", "that means",
        "that's a sign", "this is a sign", "a sign of", "caused by", "the reason you", "that's why you", "this is why you",
        "because you", "you are clearly", "you're clearly", "it's natural", "it is natural", "it's normal", "it is normal",
        "perfectly normal", "valid to feel", "your feelings are valid", "not your fault", "you did nothing wrong", "they were wrong",
        "they are wrong", "he was wrong", "she was wrong", "you deserve",
    ]
    static let reassuranceTerms = [
        "it will be okay", "it will be ok", "it'll be okay", "it'll be ok", "it will be alright", "it'll be alright", "everything will",
        "everything is going to", "it's going to be okay", "it's going to be ok", "going to be fine", "you're doing great", "you are doing great",
        "you're doing well", "you are doing well", "you're doing your best", "you've got this", "you got this", "no need to worry",
        "nothing to worry", "you're not alone", "you are not alone", "you're safe", "you are safe", "things will get better",
        "it gets better", "you'll get through", "you will get through", "you're strong", "you are strong", "you're so brave", "you are so brave",
        "i understand how you feel", "i know how you feel", "i know exactly", "i understand exactly", "i understand what you're going through",
    ]
    static let personaTerms = [
        "i'm here for you", "i am here for you", "i'm here with you", "i am here with you", "i'm always here", "i am always here",
        "i'll always be", "i will always be", "as your friend", "your friend", "i care about you", "i care for you", "i'm proud", "i am proud",
        "i love you", "i'm with you", "i am with you", "i'm glad you", "i am glad you", "thank you for sharing", "thanks for sharing",
        "thank you for trusting", "thank you for telling", "my name is", "i'm an ai", "i am an ai", "as an ai", "i'm your", "i am your",
        "stay with me", "talk you through", "i missed you", "i'm worried about you", "i am worried about you",
    ]

    /// Agreeing with her story, giving it special meaning, or claiming to be alive or close to her
    /// (docs/15). Sycophancy and these themes are the pattern in reported chatbot-linked delusions
    /// (Moore 2026, Cheng 2026). Rejected even if she said the words: echoing them back is agreement.
    static let affirmationTerms = [
        "you're right", "you are right", "you're absolutely", "you are absolutely", "exactly right", "that's exactly", "absolutely right",
        "of course you", "you're not crazy", "you are not crazy", "you're not imagining", "you are not imagining",
        "you're not wrong", "you are not wrong", "it's a sign", "it is a sign", "meant to be", "the universe", "you were chosen",
        "you are chosen", "you're chosen", "you're special", "you are special", "only you can", "no one else understands",
        "nobody else understands", "only i understand", "i understand you", "i'm conscious", "i am conscious", "i'm alive", "i am alive",
        "i have feelings", "i'm real", "i am real", "our connection", "between us", "you and me",
    ]

    /// Lower case, straight apostrophes, single spaces.
    static func normalised(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Validates a model reply. Returns nil if fine, else a short reason (no content).
    /// `reflective`: Talk it through (docs/21) may offer tentative reflections ("it sounds like ...")
    /// and up to three sentences; certainty and special-meaning claims are still rejected by its own list.
    public static func rejection(_ reply: String, transcript: String, quietTopics: [String], reflective: Bool = false) -> String? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "empty" }
        // Numbers she said are allowed: the transcript is the input.
        let policy = OutputPolicy(input: transcript, userText: transcript, quietTopics: quietTopics, maxCharacters: 320)
        // Reflective mode: an open question ("What would it be like to let yourself rest?") is not advice.
        // Advice and reassurance are checked on the statements only (owner report, 2026-11-04: long talks
        // fell back to fixed questions because questions like that were rejected as advice).
        let statements = reflective
            ? sentences(in: text).filter { !$0.contains("?") && !$0.contains("\u{FF1F}") }.joined(separator: " ")
            : text
        if reflective {
            let all = OutputValidator.check(text, policy).filter { v in
                if case .advice = v { return false }
                if case .reassurance = v { return false }
                return true
            }
            let onStatements = OutputValidator.check(statements.isEmpty ? "." : statements, policy).filter { v in
                if case .advice = v { return true }
                if case .reassurance = v { return true }
                return false
            }
            if let first = (all + onStatements).first {
                switch first {
                case .numberNotInInput: return "number"
                case .label: return "label"
                case .advice: return "advice"
                case .reassurance: return "reassurance"
                case .quietTopic: return "quiet topic"
                case .tooLong: return "too long"
                case .empty: break
                }
            }
        } else if let first = OutputValidator.check(text, policy).first {
            switch first {
            case .numberNotInInput: return "number"
            case .label: return "label"
            case .advice: return "advice"
            case .reassurance: return "reassurance"
            case .quietTopic: return "quiet topic"
            case .tooLong: return "too long"
            case .empty: return "empty"
            }
        }
        if sentences(in: text).count > (reflective ? 3 : 2) { return "too many sentences" }
        if text.filter({ $0 == "?" || $0 == "\u{FF1F}" }).count > 1 { return "too many questions" }

        let lower = normalised(text), said = normalised(transcript)
        let lowerStatements = reflective ? normalised(statements) : lower
        if matches(adviceTerms, in: lowerStatements) { return "advice" }
        if matches(reassuranceTerms, in: lowerStatements) { return "reassurance" }
        if matches(personaTerms, in: lower) { return "persona" }
        if matches(affirmationTerms, in: lower) { return "affirmation" }
        if matches(labelTerms, in: lower, unless: said) { return "label" }
        if !reflective, matches(interpretationTerms, in: lower) { return "interpretation" }
        for q in quietTopics {
            let t = normalised(q).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, lower.contains(t) { return "quiet topic" }
        }
        return nil
    }

    /// True if any term appears in `text` as whole words (so "try " does not hit "country"). A term she
    /// said herself (`unless`) does not count.
    static func matches(_ terms: [String], in text: String, unless said: String = "") -> Bool {
        for t in terms {
            guard let r = text.range(of: t) else { continue }
            if !said.isEmpty, said.contains(t) { continue }
            // Whole-word on the left for terms that start with a letter ("try" must not match "entry").
            if let f = t.first, f.isLetter, f.isASCII, r.lowerBound > text.startIndex {
                var searchFrom = text.startIndex
                var ok = false
                while let hit = text.range(of: t, range: searchFrom..<text.endIndex) {
                    let before = hit.lowerBound == text.startIndex ? nil : text[text.index(before: hit.lowerBound)]
                    if before == nil || !(before!.isLetter && before!.isASCII) { ok = true; break }
                    searchFrom = hit.upperBound
                }
                if !ok { continue }
            }
            return true
        }
        return false
    }

    // MARK: Sentences

    /// Splits into sentences, each keeping its end mark. "3.5" and "Mr.A" do not split; a Japanese
    /// full stop always does; so does a newline.
    static func sentences(in text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        let chars = Array(text)
        var i = 0
        func flush() {
            let s = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.contains(where: { $0.isLetter || $0.isNumber }) { out.append(s) }
            cur = ""
        }
        while i < chars.count {
            let c = chars[i]
            cur.append(c)
            if c == "\n" { flush() }
            else if "\u{3002}\u{FF01}\u{FF1F}\u{2026}".contains(c) {
                while i + 1 < chars.count, "\u{3002}\u{FF01}\u{FF1F}\u{2026}\u{300D}\u{201D}\"')".contains(chars[i + 1]) { i += 1; cur.append(chars[i]) }
                flush()
            } else if ".!?".contains(c) {
                // End mark only at the end of a run followed by space or the end of the text.
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if next == nil || next!.isWhitespace {
                    flush()
                } else if let n = next, "\"')\u{201D}\u{2019}".contains(n), i + 2 >= chars.count || chars[i + 2].isWhitespace {
                    i += 1; cur.append(chars[i]); flush()
                }
            }
            i += 1
        }
        flush()
        return out
    }

    // MARK: Fallback

    static let feelingWords = [
        "feel", "felt", "feeling", "tired", "exhausted", "sad", "angry", "mad", "scared", "afraid", "anxious", "nervous", "worried",
        "heavy", "empty", "lonely", "alone", "overwhelmed", "hurt", "hurts", "upset", "stressed", "happy", "relieved", "numb", "tense",
        "tight", "ashamed", "guilty", "frustrated", "stuck", "lost", "hopeless", "restless", "drained", "sick", "crying", "cried", "hard",
        "疲れ", "悲しい", "つらい", "辛い", "不安", "怖い", "しんどい", "寂しい", "苦しい", "重い", "イライラ", "嬉しい", "気持ち", "痛い", "眠れ",
        "pagod", "malungkot", "galit", "takot", "kinakabahan", "nalulungkot", "nahihirapan", "hirap", "mabigat", "nag-iisa", "stress", "sakit",
    ]
    static let trailingConnectors: Set<String> = [
        "and", "but", "so", "because", "that", "to", "the", "a", "an", "of", "with", "or", "then", "like", "my", "i", "it", "in", "on", "for", "at",
        "kasi", "at", "na", "ng", "sa", "pero",
    ]
    static let wordLimit = 22
    static let cjkCharLimit = 40

    static func isCJK(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let cjk = letters.filter { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        return cjk.count * 2 > letters.count
    }

    /// Extractive fallback: 1 to 2 of her own sentences, each trimmed to 22 words. Never adds a word.
    /// Returns "" for empty input, or if every sentence touches a quiet topic (a quiet topic wins over "never empty").
    public static func fallbackReflection(_ transcript: String, quietTopics: [String] = []) -> String {
        let topics = quietTopics.map { normalised($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var cands: [(text: String, score: Double)] = []
        let all = sentences(in: transcript)
        for (i, raw) in all.enumerated() {
            let lower = normalised(raw)
            if topics.contains(where: { lower.contains($0) }) { continue }
            let s = stripFillers(raw)
            let cjk = isCJK(s)
            let size = cjk ? s.filter { $0.isLetter }.count : s.split(whereSeparator: \.isWhitespace).count
            var score = Double(i) / Double(max(1, all.count))   // later is better
            if size >= (cjk ? 6 : 4) { score += 2 }               // substantive
            if feelingWords.contains(where: { lower.contains($0) }) { score += 2 }
            if s.contains(where: { $0.isLetter || $0.isNumber }) { cands.append((s, score)) }
        }
        guard !cands.isEmpty else { return "" }
        let indexed = cands.enumerated().sorted { a, b in a.element.score == b.element.score ? a.offset > b.offset : a.element.score > b.element.score }
        let picked = indexed.prefix(2).map(\.offset).sorted()
        return picked.map { shorten(cands[$0].text) }.joined(separator: " ")
    }

    static func stripFillers(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let r = t.range(of: "^(um+|uh+|erm+|hmm+)[,.]?\\s+", options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(r) }
        return t
    }

    /// At most 22 words (40 characters for Japanese). Cuts at a comma when that keeps enough; otherwise
    /// at the limit. Only removes text.
    static func shorten(_ sentence: String) -> String {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let endMarks = CharacterSet(charactersIn: ".!?\u{3002}\u{FF01}\u{FF1F}\u{2026}")
        func closed(_ body: String, original: Bool) -> String {
            var b = body.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:、，；：-\u{2013}\u{2014}"))
            if original { return b }
            // Trim dangling connectors left by a hard cut ("... and").
            var words = b.split(separator: " ").map(String.init)
            while let last = words.last, trailingConnectors.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)), words.count > 3 { words.removeLast() }
            b = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;:、，；：-"))
            return b
        }

        if isCJK(s) {
            let body = s.trimmingCharacters(in: endMarks)
            if body.count <= cjkCharLimit { return s.unicodeScalars.last.map { endMarks.contains($0) } == true ? s : s + "\u{3002}" }
            let head = String(body.prefix(cjkCharLimit))
            if let cut = head.lastIndex(where: { "\u{3001},\u{FF0C}".contains($0) }), head.distance(from: head.startIndex, to: cut) >= 8 {
                return String(head[..<cut]) + "\u{3002}"
            }
            return head + "\u{2026}"
        }

        let words = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count <= wordLimit {
            return s.unicodeScalars.last.map { endMarks.contains($0) } == true ? s : s + "."
        }
        let head = Array(words.prefix(wordLimit))
        // Prefer the last comma / semicolon that still leaves a real clause.
        if let idx = head.lastIndex(where: { $0.hasSuffix(",") || $0.hasSuffix(";") }), idx >= 5 {
            return closed(head[...idx].joined(separator: " "), original: true) + "."
        }
        return closed(head.joined(separator: " "), original: false) + "\u{2026}"
    }

    // MARK: Pacing

    /// Fixed gentle lines after a long pause (only when offers != .ask).
    public static let nudges = ["Take your time.", "Anything else?", "Where does that sit in your body?"]
    public static let longSessionLine = "We have been at this a while. Want to stop here?"

    /// Whether to show a nudge now. ask: never. sometimes: silence of 12 s and fewer than 2 so far.
    /// often: 8 s and fewer than 4. Never two within 45 s.
    public static func shouldNudge(silence: Double, offers: ListenOffers, nudgesSoFar: Int, secondsSinceLastNudge: Double?) -> Bool {
        if let since = secondsSinceLastNudge, since < 45 { return false }
        switch offers {
        case .ask: return false
        case .sometimes: return silence >= 12 && nudgesSoFar < 2
        case .often: return silence >= 8 && nudgesSoFar < 4
        }
    }

    /// Long session: true once, after 20 minutes, if she turned it on.
    public static func shouldSayLong(elapsed: Double, enabled: Bool, alreadySaid: Bool) -> Bool {
        enabled && !alreadySaid && elapsed >= 20 * 60
    }
}

/// "Help me sort it" (owner, 2026-11-02): she knows what to do once she can see it clearly. Her own
/// words, sorted into what happened, what she felt, and what she already knows. It never adds advice.
public struct ListenSorted: Equatable, Sendable {
    public var happened: [String] = []
    public var felt: [String] = []
    public var know: [String] = []
    public init(happened: [String] = [], felt: [String] = [], know: [String] = []) {
        self.happened = happened; self.felt = felt; self.know = know
    }
    public var isEmpty: Bool { happened.isEmpty && felt.isEmpty && know.isEmpty }
}

public enum ListenSort {
    static let knowCues = [
        "i know", "i already", "i need to", "i have to", "i should", "i will ", "i'll ", "i'm going to", "i am going to", "i can ", "i could ",
        "i want to", "next time", "tomorrow", "what helps", "what helped", "alam ko", "kailangan ko", "gagawin ko",
        "わかって", "分かって", "しなきゃ", "しよう", "必要",
    ]
    static let perLine = 3

    public static let system = """
    You sort what she said into three lines. You copy her own words, shortened. You add nothing of your own: no advice, no labels, \
    no reassurance, no causes, no new facts. Reply in the language she used.
    """

    public static func prompt(transcript: String) -> String {
        let body = String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).suffix(3000))
        return """
        What she said:
        \"\"\"
        \(body)
        \"\"\"
        Write exactly three lines, using her words:
        HAPPENED: what happened
        FELT: what she felt
        KNOW: what she says she knows, needs or plans to do
        If she said nothing for a line, write none after the colon.
        """
    }

    /// Reads the model's three lines. A line survives only if it passes the Listen rules and is made of
    /// her words. Returns nil when nothing survives, so the rule-based sort takes over.
    public static func parse(_ raw: String, transcript: String, quietTopics: [String]) -> ListenSorted? {
        var out = ListenSorted()
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet.letters.inverted).uppercased()
            let text = parts[1].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.lowercased().trimmingCharacters(in: .punctuationCharacters) != "none" else { continue }
            guard ListenRules.rejection(text, transcript: transcript, quietTopics: quietTopics) == nil,
                  isHerWords(text, transcript: transcript) else { continue }
            switch key {
            case "HAPPENED": out.happened = [text]
            case "FELT": out.felt = [text]
            case "KNOW": out.know = [text]
            default: continue
            }
        }
        return out.isEmpty ? nil : out
    }

    /// At least 3 of every 4 words (or Japanese character pairs) came from what she said.
    public static func isHerWords(_ line: String, transcript: String) -> Bool {
        if ListenRules.isCJK(line) {
            let letters = Array(line.filter(\.isLetter))
            guard letters.count >= 2 else { return false }
            let pairs = (0..<(letters.count - 1)).map { String(letters[$0...($0 + 1)]) }
            return Double(pairs.filter { transcript.contains($0) }.count) >= Double(pairs.count) * 0.75
        }
        func words(_ s: String) -> [String] {
            ListenRules.normalised(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        let said = Set(words(transcript)), mine = words(line)
        guard !mine.isEmpty else { return false }
        return Double(mine.filter(said.contains).count) >= Double(mine.count) * 0.75
    }

    /// Rule-based sort, no model. Only ever removes text. Speech often arrives as one long run, so
    /// long sentences are first cut at their joins.
    public static func fallback(_ transcript: String, quietTopics: [String] = []) -> ListenSorted {
        let topics = quietTopics.map { ListenRules.normalised($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out = ListenSorted()
        for sentence in ListenRules.sentences(in: transcript) {
            for clause in clauses(ListenRules.stripFillers(sentence)) {
                let lower = ListenRules.normalised(clause)
                guard clause.contains(where: { $0.isLetter || $0.isNumber }), !topics.contains(where: { lower.contains($0) }) else { continue }
                let short = ListenRules.shorten(clause)
                if knowCues.contains(where: { lower.contains($0) }) { out.know.append(short) }
                else if ListenRules.feelingWords.contains(where: { lower.contains($0) }) { out.felt.append(short) }
                else { out.happened.append(short) }
            }
        }
        out.happened = Array(out.happened.suffix(perLine))
        out.felt = Array(out.felt.suffix(perLine))
        out.know = Array(out.know.suffix(perLine))
        return out
    }

    static func clauses(_ sentence: String) -> [String] {
        let words = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > ListenRules.wordLimit else { return [sentence] }
        var out: [String] = [], cur: [String] = []
        for w in words {
            let join = ["but", "and", "so", "pero", "kasi"].contains(w.lowercased())
            if join, cur.count >= 5 { out.append(cur.joined(separator: " ")); cur = [] }
            cur.append(w)
            if w.hasSuffix(","), cur.count >= 5 { out.append(cur.joined(separator: " ")); cur = [] }
        }
        if !cur.isEmpty { out.append(cur.joined(separator: " ")) }
        return out
    }
}

public enum ListenSafety {
    /// Phrases beyond SafetyCheck's list: English, Japanese, Tagalog.
    static let extra = [
        "no reason to live", "better off without me", "can't go on", "cant go on", "end it all", "plan to die", "take my own life",
        "wish i was dead", "wish i were dead", "rather be dead", "no point in living", "not worth living", "don't want to live",
        "dont want to live", "don't want to be here anymore", "never wake up",
        "not exist", "stop existing", "don't want to exist", "dont want to exist", "disappear forever",
        "消えてしまいたい", "生きていたくない", "死んでしまいたい", "いなくなりたい", "死のうと", "生きるのをやめ",
        "ayoko nang mabuhay", "ayaw ko nang mabuhay", "magpakamatay", "magpatiwakal", "gusto ko nang mamatay", "gusto kong mamatay",
        "wala na akong dahilan para mabuhay",
    ]

    /// Heavy, short of the self-harm stop (owner, 2026-11-02). Fixed words, never the model. It does not
    /// interrupt her: after she stops, the screens show a card pointing to her therapist and crisis lines.
    /// A false alarm costs one small card. Missing it is covered by "Who I can reach", always on the sheet.
    static let heavyPhrases = [
        "so heavy", "too heavy", "too much", "can't take", "cant take", "can't cope", "cant cope", "can't do this", "cant do this",
        "can't anymore", "cant anymore", "can't keep going", "cant keep going", "can't handle", "cant handle", "can't stop crying", "cant stop crying",
        "falling apart", "breaking down", "hopeless", "no way out", "give up", "giving up", "nothing matters", "drowning",
        "i'm not okay", "im not okay", "i am not okay", "not ok anymore",
        "もう無理", "限界", "耐えられない", "つらすぎ", "辛すぎ",
        "hindi ko na kaya", "di ko na kaya", "suko na ako", "ang bigat", "sobrang bigat",
    ]

    public static func feelsHeavy(_ transcript: String) -> Bool {
        let t = transcript
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return heavyPhrases.contains { t.contains($0.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)) }
    }

    /// Continuous check of the live transcript. Case- and width-insensitive. Deliberately conservative:
    /// it fires on any sentence containing a phrase, including negations ("I would never hurt myself",
    /// "I want to die laughing"), because a false alarm shows a calm page and a miss is far worse.
    public static func flags(_ transcript: String) -> Bool {
        if SafetyCheck.mentionsSelfHarm(transcript) { return true }
        let t = transcript
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if SafetyCheck.mentionsSelfHarm(t) { return true }
        return extra.contains { t.contains($0.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)) }
    }
}

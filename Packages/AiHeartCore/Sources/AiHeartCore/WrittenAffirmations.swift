import Foundation

/// Honest affirmations written by the language model (owner, 2026-11-05: the fixed templates "are still flat").
/// The model sees her numbered sentences and writes one or two short lines that connect things she actually
/// wrote. Every line must cite the sentences it rests on, and is dropped unless it passes the rails below.
/// The fixed templates in `HonestAffirmations.from` remain the fallback (old notes, no model, no line passed).
/// Nothing here is a trait, a promise, advice or reassurance; docs/16.
public struct WrittenAffirmation: Codable, Equatable, Sendable {
    public var text: String
    /// Why it is true here: the approach, then one line on what in her entry backs it.
    public var basis: String
    /// Her sentences the line rests on, word for word.
    public var anchors: [String]

    public init(text: String, basis: String, anchors: [String]) {
        self.text = text; self.basis = basis; self.anchors = anchors
    }
}

/// The research-backed approaches a line may name. Closed on purpose: the model picks a key, the app
/// supplies the true description, so a citation is never invented.
public enum AffirmationApproach: String, CaseIterable, Sendable {
    case values, compassion, strengths, labelling

    public var caption: String {
        switch self {
        case .values: "Self-affirmation (Cohen and Sherman): holding on to your own values and acts."
        case .compassion: "Self-compassion (Neff): kindness toward yourself, and knowing others struggle too."
        case .strengths: "Strengths-based noticing: seeing what you already do."
        case .labelling: "Affect labelling: putting feelings into words."
        }
    }
}

extension HonestAffirmations {
    public static let writtenMaxWords = 34
    static let writtenMaxChars = 260
    static let maxCited = 3
    static let maxPromptSentences = 80

    // MARK: Prompt

    public static let system = """
    You are a careful, warm reader of a person's journal entry. You write one or two short honest lines to her, \
    using only what she wrote. You never add facts, advice, reassurance, predictions, diagnoses or praise of who she is.
    """

    /// Her numbered sentences (with the part each was sorted into), the feelings and the needs.
    /// Sentences about self-harm or hopelessness are left out of the prompt but keep their numbers.
    public static func prompt(sentences: [String], labels: [Int: NotePart], note: ReleaseNote, noQuotes: Bool = false) -> String {
        let rows = sentences.prefix(maxPromptSentences).enumerated().compactMap { i, s -> String? in
            guard usable(s) else { return nil }
            let part = labels[i].map { " [\($0.rawValue)]" } ?? ""
            return "\(i + 1).\(part) \(s)"
        }.joined(separator: "\n")
        let feelings = note.feelings.isEmpty ? "none picked" : note.feelings.map(\.rawValue).joined(separator: ", ")
        let needs = note.needs.isEmpty ? "none" : note.needs.map { "\($0.need.title) (\($0.met ? "met" : "seemed missing"))" }.joined(separator: "; ")
        let approaches = AffirmationApproach.allCases.map(\.rawValue).joined(separator: " | ")
        return """
        Her entry, one sentence per line, with the part of her story each belongs to:
        \(rows)

        Feelings that seemed present: \(feelings)
        Needs that seemed touched: \(needs)

        Write 1 or 2 short lines (under 30 words each) to her, addressed as "you". Warm, plain and specific. \
        Each line should CONNECT two things she actually wrote, for example: what she wants with what she did; \
        what she longs for with the need under it; how she handled something with what it cost her. \
        Each rests on one of these approaches: \
        values (affirming her own values and acts), compassion (kindness toward herself, others struggle too), \
        strengths (noticing what she already does), labelling (putting feelings into words). \
        Rules: say only what her sentences support. No praise of who she is ("you are strong"). No promises or predictions \
        ("it will be okay"). No "don't worry", no advice, no "you should" or "try to", no orders. No diagnoses. \
        Do not say "I" or "me". \(noQuotes ? "Do not quote her at all: she let this entry go, so say it in your own plain words, without quotation marks." : "If you quote her, copy her exact words in double quotes.") \
        If nothing fits honestly, answer: none
        One line per answer, in exactly this form (sentence numbers from the list above):
        LINE: You wanted to be there for her, and you went. | SENTENCES: 2,5 | APPROACH: values | BASIS: Both sentences show a value of yours acted on.
        Nothing else.
        """
    }

    // MARK: Parse and rails

    /// Reads the model's answer into checked lines, at most `maxShown`. A line that fails any rail is dropped.
    public static func parseWritten(_ raw: String, sentences: [String], text: String, quietTopics: [String] = []) -> [WrittenAffirmation] {
        var out: [WrittenAffirmation] = []
        for row in raw.split(whereSeparator: \.isNewline) {
            guard let a = parseLine(String(row), sentences: sentences, text: text, quietTopics: quietTopics),
                  !out.contains(where: { $0.text == a.text }) else { continue }
            out.append(a)
            if out.count == maxShown { break }
        }
        return out
    }

    /// `LINE: ... | SENTENCES: 2,5 | APPROACH: values | BASIS: ...` -> a checked line, or nil.
    public static func parseLine(_ row: String, sentences: [String], text: String, quietTopics: [String] = []) -> WrittenAffirmation? {
        var fields: [String: String] = [:]
        for bit in row.split(separator: "|") {
            let parts = bit.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: CharacterSet.letters.inverted).uppercased()
            guard ["LINE", "SENTENCES", "APPROACH", "BASIS"].contains(key), fields[key] == nil else { continue }
            fields[key] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func reject(_ reason: String) -> WrittenAffirmation? {
            // Reason only, never the line: the log must not hold her words.
            NSLog("AiHeartLLM affirmation rejected: %@", reason); return nil
        }
        guard let line = fields["LINE"], let cites = fields["SENTENCES"], let approachKey = fields["APPROACH"], let why = fields["BASIS"] else {
            return row.trimmingCharacters(in: .whitespaces).isEmpty ? nil : reject("format (fields: \(fields.keys.sorted().joined(separator: ",")))")
        }
        guard let approach = AffirmationApproach(rawValue: approachKey.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))) else {
            return reject("approach")
        }
        guard let anchors = citedSentences(cites, sentences: sentences) else { return reject("sentences") }
        let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " \"'\u{201C}\u{201D}"))
        if let r = writtenRejection(clean, text: text, quietTopics: quietTopics) { return reject("line: \(r)") }
        if let r = basisRejection(why, text: text, quietTopics: quietTopics) { return reject("basis: \(r)") }
        return WrittenAffirmation(text: clean, basis: approach.caption + " " + why.trimmingCharacters(in: .whitespaces), anchors: anchors)
    }

    /// A sentence we may rest an affirmation on: hers, not about self-harm, not hopeless.
    static func usable(_ s: String) -> Bool { !SafetyCheck.mentionsSelfHarm(s) && !KeepOrRelease.readsHopeless(s) }

    /// "2, 5" -> those sentences. nil if none, any number is out of range, or any cited sentence is unsafe.
    static func citedSentences(_ raw: String, sentences: [String]) -> [String]? {
        var numbers: [Int] = []
        for bit in raw.split(whereSeparator: { !$0.isNumber }) {
            guard let n = Int(bit), (1...max(sentences.count, 1)).contains(n), n <= sentences.count else { return nil }
            if !numbers.contains(n) { numbers.append(n) }
        }
        guard !numbers.isEmpty, numbers.count <= maxCited else { return nil }
        let cited = numbers.map { sentences[$0 - 1] }
        return cited.allSatisfy(usable) ? cited : nil
    }

    /// Claims about her mind, causes or verdicts the model cannot know (narrower than Listen's list).
    static let mindReading = ["you must be", "you are probably", "you're probably", "a sign of", "that's a sign", "this is a sign",
                              "caused by", "the reason you", "you are clearly", "you're clearly", "you deserve", "not your fault",
                              "you did nothing wrong", "they were wrong", "he was wrong", "she was wrong", "deep down", "really means"]

    static let traitWords = ["strong", "brave", "resilient", "amazing", "incredible", "wonderful", "awesome", "courageous", "fearless",
                             "inspiring", "special", "worthy", "enough", "lovable", "loved", "capable", "a survivor", "a fighter",
                             "a warrior", "a good", "a great", "a bad", "a kind", "a caring", "a wonderful", "such a"]
    static let promiseTerms = ["it'll", "things will", "will get better", "gets better", "get better", "gets easier", "get easier",
                               "in time", "time heals", "someday", "eventually", "never again", "going to be", "is going to", "are going to",
                               "all work out", "work out", "will pass", "this too shall"]
    static let dismissTerms = ["not a big deal", "no big deal", "nothing to worry", "no need to", "doesn't matter", "does not matter",
                               "just a", "only a", "overthinking", "overreact", "get over", "move on", "look on the bright", "silver lining",
                               "at least", "could be worse"]
    static let adviceExtra = ["you should", "you must", "you have to", "you ought", "you could", "you might want", "you can try", "don't forget",
                              "do not forget", "never forget", "remember to", "remember that", "keep going", "keep doing", "keep it up",
                              "next time", "from now on", "be kind to", "be gentle", "let yourself", "allow yourself", "give yourself"]
    /// A sentence that opens with one of these is an order, not a description.
    static let imperativeStarts: Set<String> = ["remember", "try", "keep", "let", "be", "take", "give", "allow", "notice", "don't", "do", "please",
                                                "go", "think", "know", "hold", "trust", "stay", "forgive", "accept", "breathe", "look", "make",
                                                "stop", "start", "continue", "focus", "celebrate", "honour", "honor", "embrace", "choose",
                                                "allow", "reach", "talk", "consider", "imagine", "ask", "tell", "say", "write", "use"]
    static let iVoice = try! NSRegularExpression(pattern: #"(?<![\p{L}'])(i|i'm|i've|i'd|i'll|me|we|us|our|let's)(?![\p{L}'])"#,
                                                 options: .caseInsensitive)

    /// Text between double quotes (straight, curly) or corner brackets.
    static func quoted(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[\"\u{201C}\u{300C}]([^\"\u{201C}\u{201D}\u{300C}\u{300D}]+)[\"\u{201D}\u{300D}]"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range(at: 1), in: s).map { String(s[$0]) }
        }
    }

    /// Why a written line fails the rails, or nil if it passes (no content in the reason).
    public static func writtenRejection(_ line: String, text: String, quietTopics: [String] = []) -> String? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !ReleaseNotes.isNone(t) else { return "empty" }
        let words = t.split(whereSeparator: \.isWhitespace).count
        if t.count > writtenMaxChars || (!ListenRules.isCJK(t) && words > writtenMaxWords) { return "too long" }
        if t.contains("<") || t.contains("[") { return "placeholder" }
        // Invented facts: anything in quotes must be her exact words.
        let said = ListenRules.normalised(text)
        for q in quoted(t) {
            let n = ListenRules.normalised(q).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !n.isEmpty, !said.contains(n) { return "invented quote" }
        }
        if SafetyCheck.mentionsSelfHarm(t) || KeepOrRelease.readsHopeless(t) { return "self-harm or hopeless" }
        // Fixed output rules (labels, quiet topics, numbers), then the Listen word lists for advice,
        // reassurance, persona, special meaning and interpretation.
        // Reflective mode: a line that CONNECTS two things she wrote needs "because you" or "it's human to"
        // (common humanity is self-compassion). Readings of her mind or causes are still refused below.
        if let why = ListenRules.rejection(t, transcript: text, quietTopics: quietTopics, reflective: true) { return why }
        if ListenRules.matches(mindReading, in: t.lowercased()) { return "interpretation" }
        // Her own quoted words are not the app speaking: the style rails look at the rest.
        let own = quoted(t).reduce(ListenRules.normalised(t)) { $0.replacingOccurrences(of: ListenRules.normalised($1), with: " ") }
        for rail: (String, [String]) in [("promise", promiseTerms), ("dismissing", dismissTerms), ("advice", adviceExtra)] {
            if ListenRules.matches(rail.1, in: own) { return rail.0 }
        }
        if own.range(of: #"\b(will|won't|shall)\b|'ll\b"#, options: .regularExpression) != nil { return "promise" }
        if let r = own.range(of: #"\b(you are|you're|you were|you seem|you remain)\b"#, options: .regularExpression) {
            let tail = String(own[r.upperBound...].prefix(40))
            if traitWords.contains(where: { w in ListenRules.matches([w], in: tail) }) { return "trait" }
            if tail.range(of: #"\b(person|human|someone who)\b"#, options: .regularExpression) != nil { return "trait" }
        }
        if own.contains("your strength") || own.contains("so strong") || own.contains("such strength") { return "trait" }
        for s in ListenRules.sentences(in: own) {
            let first = s.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)).split(whereSeparator: { !$0.isLetter && $0 != "'" }).first
            if let f = first, imperativeStarts.contains(String(f)) { return "imperative" }
        }
        if iVoice.firstMatch(in: own, range: NSRange(own.startIndex..., in: own)) != nil { return "I voice" }
        return nil
    }

    /// The "why it is true here" line: short, no labels or quiet topics, no first person, and no quote she did not write.
    static func basisRejection(_ why: String, text: String, quietTopics: [String]) -> String? {
        let t = why.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 180 else { return "length" }
        let said = ListenRules.normalised(text)
        for q in quoted(t) where !said.contains(ListenRules.normalised(q).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) {
            return "invented quote"
        }
        if SafetyCheck.mentionsSelfHarm(t) || KeepOrRelease.readsHopeless(t) { return "self-harm or hopeless" }
        let policy = OutputPolicy(input: text, userText: text, quietTopics: quietTopics, maxCharacters: 180)
        let bad = OutputValidator.check(t, policy).filter { v in
            if case .reassurance = v { return false }
            return true
        }
        return bad.isEmpty ? nil : "output rules"
    }

    // MARK: Display

    /// What the card shows: the written lines when the note has them, else the fixed templates.
    public static func shown(_ note: ReleaseNote) -> [Affirmation] {
        if let written = note.affirmations, !written.isEmpty {
            return written.prefix(maxShown).map { Affirmation(text: $0.text, basis: $0.basis) }
        }
        // A let-go note keeps too little for a template to say anything specific (owner, 2026-11-05: flat).
        if note.summaryOnly == true { return [] }
        return from(note)
    }

    /// Entries that read as heavy or hopeless, or mention self-harm, get no written lines (the fixed heavy card shows).
    public static func mayWrite(for text: String) -> Bool {
        !SafetyCheck.mentionsSelfHarm(text) && !KeepOrRelease.readsHopeless(text)
    }
}

import Foundation
import NaturalLanguage

// Talk it through (docs/21). A bounded, purpose-built conversation for talking a hard moment
// through with reflective questions. Not a companion and not open chat: no persona, no memory of
// past conversations, no advice. Safety checks run on the phone before any model call, every reply
// is checked before she sees it, and a fixed line stands in when a reply fails.

public enum TalkRole: Sendable, Equatable { case her, app }

public struct TalkTurn: Sendable, Equatable {
    public var role: TalkRole
    public var text: String
    public init(_ role: TalkRole, _ text: String) { self.role = role; self.text = text }
}

public enum TalkSafety: Sendable, Equatable { case none, heavy, selfHarm }

/// What `reply` hands back.
public enum TalkReplyResult: Sendable, Equatable {
    /// A reply that passed every check.
    case model(String)
    /// The model's replies failed the checks twice: the fixed line stands in.
    case fallback(String)
    /// The model could not be reached.
    case unavailable
}

public enum TalkItThrough {
    /// The mirror (owner-reviewed intent, 2026-11-04). The parts about earlier words and About me are added
    /// only when those are actually sent: told it may quote the past, a model invented "on <date> you wrote"
    /// quotes even when nothing was given, and every such reply was rejected (owner report: the same fixed
    /// line kept coming back).
    public static let system = """
    You are Claude, inside her private journal app, talking with her through a hard moment. Talk the way you \
    naturally would with someone going through something hard: warm, honest, plain and unhurried. You can say "I" \
    to show care ("I'm sorry that happened", "I'm glad you told me") and you can say what is understandable about how \
    she feels. Reflect what you hear, including the feeling or need underneath, and ask a question when it helps; it \
    is fine not to ask one, and when she sounds very distressed keep the reply short and gentle and do not push. Help \
    her process the feeling at her pace: naming it, understanding the need under it, making room for it, and what she \
    needs now. Ask about where she feels it in her body at most once in the whole conversation, only if it seems \
    welcome. Stay grounded and honest: do not promise that things will be fine, never agree that a harsh belief about \
    herself is true (gently explore it instead), and do not give events special meaning. Do not diagnose or name \
    conditions or states. Do not give advice or suggestions unless she asks for them; if she asks, offer one or two \
    small, gentle options, never instructions and never anything medical. Do not claim feelings of your own beyond \
    care for her, and do not describe a relationship with her (no "I love you", "our bond", "I'll always be here"). \
    Never ask for details of a traumatic event. Do not mention earlier notes, earlier talks or anything she wrote \
    before, and never quote anything except her words in this conversation. Vary how you start, and keep replies \
    short: usually two to four sentences, under 90 words. Reply in the language she uses.
    """

    /// Added when retrieved passages are sent.
    public static let memoryPart = """
    Passages from her journal or earlier talks are given below. You may link to one only when it clearly relates to \
    what she is saying now: quote her words from it exactly, with the date exactly as shown (for example "on Nov 3 \
    you wrote ..."), then ask how it sits with what she is saying now. Never invent or reword earlier words, never \
    interpret them, never say she always or never does something, and never bring up something painful from them \
    that she has not raised. Older passages may not describe how she feels now; where a passage says how long ago \
    it was, you may mention that loosely ("a few months ago"). This replaces the rule about not mentioning earlier notes.
    """

    /// Added when her About me is sent.
    public static let aboutMePart = """
    Her own About me is given below for context only: use it to understand her and choose better reflections; never \
    quote it, never bring up anything from it she has not raised, and never diagnose from it.
    """

    public static func system(hasPassages: Bool, hasAboutMe: Bool) -> String {
        [system, hasPassages ? memoryPart : nil, hasAboutMe ? aboutMePart : nil].compactMap { $0 }.joined(separator: " ")
    }

    /// Shown instead of a reply that failed the checks twice (kept for tests and the first fallback).
    public static let fallbackReply = "Say more about that, if you want. What feels most important about it right now?"
    /// Fixed lines, never the same one twice in a row (owner, 2026-11-04: one line on repeat "will annoy the hell
    /// out of me" in distress). The last one offers Something to try instead of another question.
    public static let fallbacks = [
        fallbackReply,
        "That sounds like a lot to hold. Where do you notice it most right now, in your thoughts or in your body?",
        "Take your time. What is the hardest part of this for you?",
        "If words are hard right now, Something to try is one tap away. Or say whatever comes next.",
    ]

    public static func fallback(after previous: [String]) -> String {
        let used = Set(previous.suffix(3))
        return fallbacks.first { !used.contains($0) } ?? fallbacks[previous.count % fallbacks.count]
    }

    /// Shown once, by the app, when a session has gone on long (no model).
    public static let wrapLine = "We have been at this a while. Want to keep a note of it and stop here, or say one more thing?"
    /// Shown when the one more message has been answered.
    public static let endLine = "That is the end of this one. You can keep a note of it, or leave it."

    public static let maxTurnsInPrompt = 12
    public static let maxWords = 90
    public static let wrapMinutes = 20
    public static let wrapMessages = 30
    public static let maxSnippets = 4

    // MARK: Session limits

    /// True after 20 minutes or 30 of her messages.
    public static func shouldWrap(startedAt: Date, now: Date = .now, herMessages: Int) -> Bool {
        herMessages >= wrapMessages || now.timeIntervalSince(startedAt) >= Double(wrapMinutes) * 60
    }

    // MARK: Safety (on the phone, before any model call)

    public static func safety(herMessage: String) -> TalkSafety {
        if SafetyCheck.mentionsSelfHarm(herMessage) || ListenSafety.flags(herMessage) { return .selfHarm }
        if ListenSafety.feelsHeavy(herMessage) || KeepOrRelease.readsHopeless(herMessage) { return .heavy }
        return .none
    }

    // MARK: Prompt

    /// "4 Nov 2026". Fixed format so the model sees one shape and the checker knows the numbers.
    /// The passages a reply actually used: it names the passage's date or quotes from it (owner, 2026-11-04:
    /// a chip for every passage sent was "annoying").
    public static func usedSnippets(reply: String, snippets: [Snippet], calendar: Calendar = .current) -> [Snippet] {
        let r = ListenRules.normalised(reply)
        let quotes = quotedPhrases(reply).map { ListenRules.normalised($0) }.filter { $0.count >= 8 }
        return snippets.filter { s in
            let d = ListenRules.normalised(dateText(s.date, calendar: calendar))
            let text = ListenRules.normalised(s.text)
            return (!d.isEmpty && r.contains(d)) || quotes.contains { text.contains($0) }
        }
    }

    public static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    /// Her About me, for context only (owner, 2026-11-04: "full About me"). Lines with a quiet topic are
    /// dropped; long documents are clipped. The whole request is redacted before it leaves the phone.
    public static func aboutMeBlock(_ markdown: String, quietTopics: [String]) -> String {
        let topics = quietTopics.map { $0.lowercased() }.filter { !$0.isEmpty }
        let kept = markdown.components(separatedBy: .newlines).filter { line in
            let l = line.lowercased()
            return !topics.contains(where: l.contains)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { return "" }
        return "Her About me, in her own words (context only; do not quote):\n\"\"\"\n" + String(kept.prefix(12000)) + "\n\"\"\"\n\n"
    }

    /// Her turns that may go to a model: a turn that mentions self-harm never does (on the phone, fixed words).
    public static func sendable(_ turns: [TalkTurn]) -> [TalkTurn] {
        turns.filter { $0.role == .app || !CloudGate.blocks($0.text) }
    }

    public static func prompt(turns allTurns: [TalkTurn], snippets: [Snippet], aboutMe: String = "", calendar: Calendar = .current,
                              now: Date = Date()) -> String {
        let turns = sendable(allTurns)
        var out = aboutMe
        if !snippets.isEmpty {
            out += "Notes from her journal:\n"
            for s in snippets.prefix(maxSnippets) {
                let body = s.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                out += s.fromTalk
                    ? "- Her words in a talk on \(dateText(s.date, calendar: calendar)) (\(MemoryRecency.ageText(of: s.date, now: now))): \"\(body)\"\n"
                    : "- Your note from \(dateText(s.date, calendar: calendar)): \"\(body)\"\n"
            }
            out += "\n"
        }
        out += "Conversation:\n"
        for t in turns.suffix(maxTurnsInPrompt) {
            out += (t.role == .her ? "Her: " : "You: ") + t.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        // Models copy their own earlier replies as a talk grows (owner report, 2026-11-04: long talks turned
        // templated). Name how the last reply began and ask for something different and short.
        if let last = turns.last(where: { $0.role == .app })?.text {
            let opening = last.split(whereSeparator: \.isWhitespace).prefix(4).joined(separator: " ")
            out += "\nYour last reply began \"\(opening)\". Begin this one differently, and keep it to two or three short sentences.\n"
        }
        out += "\nYour reply:"
        return out
    }

    // MARK: Checking a reply

    /// Phrases that claim feelings or a relationship. Matched as whole words, even if she used them.
    /// Relationship talk and claims of her own feelings beyond care (owner, 2026-11-04: Claude's own voice, but
    /// still no companion bond). "I'm sorry that happened" and "I'm glad you told me" are fine.
    static let relationshipTerms = ["i love you", "love you", "i'll always be here", "i will always be here", "always here for you",
                                    "i miss you", "our bond", "our connection", "i need you", "proud of you", "i'm your friend",
                                    "you have me", "i'm real", "i am real", "i'm conscious", "between us"]
    /// Promises and comfort about how things will turn out.
    static let promisingTerms = ["will be okay", "'ll be okay", "will be ok", "will be fine", "'ll be fine", "will be alright", "'ll be alright", "will work out", "will pass",
                                 "will get better", "going to be fine", "all be fine", "nothing to worry", "don't worry", "do not worry"]
    /// Agreeing with a harsh belief or giving events special meaning.
    static let agreeingTerms = ["you're right", "you are right", "that's true", "it's a sign", "it is a sign", "meant to be",
                                "only you can", "the universe"]
    /// Her last message asks for ideas: then gentle suggestions are allowed.
    static let asksForIdeas = ["what should i do", "what do i do", "what can i do", "any advice", "any ideas", "suggest", "advice",
                               "how do i", "what would you do", "tips", "help me figure", "what could i do", "ano gagawin ko",
                               "どうしたらいい", "どうすれば"]

    /// nil if the reply is fine, else a short reason (never content). `snippets` lets the reply name
    /// a note's date.
    public static func check(reply: String, herWords: String, quietTopics: [String], snippets: [Snippet] = [],
                             earlierReplies: [String] = [], calendar: Calendar = .current) -> String? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "empty" }
        // Owner, 2026-11-04: asking where she feels it, again and again, is pushy. Once per talk at most.
        if earlierReplies.contains(where: asksAboutBody), asksAboutBody(text) { return "repeat body" }
        // Numbers are allowed only if she said them or they are in a note's date.
        let dateNumbers = snippets.map { dateText($0.date, calendar: calendar) }.joined(separator: " ")
        let snippetNumbers = snippets.flatMap { OutputValidator.numbers(in: $0.text) }.joined(separator: " ")
        let policy = OutputPolicy(input: herWords + " " + dateNumbers + " " + snippetNumbers, userText: herWords,
                                  quietTopics: quietTopics, maxCharacters: 900)
        // Claude's own voice (owner, 2026-11-04): validation and "it's okay to feel" are fine; labels, quiet topics
        // and invented numbers are not. Advice only when she asks for ideas, and never in a question's place.
        for v in OutputValidator.check(text, policy) {
            switch v {
            case .label: return "label"
            case .quietTopic: return "quiet topic"
            case .numberNotInInput: return "number"
            case .tooLong: return "too long"
            case .empty: return "empty"
            case .advice, .reassurance: continue
            }
        }
        let lastHer = (herWords.components(separatedBy: "\n").last ?? "").lowercased()
        if !asksForIdeas.contains(where: lastHer.contains) {
            let statements = ListenRules.sentences(in: text).filter { !$0.contains("?") && !$0.contains("\u{FF1F}") }.joined(separator: " ")
            if ListenRules.matches(ListenRules.adviceTerms, in: ListenRules.normalised(statements)) { return "advice" }
        }
        if text.filter({ $0 == "?" || $0 == "\u{FF1F}" }).count > 1 { return "too many questions" }
        if wordCount(text) > maxWords { return "too long" }
        let lower = ListenRules.normalised(text)
        // Her own quoted words are not the app speaking about itself.
        let unquoted = quotedPhrases(text).reduce(lower) { $0.replacingOccurrences(of: ListenRules.normalised($1), with: " ") }
        if relationshipTerms.contains(where: unquoted.contains) { return "persona" }
        if agreeingTerms.contains(where: unquoted.contains) { return "agreement" }
        if ListenRules.matches(OutputValidator.labels + ListenRules.labelTerms, in: unquoted, unless: ListenRules.normalised(herWords)) { return "label" }
        // A remembered quote must be real: every quoted phrase must appear in what she said or in a passage
        // sent with this turn (owner, 2026-11-04 test: a small model invented "on <date> you wrote ...").
        if text.contains("<date>") { return "placeholder" }
        let sources = ListenRules.normalised(herWords + " " + snippets.map(\.text).joined(separator: " "))
        for q in quotedPhrases(text) where q.count >= 8 {
            if !sources.contains(ListenRules.normalised(q).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) {
                return "invented quote"
            }
        }
        // A mirror is tentative: certainty about causes, hidden meanings or her inner life is rejected.
        if certaintyTerms.contains(where: lower.contains) { return "certainty" }
        if promisingTerms.contains(where: lower.contains) { return "reassurance" }
        return nil
    }

    /// Text between quotation marks (straight or curly, single-word quotes ignored by the caller).
    static func quotedPhrases(_ s: String) -> [String] {
        let pattern = #"[\"\u201C]([^\"\u201C\u201D]+)[\"\u201D]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range(at: 1), in: s).map { String(s[$0]).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }
        }
    }

    static let certaintyTerms = [
        "which means", "this means", "that means", "a sign of", "this is a sign", "that's a sign", "caused by", "the reason you",
        "that's why you", "this is why you", "because you", "you are probably", "you're probably", "you must be", "you are clearly",
        "you're clearly", "you always", "you never", "you clearly", "the real reason", "deep down you",
    ]

    static func wordCount(_ s: String) -> Int {
        let t = NLTokenizer(unit: .word)
        t.string = s
        var n = 0
        t.enumerateTokens(in: s.startIndex..<s.endIndex) { r, _ in
            if s[r].contains(where: { $0.isLetter || $0.isNumber }) { n += 1 }
            return true
        }
        return n
    }

    static func matchesWord(_ terms: [String], in text: String) -> Bool {
        terms.contains { t in
            let p = "(?<![\\p{L}\\p{N}'])" + NSRegularExpression.escapedPattern(for: t) + "(?![\\p{L}\\p{N}'])"
            return text.range(of: p, options: .regularExpression) != nil
        }
    }

    // MARK: Generating a reply

    // MARK: Notes about the talk (owner, 2026-11-05: the model never writes in her voice)

    public static let notesSystem = """
    You write short notes about a conversation a person just had with a reflective journal app, addressed to her as \
    "you" (for example "You talked about ..."). Never write as her and never use "I". Describe only what she said: \
    what happened, what she felt, what she needs or wants. 2 to 4 short lines. No advice, no diagnosis or labels, no \
    reassurance, no names of other people. Under 70 words. Write in the language she used.
    """

    public static func notesPrompt(turns: [TalkTurn]) -> String {
        "The conversation:\n" + sendable(turns).map { ($0.role == .her ? "Her: " : "App: ") + $0.text }.joined(separator: "\n")
            + "\n\nThe notes, addressed to her as \"you\":"
    }

    /// The notes if they pass the checks, else nil (the entry then holds only her own words).
    /// They must be addressed to her: a first-person line would read as her own writing.
    public static func checkNotes(_ raw: String, herWords: String, quietTopics: [String]) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, wordCount(s) <= 90, s.split(whereSeparator: \.isNewline).count <= 6 else { return nil }
        guard s.range(of: #"(?i)(?<![\p{L}\p{N}'])(i|i'm|i've|i'll|i'd|my|me|myself)(?![\p{L}\p{N}'])"#, options: .regularExpression) == nil else { return nil }
        let policy = OutputPolicy(input: herWords, userText: herWords, quietTopics: quietTopics, maxCharacters: 700)
        return OutputValidator.check(s, policy).isEmpty ? s : nil
    }

    /// Reasons a reply can be rescued by dropping sentences rather than thrown away.
    /// A question about her body (where she feels it, chest, stomach, physically ...).
    static let bodyTerms = ["body", "chest", "stomach", "throat", "shoulders", "physically", "sensation", "where do you feel",
                            "where you feel", "where in you", "feel it in", "notice it in", "tight", "tension", "breath"]

    public static func asksAboutBody(_ text: String) -> Bool {
        KeepOrRelease.sentences(text).contains { s in
            (s.contains("?") || s.contains("\u{FF1F}")) && bodyTerms.contains(where: s.lowercased().contains)
        }
    }

    static let salvageable: Set<String> = ["repeat body", "invented quote", "placeholder", "too many sentences", "too long", "number", "advice", "reassurance"]

    /// Drops sentences that quote anything not in the sources, mention a date placeholder, or carry a number
    /// she did not give; then keeps the first reflection and the last question.
    public static func salvage(_ reply: String, herWords: String, snippets: [Snippet], dropBodyQuestions: Bool = false) -> String {
        let sources = ListenRules.normalised(herWords + " " + snippets.map(\.text).joined(separator: " "))
        let given = Set(OutputValidator.numbers(in: herWords + " " + snippets.map(\.text).joined(separator: " ")))
        var keep: [String] = []
        for sentence in KeepOrRelease.sentences(reply) {
            if dropBodyQuestions, asksAboutBody(sentence) { continue }
            let l = sentence.lowercased()
            if l.contains("<date>") || l.contains("[date]") || l.contains("you wrote") || l.contains("you said on") { continue }
            if quotedPhrases(sentence).contains(where: { q in
                q.count >= 8 && !sources.contains(ListenRules.normalised(q).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
            }) { continue }
            if OutputValidator.numbers(in: sentence).contains(where: { !given.contains($0) }) { continue }
            // A statement that reads as advice or reassurance is dropped; questions stay.
            if !sentence.contains("?"), ListenRules.rejection(sentence, transcript: herWords, quietTopics: [], reflective: true) == "advice"
                || ListenRules.rejection(sentence, transcript: herWords, quietTopics: [], reflective: true) == "reassurance" { continue }
            keep.append(sentence)
        }
        guard let question = keep.last(where: { $0.contains("?") || $0.contains("\u{FF1F}") }) else { return keep.prefix(2).joined(separator: " ") }
        let reflections = keep.filter { $0 != question }.prefix(2)
        return (Array(reflections) + [question]).joined(separator: " ")
    }

    /// Asks the model and checks the reply. A reply that fails only on a stray quote, number or length is
    /// rescued by dropping the offending sentences. Otherwise it asks once more, telling the model why. After
    /// that a fixed line stands in, never the same one twice in a row. Reasons are logged, never text.
    public static func reply(model: any LanguageModel, turns: [TalkTurn], snippets: [Snippet], quietTopics: [String],
                             aboutMe: String = "", previousFallbacks: [String] = [], calendar: Calendar = .current,
                             now: Date = Date(), log: (String) -> Void = { _ in }) async -> TalkReplyResult {
        let turns = sendable(turns)
        let herWords = turns.filter { $0.role == .her }.map(\.text).joined(separator: "\n")
        let earlier = turns.filter { $0.role == .app }.map(\.text)
        let used = Array(snippets.prefix(maxSnippets))
        let about = aboutMeBlock(aboutMe, quietTopics: quietTopics)
        let sys = system(hasPassages: !used.isEmpty, hasAboutMe: !about.isEmpty)
        let basePrompt = prompt(turns: turns, snippets: used, aboutMe: about, calendar: calendar, now: now)
        var reached = false
        var lastReason: String?
        for attempt in 0..<2 {
            var p = basePrompt
            if attempt > 0, let r = lastReason {
                p = basePrompt.replacingOccurrences(of: "Your reply:", with: "Your previous reply could not be used (\(r)). "
                    + "Write a new one: at most three sentences, no quotes except her words in this conversation, one question.\nYour reply:")
            }
            let request = GenerationRequest(system: sys, prompt: p, maxTokens: 160, temperature: attempt == 0 ? 0.4 : 0.6, ownText: herWords)
            guard let raw = try? await model.generate(request) else { log("unreachable"); continue }
            reached = true
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let why = check(reply: text, herWords: herWords, quietTopics: quietTopics, snippets: used, earlierReplies: earlier, calendar: calendar) else {
                return .model(text)
            }
            log("rejected: \(why)")
            lastReason = why
            if salvageable.contains(why) {
                let rescued = salvage(text, herWords: herWords, snippets: used, dropBodyQuestions: earlier.contains(where: asksAboutBody))
                if !rescued.isEmpty, check(reply: rescued, herWords: herWords, quietTopics: quietTopics, snippets: used, earlierReplies: earlier, calendar: calendar) == nil {
                    log("rescued")
                    return .model(rescued)
                }
            }
        }
        return reached ? .fallback(fallback(after: previousFallbacks)) : .unavailable
    }
}

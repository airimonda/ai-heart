import Foundation

// Notes kept from a let-go entry (docs/16). Instead of one or two of her lines, the app keeps
// short notes on how she reacted, the way a clinician's session note is laid out:
// what happened, the reaction in five parts (thought, feeling, body, urge), how strong it read,
// which needs seemed touched, and what helped. Every part except "what happened" is either
// her own words (checked against the entry) or picked from a fixed list. The model never
// invents a feeling, a need, a cause or advice; anything it writes that fails a check is dropped.

/// A feeling word from a fixed list. Closed on purpose: naming the feeling is the useful part
/// (affect labeling), and a fixed list stops the model from inventing labels.
public enum NoteFeeling: String, CaseIterable, Codable, Sendable {
    case happy, calm, close, proud, relieved, hopeful,
         sad, hurt, lonely, angry, frustrated, scared, anxious, ashamed, guilty, disappointed,
         overwhelmed, tired, numb, jealous, helpless, confused

    /// Words in her text that point to the feeling (rule-based fallback). English and Japanese.
    var cues: [String] {
        switch self {
        case .happy: ["happy", "glad", "joy", "嬉しい", "楽しい"]
        case .calm: ["calm", "peaceful", "relaxed", "落ち着"]
        case .close: ["felt close", "connected", "together"]
        case .proud: ["proud", "i managed", "頑張った"]
        case .relieved: ["relieved", "relief", "ほっと"]
        case .hopeful: ["hopeful", "looking forward", "楽しみ"]
        case .sad: ["sad", "cried", "crying", "tears", "悲しい", "泣"]
        case .hurt: ["hurt", "stung", "傷つ"]
        case .lonely: ["lonely", "alone", "nobody", "no one", "孤独", "寂しい", "一人"]
        case .angry: ["angry", "mad", "furious", "rage", "yelled", "shouted", "怒", "腹が立"]
        case .frustrated: ["frustrat", "annoyed", "irritat", "イライラ"]
        case .scared: ["scared", "afraid", "terrified", "怖い"]
        case .anxious: ["anxious", "nervous", "worried", "panic", "dread", "不安", "心配"]
        case .ashamed: ["ashamed", "shame", "humiliat", "embarrass", "恥"]
        case .guilty: ["guilty", "my fault", "i shouldn't have", "罪悪感", "私のせい"]
        case .disappointed: ["disappoint", "let down", "がっかり"]
        case .overwhelmed: ["overwhelm", "too much", "drowning", "いっぱいいっぱい"]
        case .tired: ["tired", "exhausted", "drained", "worn out", "疲れ"]
        case .numb: ["numb", "empty", "nothing at all", "空っぽ"]
        case .jealous: ["jealous", "envious", "嫉妬", "羨"]
        case .helpless: ["helpless", "powerless", "hopeless", "nothing i can do", "どうしようもない"]
        case .confused: ["confused", "don't understand", "makes no sense", "混乱"]
        }
    }
}

/// How strong the moment read. A three-step read, never a score: the app cannot measure distress,
/// only notice how strongly she wrote about it.
public enum NoteIntensity: String, Codable, Sendable {
    case mild, strong, veryStrong = "very strong"

    public var title: String {
        switch self {
        case .mild: "Mild"
        case .strong: "Strong"
        case .veryStrong: "Very strong"
        }
    }
}

/// A core need, from a fixed list built on two research frameworks: basic psychological needs
/// (self-determination theory: connection, choice, feeling capable) and the core emotional needs of
/// schema therapy (safety, being understood, fairness, room to express feelings, ease and play). Rest is
/// added because short sleep and depletion raise emotional reactivity. See docs/16.
public enum CoreNeed: String, CaseIterable, Codable, Sendable {
    case safety, connection, understood, fairness, choice, capable, expression, rest, ease

    public var title: String {
        switch self {
        case .safety: "To feel safe"
        case .connection: "Closeness, to belong"
        case .understood: "To be heard and understood"
        case .fairness: "To be treated fairly"
        case .choice: "A say in what happens"
        case .capable: "To feel capable"
        case .expression: "Room to say what you feel"
        case .rest: "Rest"
        case .ease: "Ease, something light"
        }
    }

    public var framework: String {
        switch self {
        case .safety: "Schema therapy: safety and stability"
        case .connection: "Self-determination theory: relatedness"
        case .understood: "Schema therapy: validation of feelings"
        case .fairness: "Schema therapy (2021 reformulation): fairness"
        case .choice: "Self-determination theory: autonomy"
        case .capable: "Self-determination theory: competence"
        case .expression: "Schema therapy: freedom to express needs and emotions"
        case .rest: "Sleep and emotion research: depletion raises reactivity"
        case .ease: "Schema therapy: spontaneity and play"
        }
    }

    /// Words that point to the need being missing (rule-based fallback).
    var missingCues: [String] {
        switch self {
        case .safety: ["unsafe", "scared", "afraid", "threat", "not safe", "怖い", "危ない"]
        case .connection: ["alone", "lonely", "nobody", "no one", "left out", "miss them", "miss him", "miss her", "孤独", "寂しい"]
        case .understood: ["nobody listened", "no one listened", "not heard", "didn't listen", "doesn't listen", "don't listen", "not listening", "ignored", "dismissed",
                           "doesn't understand", "didn't understand", "nobody understands", "misunderstood", "分かってくれない", "無視"]
        case .fairness: ["unfair", "not fair", "blamed me", "disrespect", "treated me like", "不公平", "理不尽"]
        case .choice: ["forced", "no choice", "had no say", "made me", "controlled", "pressured", "無理やり"]
        case .capable: ["failed", "failure", "useless", "not good enough", "messed up", "screwed up", "can't do anything", "stupid", "ダメ", "失敗"]
        case .expression: ["couldn't say", "held it in", "kept quiet", "bottled", "couldn't speak", "言えなかった"]
        case .rest: ["exhausted", "no sleep", "didn't sleep", "couldn't sleep", "drained", "worn out", "眠れ", "疲れ"]
        case .ease: ["no fun", "all work", "no break", "never relax", "休めない"]
        }
    }

    /// Words that point to the need being met.
    var metCues: [String] {
        switch self {
        case .safety: ["felt safe", "safe again", "安心"]
        case .connection: ["called", "hugged", "talked to", "was there for me", "together"]
        case .understood: ["listened", "understood me", "felt heard", "got it"]
        case .fairness: ["was fair", "apologized", "apologised", "謝ってくれ"]
        case .choice: ["i decided", "i chose", "said no", "my choice"]
        case .capable: ["i managed", "i handled", "i did it", "proud"]
        case .expression: ["told them", "i said how", "let it out", "talked about it"]
        case .rest: ["slept", "nap", "rested", "lay down"]
        case .ease: ["laughed", "funny", "played", "fun"]
        }
    }
}

/// One part of a behaviour chain (DBT chain analysis): each of her sentences is labelled with one.
/// The labels are the model's; the sentences are always hers, copied whole.
public enum NotePart: String, CaseIterable, Codable, Sendable {
    case trigger, thought, feeling, body, action, payoff, cost, want, helped, context
    // Reflection parts, for long entries that tell a story rather than one moment (owner, 2026-11-04).
    case hurt, longing, proud, insight, others

    /// Short entries: a behaviour chain (DBT). Long, reflective entries: what was hard, what she longs
    /// for, what she is proud of, what she understands now, what she wants (narrative reflection).
    public static let chainParts: [NotePart] = [.trigger, .thought, .feeling, .body, .action, .payoff, .cost, .want, .helped, .context]
    public static let reflectionParts: [NotePart] = [.hurt, .longing, .proud, .insight, .want, .others, .context]
    /// Card order.
    public static let shown: [NotePart] = [.trigger, .thought, .feeling, .body, .action, .payoff, .cost,
                                           .hurt, .longing, .proud, .insight, .want, .helped]

    public var title: String {
        switch self {
        case .trigger: "What set it off"
        case .thought: "What went through your mind"
        case .feeling: "How it felt"
        case .body: "In your body"
        case .action: "What you did, or felt pulled to do"
        case .payoff: "What it gave you in the moment"
        case .cost: "What it cost you"
        case .want: "What you want"
        case .helped: "What helped"
        case .context: "Background"
        case .hurt: "What was hard for you"
        case .longing: "What you long for"
        case .proud: "What you are proud of"
        case .insight: "What you understand now"
        case .others: "About others"
        }
    }

    /// The model's label definitions, in the prompt.
    var definition: String {
        switch self {
        case .trigger: "what sets it off, or when it tends to happen"
        case .thought: "a thought, worry, fear or belief she has"
        case .feeling: "an emotion she names (not one caused by her action)"
        case .body: "a body sensation"
        case .action: "what she did, does, or feels pulled to do"
        case .payoff: "how her action makes her feel in the moment, or what it gives her"
        case .cost: "what it costs her, or how a slip or the habit makes her feel after"
        case .want: "what she wants, values or intends"
        case .helped: "something that helped her"
        case .context: "background that is none of the above"
        case .hurt: "something that was hard or painful for her herself"
        case .longing: "something she longs for, misses or wishes she had had"
        case .proud: "something she is proud of or glad about in herself or her life"
        case .insight: "something she understands or realises now"
        case .others: "mainly about someone else's life, acts or words"
        }
    }
}

public struct NeedNote: Codable, Equatable, Sendable {
    public var need: CoreNeed
    public var met: Bool
    /// Her words that show it.
    public var quote: String

    public init(need: CoreNeed, met: Bool, quote: String) {
        self.need = need; self.met = met; self.quote = quote
    }
}

public struct ReleaseNote: Codable, Equatable, Sendable {
    /// One neutral line, no painful detail. The only free-written part; checked and dropped if it fails.
    public var happened: String?
    /// Her words for what went through her mind.
    public var thought: String?
    public var feelings: [NoteFeeling] = []
    /// Her words about her body.
    public var body: String?
    /// Her words for what she did or wanted to do.
    public var urge: String?
    public var intensity: NoteIntensity?
    public var intensityQuote: String?
    public var needs: [NeedNote] = []
    /// Her words about what helped, what she knows or what she will do.
    public var helped: [String] = []
    /// True when written by the on-device model (checked), false when by rules alone.
    public var byModel: Bool = false
    public var version: Int = 1
    /// Version 2: her sentences by chain part (rawValue -> sentences, in her order). Optional so
    /// version-1 notes still decode.
    public var parts: [String: [String]]?
    /// True for an entry she let go (owner, 2026-11-05): only the summary is kept, none of her exact lines.
    /// Optional so older notes still decode.
    public var summaryOnly: Bool?
    /// Version 3 (owner, 2026-11-05: "just summaries, and some direct lines if they're really helpful"):
    /// one short summary line per chain part (rawValue -> line), written by the model and checked.
    /// `parts` is still kept underneath for the affirmations, the therapist report and retrieval.
    public var partSummaries: [String: String]?
    /// At most two of her sentences worth keeping word for word.
    public var keyLines: [String]?
    /// Notes about a "Talk it through" conversation, addressed to her as "you" (owner, 2026-11-05). Written
    /// by the model and checked; never her words. Optional so older notes still decode.
    public var talkNotes: String?
    /// Honest affirmations written by the model from her sentences and checked by fixed rules (owner, 2026-11-05;
    /// `HonestAffirmations.parseWritten`). Optional so older notes still decode; nil means the fixed templates show.
    public var affirmations: [WrittenAffirmation]?

    public init() {}

    /// The note without her words: the neutral one-line summary, feelings, how strong it read,
    /// and which needs seemed met or missing. Her sentences and quotes are dropped.
    public var summary: ReleaseNote {
        var n = self
        n.thought = nil
        n.body = nil
        n.urge = nil
        n.intensityQuote = nil
        n.needs = needs.map { NeedNote(need: $0.need, met: $0.met, quote: "") }
        n.helped = []
        n.parts = nil
        n.partSummaries = nil
        n.keyLines = nil
        n.talkNotes = nil
        // Written affirmations survive only without her words: no quotes, no anchors (owner, 2026-11-05).
        n.affirmations = affirmations?.compactMap { a in
            let quoteMarks = CharacterSet(charactersIn: "\"\u{201C}\u{201D}\u{300C}\u{300D}")
            guard a.text.rangeOfCharacter(from: quoteMarks) == nil, a.basis.rangeOfCharacter(from: quoteMarks) == nil else { return nil }
            return WrittenAffirmation(text: a.text, basis: a.basis, anchors: [])
        }
        if n.affirmations?.isEmpty == true { n.affirmations = nil }
        n.summaryOnly = true
        return n
    }

    public func sentences(_ part: NotePart) -> [String] { parts?[part.rawValue] ?? [] }
    public func partSummary(_ part: NotePart) -> String? { partSummaries?[part.rawValue] }

    public var isEmpty: Bool {
        (parts ?? [:]).values.allSatisfy(\.isEmpty) && happened == nil && talkNotes == nil && thought == nil && feelings.isEmpty && body == nil && urge == nil
            && intensity == nil && needs.isEmpty && helped.isEmpty
    }

    public var missingNeeds: [NeedNote] { needs.filter { !$0.met } }
    public var metNeeds: [NeedNote] { needs.filter(\.met) }

    /// Every quote, for safety and quiet-topic checks.
    public var allText: [String] {
        [happened, thought, body, urge, intensityQuote].compactMap { $0 } + needs.map(\.quote) + helped
            + (parts ?? [:]).values.flatMap { $0 } + (partSummaries ?? [:]).values + (keyLines ?? []) + [talkNotes].compactMap { $0 }
            + (affirmations ?? []).flatMap { [$0.text] + $0.anchors }
    }

    public func encoded() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ s: String?) -> ReleaseNote? {
        guard let d = s?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReleaseNote.self, from: d)
    }
}

public enum ReleaseNotes {
    static let maxQuoteWords = 16
    static let maxNeeds = 3

    // MARK: Prompts (two short calls: a small model is more reliable with fewer fields per call)

    public static let system = """
    You take brief, neutral notes on a journal entry, like a careful therapist's session note. \
    You copy her exact words where asked. You pick words only from the lists given. \
    You add nothing of your own: no advice, no diagnosis, no labels, no reassurance, no guesses about causes.
    """

    public static func reactionPrompt(text: String) -> String {
        """
        Her entry:
        \"\"\"
        \(clip(text))
        \"\"\"
        Write exactly these lines:
        HAPPENED: one short, neutral line about the situation, under 12 words, without painful details
        THOUGHT: her exact words for a thought she had, or none
        FELT: one to three words from this list only: \(NoteFeeling.allCases.map(\.rawValue).joined(separator: ", "))
        BODY: her exact words about her body, or none
        URGE: her exact words for what she did or wanted to do, or none
        INTENSITY: mild, strong or very strong
        SHOWN_BY: her exact words that show how strong it was
        """
    }

    public static func needsPrompt(text: String) -> String {
        """
        Her entry:
        \"\"\"
        \(clip(text))
        \"\"\"
        Needs list: \(CoreNeed.allCases.map(\.rawValue).joined(separator: ", "))
        safety = to feel safe; connection = closeness, belonging; understood = to be heard; fairness = to be treated fairly; \
        choice = a say in what happens; capable = to feel able; expression = room to say what she feels; \
        rest = rest, sleep; ease = something light, play.
        Write up to three lines, one per need her words clearly touch, in this form:
        NEED: name | missing or met | her exact words that show it
        Then one line:
        HELPED: her exact words about what helped, what she knows or what she will do, or none
        If no need is clearly touched, write no NEED lines.
        """
    }

    static func clip(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(2400))
    }

    // MARK: Version 2: one short question per call (tested on Qwen3-VL 4B, docs/16)
    // A small model copies words well but puts them in the wrong box when asked to fill many
    // fields at once. Labelling numbered sentences, and one question per call, is far more reliable.

    public static let systemV2 = """
    You are a careful therapist reading a client's journal entry and taking brief notes. \
    You only label and point to her own sentences. You never add advice, diagnoses, labels or reassurance.
    """
    public static let systemYesNo = "You are a careful therapist reading a client's journal entry. Answer with one word: yes or no."

    /// Her sentences, at most 30, each whole.
    /// All of her sentences (owner, 2026-11-04: "read the whole thing"; a 30-sentence cap had cut
    /// off the second half of a long entry). Long entries are labelled in chunks.
    public static func noteSentences(_ text: String) -> [String] {
        Array(text.components(separatedBy: .newlines).flatMap(KeepOrRelease.sentences).prefix(200))
    }

    public static let chunkSize = 15

    /// Index ranges of the label chunks.
    public static func chunks(_ count: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: chunkSize).map { $0..<min($0 + chunkSize, count) }
    }

    static func numbered(_ sentences: [String]) -> String {
        "Her entry, one sentence per line:\n" + sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n\n"
    }

    /// Labels for one chunk of a longer entry. The whole entry is given first for context, so she is
    /// read as one person telling one story; only the chunk's sentences are labelled.
    public static func labelPrompt(_ s: [String], chunk: Range<Int>) -> String {
        guard s.count > chunkSize else { return labelPrompt(s) }
        let whole = clip(s.joined(separator: " "))
        let lines = chunk.map { "\($0 - chunk.lowerBound + 1). \(s[$0])" }.joined(separator: "\n")
        return "Her whole entry, for context:\n\"\"\"\n\(whole)\n\"\"\"\n\nNow label only these sentences from it:\n\(lines)\n\n"
            + labelInstructions(s.count > chunkSize ? NotePart.reflectionParts : NotePart.chainParts)
    }

    static func labelInstructions(_ set: [NotePart]) -> String {
        "Labels:\n" + set.map { "\($0.rawValue.uppercased()) = \($0.definition)" }.joined(separator: "\n")
            + "\n\nGive each sentence exactly one label. Also say whose sentence it is: SELF if it is about what she herself does, "
            + "thinks, feels or wants, including a wish or vow she makes for someone she loves; OTHER if it is mainly about what "
            + "someone else did, does, says, thinks or wants. One line per sentence, like:\n1: CONTEXT | SELF\n2: TRIGGER | OTHER\nNothing else."
    }

    public static func labelPrompt(_ s: [String]) -> String {
        numbered(s) + labelInstructions(s.count > chunkSize ? NotePart.reflectionParts : NotePart.chainParts)
    }

    /// Parts that can only be hers. A sentence about someone else in one of these is what set it off.
    static let selfOnly: Set<NotePart> = [.thought, .feeling, .body, .action, .payoff, .cost, .want, .helped,
                                          .hurt, .longing, .proud, .insight]

    /// Sentences mainly about someone else (owner, 2026-11-04: a sentence about her child was filed
    /// as her own act). No I/me, and it opens with another person.
    static let otherOpeners = ["my daughter", "my son", "my mom", "my mother", "my dad", "my father", "my sister", "my brother",
                               "my husband", "my wife", "my partner", "my boyfriend", "my girlfriend", "my friend", "my boss",
                               "my kid", "my child", "my baby", "my family", "my parents", "my coworker", "my colleague",
                               "he ", "she ", "they ", "his ", "her ", "their ", "mom ", "dad ", "everyone ", "nobody ", "people "]
    static let firstPerson = [" i ", " i'm ", " im ", " i've ", " i'd ", " i'll ", " me ", " me.", " me,", " myself", " mine"]

    public static func isAboutOther(_ sentence: String) -> Bool {
        let l = " " + sentence.lowercased().trimmingCharacters(in: .whitespaces) + " "
        guard otherOpeners.contains(where: { l.dropFirst().hasPrefix($0) }) else { return false }
        // "My son will be free" is her vow, not his act.
        if l.contains(" will ") || l.contains(" won't ") || l.contains(" will not ") || l.contains(" will never ") { return false }
        return !firstPerson.contains(where: l.contains)
    }

    public static func summaryPrompt(_ s: [String]) -> String {
        numbered(s) + "In one short neutral line under 12 words, addressed to her as \"you\", what is this entry about? No painful details, no advice. Only the line."
    }

    public static func feelingsPrompt(_ s: [String]) -> String {
        numbered(s) + "Which feelings do her words clearly show? Pick one to three, only from: "
            + NoteFeeling.allCases.map(\.rawValue).joined(separator: ", ")
            + ". Fewer is better: pick a feeling only if a sentence names it or plainly shows it, never to fill the list. "
            + "Only the words, comma separated."
    }

    public static func strengthPrompt(_ s: [String]) -> String {
        numbered(s) + """
        How strong is her distress in this entry?
        none = no distress, a good or neutral moment
        mild = uncomfortable but she is managing
        strong = clearly painful or worrying
        very strong = overwhelming, she says she cannot cope or take it
        Answer with one word from: none, mild, strong, very strong. Then a bar, then the one sentence number that shows it best. Like: strong | 3
        """
    }

    static let needMeaning: [CoreNeed: String] = [
        .safety: "to feel safe", .connection: "closeness with people, to belong",
        .understood: "to be listened to and understood by someone", .fairness: "to be treated fairly",
        .choice: "a say in what happens to her", .capable: "to feel able, good enough, not less than others",
        .expression: "room to say what she feels", .rest: "rest or sleep", .ease: "something light or fun",
    ]

    public static func needPickPrompt(_ s: [String], met: Bool) -> String {
        numbered(s) + "Needs:\n" + CoreNeed.allCases.map { "\($0.rawValue) = \(needMeaning[$0] ?? "")" }.joined(separator: "\n") + "\n\n"
            + (met ? "Which ONE need was clearly met for her here?" : "Which ONE need seems most missing for her here? Think about what lies under her words.")
            + " Answer with the need word, a bar, and the one sentence number. Like: rest | 2. If none is clear, answer: none"
    }

    /// Second, strict check of a picked need against the one sentence it points to.
    public static func needVerifyPrompt(sentence: String, text: String, need: CoreNeed, met: Bool) -> String {
        "Sentence from her journal: \"\(sentence)\"\nWhole entry for context:\n\"\"\"\n\(clip(text))\n\"\"\"\n"
            + "Does that sentence directly show that she is \(met ? "getting" : "missing") this: \(needMeaning[need] ?? need.rawValue)? Be strict."
    }

    /// "3: THOUGHT" lines -> part per sentence. Unknown labels and numbers are ignored.
    /// Chunk answers, numbered from 1 within the chunk, mapped back to entry positions.
    public static func parseLabels(_ raw: String, chunk: Range<Int>) -> [Int: NotePart] {
        Dictionary(uniqueKeysWithValues: parseLabels(raw, count: chunk.count).map { ($0.key + chunk.lowerBound, $0.value) })
    }

    public static func parseLabels(_ raw: String, count: Int) -> [Int: NotePart] {
        var out: [Int: NotePart] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let bits = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }
            guard bits.count == 2, let n = Int(bits[0]), (1...count).contains(n) else { continue }
            let fields = bits[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)).lowercased() }
            guard let first = fields.first, var part = NotePart(rawValue: first) else { continue }
            // Someone else's doing, saying or wanting is what set it off, never her own act or feeling.
            if fields.count > 1, fields[1].hasPrefix("other"), selfOnly.contains(part) {
                part = NotePart.reflectionParts.contains(part) && part != .want ? .others : .trigger
            }
            out[n - 1] = part
        }
        return out
    }

    /// "strong | 3" -> intensity and sentence index. "none" -> nil.
    public static func parseStrength(_ raw: String, count: Int) -> (NoteIntensity, Int?)? {
        let first = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.lowercased() ?? ""
        let bits = first.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }
        guard let word = bits.first else { return nil }
        let level: NoteIntensity
        if word.hasPrefix("very") { level = .veryStrong } else if word.hasPrefix("strong") { level = .strong }
        else if word.hasPrefix("mild") { level = .mild } else { return nil }
        let n = bits.count > 1 ? Int(bits[1].prefix { $0.isNumber }) : nil
        return (level, n.flatMap { (1...count).contains($0) ? $0 - 1 : nil })
    }

    /// "capable | 3" -> need and sentence index.
    public static func parseNeedPick(_ raw: String, count: Int) -> (CoreNeed, Int)? {
        let first = raw.split(whereSeparator: \.isNewline).first.map(String.init)?.lowercased() ?? ""
        let bits = first.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) }
        guard bits.count >= 2, let need = CoreNeed(rawValue: bits[0]),
              let n = Int(bits[1].prefix { $0.isNumber }), (1...count).contains(n) else { return nil }
        return (need, n - 1)
    }

    public static func parseFeelings(_ raw: String) -> [NoteFeeling] {
        var seen = Set<NoteFeeling>()
        return Array(raw.lowercased().split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "\n" })
            .compactMap { NoteFeeling(rawValue: $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))) }
            .filter { seen.insert($0).inserted }.prefix(3))
    }

    /// Builds a version-2 note from the answers. Everything quoted is a whole sentence of hers.
    public static func assemble(sentences: [String], labels: [Int: NotePart], summary: String?, feelings: [NoteFeeling],
                                strength: (NoteIntensity, Int?)?, needs: [NeedNote], text: String, quietTopics: [String] = []) -> ReleaseNote {
        var n = ReleaseNote()
        n.version = 2
        n.byModel = true
        let topics = quietTopics.map { $0.lowercased() }.filter { !$0.isEmpty }
        func usable(_ s: String) -> Bool { !topics.contains(where: s.lowercased().contains) && !SafetyCheck.mentionsSelfHarm(s) }
        var parts: [String: [String]] = [:]
        for (i, sentence) in sentences.enumerated() {
            guard var part = labels[i], part != .context, usable(sentence) else { continue }
            if selfOnly.contains(part), isAboutOther(sentence) { part = sentences.count > chunkSize ? .others : .trigger }
            if part == .others { continue }
            parts[part.rawValue, default: []].append(sentence)
        }
        // A long entry would list dozens of sentences; keep the few that are most hers: first person
        // first, then later in the entry (closer to now). Order on the card stays her order.
        func rank(_ s: String) -> Int {
            let l = " " + s.lowercased() + " "
            return (firstPerson.contains(where: l.contains) || l.hasPrefix(" i ") || l.hasPrefix(" my ") ? 1000 : 0)
                + (sentences.firstIndex(of: s) ?? 0)
        }
        let cap = sentences.count > chunkSize ? 4 : 6
        for (k, list) in parts where list.count > cap {
            let keep = Set(list.sorted { rank($0) > rank($1) }.prefix(cap))
            parts[k] = list.filter(keep.contains)
        }
        n.parts = parts
        n.happened = summary.flatMap { checkedSummary($0, text: text, quietTopics: quietTopics) }
        n.feelings = feelings
        if let (level, i) = strength {
            n.intensity = level
            n.intensityQuote = i.map { sentences[$0] }.flatMap { usable($0) ? $0 : nil }
        }
        n.needs = needs.filter { usable($0.quote) }
        // Physical danger from someone else: safety is the need, whatever the model picked.
        if let danger = sentences.first(where: { s in dangerCues.contains(where: s.lowercased().contains) }), usable(danger) {
            n.needs.removeAll { $0.need == .safety || !$0.met }
            n.needs.insert(NeedNote(need: .safety, met: false, quote: danger), at: 0)
        }
        n.helped = parts[NotePart.helped.rawValue] ?? []
        n.thought = parts[NotePart.thought.rawValue]?.first
        return n
    }

    /// Someone else hurting or threatening her. English, Japanese, Tagalog.
    /// Physical acts only: "hurt me" was dropped (2026-11-05) because it is mostly emotional
    /// ("someone who hurt me years ago") and wrongly forced "to feel safe" over the model's pick.
    static let dangerCues = ["grabbed me", "grabbed my", "hit me", "pushed me", "choked", "threatened", "scared to go home",
                             "afraid to go home", "not safe at home", "unsafe at home", "殴られ", "叩かれ", "sinaktan", "binugbog"]

    // MARK: Version 3: summaries per part, plus a few of her lines

    public static let maxKeyLines = 2

    /// One call: a short summary line for each part that has sentences.
    public static func partSummaryPrompt(_ note: ReleaseNote) -> String? {
        let present = NotePart.shown.filter { !note.sentences($0).isEmpty }
        guard !present.isEmpty else { return nil }
        let blocks = present.map { part in
            "\(part.rawValue.uppercased()) (\(part.title.lowercased())):\n" + note.sentences(part).map { "- \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return """
        Her sentences, sorted into parts:

        \(blocks)

        For each part above, write one short line under 20 words that sums up what she wrote there, addressed to her as "you". \
        Use only what she wrote. No advice, no reassurance, no diagnosis or labels, no guesses about causes, no painful detail. \
        One line per part, like:
        TRIGGER: You had a hard talk with your boss.
        Nothing else.
        """
    }

    /// "TRIGGER: line" -> checked lines, only for parts the note has.
    public static func parsePartSummaries(_ raw: String, note: ReleaseNote, text: String, quietTopics: [String] = []) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in lines(raw) {
            guard let part = NotePart(rawValue: key.lowercased()), !note.sentences(part).isEmpty, out[part.rawValue] == nil,
                  let line = checkedSummary(value, text: text, quietTopics: quietTopics) else { continue }
            out[part.rawValue] = line
        }
        return out
    }

    /// The model picks at most two sentences worth keeping word for word, or none.
    public static func keyLinesPrompt(_ s: [String]) -> String {
        numbered(s) + """
        Most of these notes will be short summaries. Which one or two of her sentences, if any, are worth keeping in her \
        exact words because they say something important clearly: a realisation, what she wants, what helped, or a thought \
        she may want to look at again? Skip plain retelling of events. Answer with sentence numbers, comma separated, or: none
        """
    }

    /// "3, 7" -> her sentences, checked, at most two. Self-harm and quiet topics never kept.
    public static func parseKeyLines(_ raw: String, sentences: [String], quietTopics: [String] = []) -> [String] {
        let topics = quietTopics.map { $0.lowercased() }.filter { !$0.isEmpty }
        let first = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var out: [String] = []
        for bit in first.split(whereSeparator: { $0 == "," || $0 == " " }) {
            guard let n = Int(bit.filter(\.isNumber)), (1...max(sentences.count, 1)).contains(n), n <= sentences.count else { continue }
            let line = sentences[n - 1]
            guard !out.contains(line), !SafetyCheck.mentionsSelfHarm(line), !topics.contains(where: line.lowercased().contains),
                  line.count <= 220 else { continue }
            out.append(line)
            if out.count == maxKeyLines { break }
        }
        return out
    }

    // MARK: Parsing and checks

    /// Reads the reaction lines into `note`. Fields that fail a check are left out.
    public static func parseReaction(_ raw: String, text: String, quietTopics: [String] = [], into note: inout ReleaseNote) {
        for (key, value) in lines(raw) {
            switch key {
            case "HAPPENED":
                if let h = checkedSummary(value, text: text, quietTopics: quietTopics) { note.happened = h }
            case "THOUGHT":
                if let q = checkedQuote(value, text: text, quietTopics: quietTopics) { note.thought = q }
            case "FELT":
                let picked = value.lowercased().split(whereSeparator: { $0 == "," || $0 == "、" || $0 == "/" })
                    .compactMap { NoteFeeling(rawValue: $0.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))) }
                var seen = Set<NoteFeeling>()
                note.feelings = Array(picked.filter { seen.insert($0).inserted }.prefix(3))
            case "BODY":
                if let q = checkedQuote(value, text: text, quietTopics: quietTopics) { note.body = q }
            case "URGE":
                if let q = checkedQuote(value, text: text, quietTopics: quietTopics) { note.urge = q }
            case "INTENSITY":
                let v = value.lowercased()
                note.intensity = v.contains("very") ? .veryStrong : v.contains("strong") ? .strong : v.contains("mild") ? .mild : nil
            case "SHOWN_BY", "SHOWNBY":
                if let q = checkedQuote(value, text: text, quietTopics: quietTopics) { note.intensityQuote = q }
            default: continue
            }
        }
        // A read of how strong it was stands only with her words behind it.
        if note.intensityQuote == nil { note.intensity = nil }
    }

    public static func parseNeeds(_ raw: String, text: String, quietTopics: [String] = [], into note: inout ReleaseNote) {
        var needs: [NeedNote] = []
        for (key, value) in lines(raw) {
            switch key {
            case "NEED":
                let parts = value.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 3,
                      let need = CoreNeed(rawValue: parts[0].lowercased().trimmingCharacters(in: .punctuationCharacters)),
                      !needs.contains(where: { $0.need == need }),
                      let quote = checkedQuote(parts[2], text: text, quietTopics: quietTopics) else { continue }
                let state = parts[1].lowercased()
                let met: Bool
                if state.contains("missing") || state.contains("not met") || state.contains("unmet") { met = false }
                else if state.contains("met") { met = true }
                else { continue }
                needs.append(NeedNote(need: need, met: met, quote: quote))
            case "HELPED":
                if let q = checkedQuote(value, text: text, quietTopics: quietTopics), !note.helped.contains(q) { note.helped.append(q) }
            default: continue
            }
        }
        note.needs = Array(needs.prefix(maxNeeds))
    }

    static func lines(_ raw: String) -> [(String, String)] {
        raw.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let key = parts[0].trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "_")).inverted).uppercased()
            return (key, parts[1].trimmingCharacters(in: .whitespaces))
        }
    }

    static func isNone(_ s: String) -> Bool {
        let t = s.lowercased().trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return t.isEmpty || t == "none" || t == "n/a" || t == "なし"
    }

    /// Her words: mostly copied from the entry, short, and passing the output rules.
    public static func checkedQuote(_ value: String, text: String, quietTopics: [String] = []) -> String? {
        let q = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’「」"))
        guard !isNone(q), q.split(whereSeparator: \.isWhitespace).count <= maxQuoteWords || ListenRules.isCJK(q),
              q.count <= 140, ListenSort.isHerWords(q, transcript: text) else { return nil }
        let policy = OutputPolicy(input: text, userText: text, quietTopics: quietTopics, maxCharacters: 140)
        return OutputValidator.check(q, policy).isEmpty ? q : nil
    }

    /// The one free-written line: short, no painful retelling, passing the output rules.
    public static func checkedSummary(_ value: String, text: String, quietTopics: [String] = []) -> String? {
        let s = value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”"))
        guard !isNone(s), s.count <= 150, s.split(whereSeparator: \.isWhitespace).count <= 24 || ListenRules.isCJK(s) else { return nil }
        let lower = s.lowercased()
        // One feeling word is fine ("You're anxious about tomorrow"); two or more reads as a retelling.
        guard KeepOrRelease.hardNarrative.filter({ lower.contains($0) }).count < 2 else { return nil }
        guard !SafetyCheck.mentionsSelfHarm(s) else { return nil }
        let policy = OutputPolicy(input: text, userText: text, quietTopics: quietTopics, maxCharacters: 150)
        return OutputValidator.check(s, policy).isEmpty ? s : nil
    }

    // MARK: Rule-based notes (no model)

    static let thoughtCues = ["i thought", "i think", "i kept thinking", "i keep thinking", "what if", "why do i", "why does",
                              "i'm such", "i am such", "i always", "i never", "everyone", "nobody cares", "i can't believe",
                              "と思った", "思って"]
    static let urgeCues = ["i wanted to", "i just wanted", "i want to", "i walked away", "i left", "i hid", "i stayed in",
                           "i snapped", "i shut down", "i went to bed", "i ran", "したかった", "逃げ"]
    static let bodyCues = ["chest", "stomach", "throat", "shaking", "shaky", "heart was", "heart racing", "headache", "tight",
                           "tense", "couldn't breathe", "nauseous", "胸", "お腹", "頭痛", "震え"]

    /// Notes from rules alone. Only ever copies her words or picks from the fixed lists.
    public static func fallback(text: String, keptLines: [String], sensations: [String] = [], quietTopics: [String] = []) -> ReleaseNote {
        var note = ReleaseNote()
        let lower = text.lowercased()
        let sentences = KeepOrRelease.sentences(text)
        let topics = quietTopics.map { $0.lowercased() }.filter { !$0.isEmpty }
        func usable(_ s: String) -> Bool { !topics.contains(where: s.lowercased().contains) }
        func quote(for cues: [String]) -> String? {
            sentences.first { s in usable(s) && cues.contains(where: s.lowercased().contains) }.map(short)
        }

        note.feelings = Array(NoteFeeling.allCases.filter { f in f.cues.contains(where: lower.contains) }.prefix(3))
        note.thought = quote(for: thoughtCues)
        note.urge = quote(for: urgeCues)
        note.body = quote(for: bodyCues)
        if note.body == nil, !sensations.isEmpty { note.body = sensations.prefix(3).joined(separator: ", ") }

        let hits = Set(KeepOrRelease.hardNarrative.filter { lower.contains($0) }).count
        if hits > 0, let q = sentences.max(by: { hardness($0) < hardness($1) }), hardness(q) > 0, usable(q) {
            note.intensity = hits >= 4 ? .veryStrong : hits >= 2 ? .strong : .mild
            note.intensityQuote = short(q)
        }

        var needs: [NeedNote] = []
        for need in CoreNeed.allCases {
            if let q = quote(for: need.missingCues) { needs.append(NeedNote(need: need, met: false, quote: q)) }
            else if let q = quote(for: need.metCues) { needs.append(NeedNote(need: need, met: true, quote: q)) }
        }
        // Missing needs first: they are the useful part of the note.
        note.needs = Array((needs.filter { !$0.met } + needs.filter(\.met)).prefix(maxNeeds))
        // Only lines that say something helped; "I need" lines are not what helped.
        note.helped = keptLines.filter { usable($0) && KeepOrRelease.tag($0) == "helped" }
        return note
    }

    static func hardness(_ s: String) -> Int {
        let l = s.lowercased()
        return KeepOrRelease.hardNarrative.filter { l.contains($0) }.count
    }

    static func short(_ s: String) -> String {
        let words = s.split(whereSeparator: \.isWhitespace)
        guard words.count > maxQuoteWords else { return s }
        return words.prefix(maxQuoteWords).joined(separator: " ") + "…"
    }

    /// Model notes first, rules filling any part the model left empty.
    public static func merged(model: ReleaseNote, rules: ReleaseNote) -> ReleaseNote {
        var n = model
        n.byModel = true
        if n.thought == nil { n.thought = rules.thought }
        if n.feelings.isEmpty { n.feelings = rules.feelings }
        if n.body == nil { n.body = rules.body }
        if n.urge == nil { n.urge = rules.urge }
        if n.intensity == nil { n.intensity = rules.intensity; n.intensityQuote = rules.intensityQuote }
        if n.needs.isEmpty { n.needs = rules.needs }
        for h in rules.helped where !n.helped.contains(h) { n.helped.append(h) }
        return n
    }

    /// Worth writing notes for a kept entry (owner, 2026-11-04: "where is the AI doing its job"):
    /// a real piece of writing (25+ words, or 75+ Japanese/Chinese characters), or a shorter one that
    /// tells a hard story.
    public static func worthWriting(_ text: String?) -> Bool {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        if MoodGuess.wordCount(t) >= 25 || MoodGuess.cjkCount(t) >= 75 { return true }
        let lower = t.lowercased()
        return MoodGuess.wordCount(t) >= 8 && KeepOrRelease.hardNarrative.contains(where: lower.contains)
    }

    /// Her mood point in words, from her own tap (not the model). Nil when she did not tap one.
    public static func moodPointLine(valence: Double?, arousal: Double?) -> String? {
        guard let v = valence else { return nil }
        let pleasant = v <= -0.6 ? "Very unpleasant" : v <= -0.2 ? "Unpleasant" : v < 0.2 ? "In between" : "Pleasant"
        guard let a = arousal else { return pleasant }
        let energy = a >= 0.35 ? "stirred up" : a <= -0.35 ? "low energy" : "middle energy"
        return "\(pleasant), \(energy)"
    }
}

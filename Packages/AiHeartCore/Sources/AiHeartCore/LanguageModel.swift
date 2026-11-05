import CoreGraphics
import Foundation

// The on-device language model (M8, docs/03). Behind a protocol so it can be swapped.
// Statistics are computed in code; the model only words things. Every output is checked
// before she sees it, and regenerated or dropped if it fails.

public struct GenerationRequest: Sendable {
    public var system: String
    public var prompt: String
    public var image: CGImage?
    public var maxTokens: Int
    public var temperature: Float
    /// Only her own text in this request (entry text, talk turns, her question), for the self-harm gate
    /// before any cloud call. Never the About me block or app text. nil = not declared: the cloud refuses.
    /// "" = she wrote nothing in this request (for example facts computed from numbers).
    public var ownText: String?

    public init(system: String, prompt: String, image: CGImage? = nil, maxTokens: Int = 80, temperature: Float = 0.3,
                ownText: String? = nil) {
        self.system = system; self.prompt = prompt; self.image = image
        self.maxTokens = maxTokens; self.temperature = temperature; self.ownText = ownText
    }
}

/// Which part of the app is asking. Only the features on the allow-list may use the cloud model
/// (owner, 2026-11-05); photos and media captions stay on the phone, and so does anything not listed.
public enum LLMFeature: String, Sendable, CaseIterable {
    // May use the cloud model when her switch is on.
    case notes, talk, outlook, tone, words, aboutMe, decide, listen
    // On the phone only.
    case photo, media, other

    public var mayUseCloud: Bool {
        switch self {
        case .notes, .talk, .outlook, .tone, .words, .aboutMe, .decide, .listen: true
        case .photo, .media, .other: false
        }
    }
}

/// Raised when a request may not go to the cloud and there is no on-device model to take it.
public struct CloudRefusal: Error, Equatable, Sendable {
    public init() {}
}

/// The check before every cloud call (CLAUDE.md #2, #8): her own text must not mention self-harm.
/// On the phone, fixed words, no model. A request with a photo, or with no declared own text, is refused.
public enum CloudGate {
    public static func blocks(_ ownText: String) -> Bool {
        SafetyCheck.mentionsSelfHarm(ownText) || ListenSafety.flags(ownText)
    }

    public static func allows(_ request: GenerationRequest) -> Bool {
        guard request.image == nil, let own = request.ownText else { return false }
        return !blocks(own)
    }
}

/// The cloud model with a gate in front. A request that fails the gate goes to the on-device model
/// instead (or fails with `CloudRefusal` when there is none). A cloud error is not hidden: it is thrown.
public struct GatedCloudModel: LanguageModel {
    public let cloud: any LanguageModel
    public let local: (any LanguageModel)?
    public init(cloud: any LanguageModel, local: (any LanguageModel)?) { self.cloud = cloud; self.local = local }
    public var name: String { cloud.name }
    public var canSeeImages: Bool { local?.canSeeImages ?? false }

    public func generate(_ request: GenerationRequest) async throws -> String {
        if CloudGate.allows(request) { return try await cloud.generate(request) }
        guard let local else { throw CloudRefusal() }
        return try await local.generate(request)
    }
}

public protocol LanguageModel: Sendable {
    var name: String { get }
    var canSeeImages: Bool { get }
    func generate(_ request: GenerationRequest) async throws -> String
}

/// What an output is checked against.
public struct OutputPolicy: Sendable {
    /// Everything the model was given, so any number in the output must appear here.
    public var input: String
    /// Her own words. A banned term is allowed only if she wrote it first.
    public var userText: String
    public var quietTopics: [String]
    public var maxCharacters: Int

    public init(input: String, userText: String = "", quietTopics: [String] = [], maxCharacters: Int = 600) {
        self.input = input; self.userText = userText; self.quietTopics = quietTopics; self.maxCharacters = maxCharacters
    }
}

public enum Violation: Equatable, Sendable {
    case numberNotInInput(String)
    case label(String)
    case advice(String)
    case reassurance(String)
    case quietTopic(String)
    case tooLong
    case empty
}

public enum OutputValidator {
    /// Labels never used unless she wrote them herself (CLAUDE.md #3, docs/03).
    static let labels = ["mania", "manic", "hypomania", "hypomanic", "bipolar", "psychosis", "psychotic",
                         "depressive episode", "depressed episode", "major depression", "disorder", "diagnosis", "diagnose",
                         "躁", "うつ病", "障害"]
    /// Advice and dose talk. Never, unless she asks, and even then never dose.
    static let advice = ["you should", "you need to", "try to ", "make sure", "i recommend", "i suggest", "it might help to",
                         "consider taking", "increase your dose", "lower your dose", "reduce your dose", "take more", "take less",
                         "stop taking", "see a doctor about your dose", "change your medication"]
    static let reassurance = ["don't worry", "do not worry", "it's okay", "it is okay", "you'll be fine", "you will be fine",
                              "everything will be", "be kind to yourself", "you've got this", "proud of you", "it's normal to feel"]

    public static func check(_ output: String, _ policy: OutputPolicy) -> [Violation] {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [.empty] }
        var out: [Violation] = []
        if text.count > policy.maxCharacters { out.append(.tooLong) }
        let lower = text.lowercased(), user = policy.userText.lowercased()
        for t in labels where lower.contains(t) && !user.contains(t) { out.append(.label(t)) }
        for t in advice where lower.contains(t) { out.append(.advice(t)) }
        for t in reassurance where lower.contains(t) { out.append(.reassurance(t)) }
        for q in policy.quietTopics where !q.isEmpty && lower.contains(q.lowercased()) { out.append(.quietTopic(q)) }
        let inputNumbers = Set(numbers(in: policy.input))
        for n in numbers(in: text) where !inputNumbers.contains(n) { out.append(.numberNotInInput(n)) }
        return out
    }

    /// Numbers as written, normalised ("1,5" -> "1.5", "06" -> "6").
    static func numbers(in s: String) -> [String] {
        let t = s.replacingOccurrences(of: "(\\d),(\\d)", with: "$1.$2", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: "\\d+(?:\\.\\d+)?") else { return [] }
        return re.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { m in
            Range(m.range, in: t).map { String(t[$0]) }.map { v in
                Double(v).map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? v
            }
        }
    }

    /// Why the last generation was dropped (no content, for diagnostics).
    nonisolated(unsafe) public static var lastFailure: String?

    /// Runs the model up to `attempts` times and returns the first output that passes.
    /// Returns nil rather than show something that fails.
    public static func generate(_ model: any LanguageModel, _ request: GenerationRequest, policy: OutputPolicy,
                                attempts: Int = 3, accept: (String) -> String? = { $0 }) async -> String? {
        for i in 0..<attempts {
            var r = request
            if i > 0 { r.temperature = min(1, request.temperature + 0.2 * Float(i)) }
            let raw: String
            do { raw = try await model.generate(r) } catch { lastFailure = "error"; continue }
            guard let candidate = accept(raw) else { lastFailure = "unparsable"; continue }
            let v = check(candidate, policy)
            if v.isEmpty { lastFailure = nil; return candidate }
            lastFailure = "checks: \(v.count)"
        }
        return nil
    }
}

/// Feeling words: for a photo, and "help me find the words". Short, balanced, never labels.
public enum WordTasks {
    public static let system = """
    You help a person name how a moment feels. Offer plain, everyday feeling words. \
    Never diagnose, never label a state, never give advice, never reassure. \
    Reply with the words only, separated by commas.
    """

    /// Tone of an entry for coloring only. Two numbers, nothing else.
    public static func tonePrompt(text: String?) -> String {
        let body = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let what = body.isEmpty ? "the photo" : "this journal entry:\n\"\"\"\n\(String(body.prefix(1200)))\n\"\"\""
        return "Rate the feeling of \(what)\nAnswer with exactly two numbers, nothing else, in this form:\npleasant=<number from -1 to 1> energy=<number from -1 to 1>"
    }

    /// Parses "pleasant=0.6 energy=-0.2" (lenient about spacing and order).
    public static func parseTone(_ raw: String) -> (valence: Double, arousal: Double)? {
        func grab(_ key: String) -> Double? {
            guard let r = raw.range(of: "\(key)\\s*[=:]\\s*(-?\\d+(?:\\.\\d+)?)", options: [.regularExpression, .caseInsensitive]) else { return nil }
            let num = raw[r].split(whereSeparator: { $0 == "=" || $0 == ":" }).last.map { $0.trimmingCharacters(in: .whitespaces) }
            return num.flatMap(Double.init)
        }
        guard let v = grab("pleasant"), let a = grab("energy") else { return nil }
        return (max(-1, min(1, v)), max(-1, min(1, a)))
    }

    public static func photoPrompt() -> String {
        "Look at this photo. Offer three different single words for how this moment might feel, including at least one calm or pleasant word. Words only, separated by commas."
    }

    /// One short caption for the vibe of a photo (owner's choice, 2026-10-31).
    public static func vibePrompt() -> String {
        "Give this photo a short caption of two to five words that captures its vibe, like A quiet evening or Slow sunny morning. Reply with the caption only."
    }

    /// First line, quotes and trailing punctuation removed; one to six words, else nil.
    public static func parseVibe(_ raw: String) -> String? {
        guard var line = raw.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        line = line.replacingOccurrences(of: "^(caption\\s*:\\s*)", with: "", options: [.regularExpression, .caseInsensitive])
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”*_.!,;: "))
        let n = line.split(separator: " ").count
        guard (1...6).contains(n), line.count <= 48 else { return nil }
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// One call for both: a short neutral caption, then three feeling words.
    public static func photoCaptionPrompt() -> String {
        "Look at this photo. Line 1: a short caption of at most eight words that plainly describes what is in the photo, without guessing feelings. Line 2: three different single words for how this moment might feel, including at least one calm or pleasant word, separated by commas."
    }

    /// Parses the two-line reply. The caption must be short and plain; words as before.
    public static func parsePhoto(_ raw: String) -> (caption: String?, words: [String]) {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "^(line\\s*\\d\\s*[:.-]|caption\\s*:|words?\\s*:|[-*•\\d.)\\s])+", with: "", options: [.regularExpression, .caseInsensitive])
                     .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return (nil, []) }
        var caption: String? = lines[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
        if let c = caption, c.split(separator: " ").count > 10 || c.contains(",") && c.split(separator: ",").count >= 3 { caption = nil }
        let wordLine = lines.count > 1 ? lines[1...].joined(separator: ", ") : (caption == nil ? lines[0] : "")
        return (caption, parseWords(wordLine, limit: 3))
    }

    public static func findWordsPrompt(draft: String, vocabulary: [String]) -> String {
        let vocab = vocabulary.isEmpty ? "" : "Words she has used before: \(vocabulary.joined(separator: ", ")). Prefer these when they fit.\n"
        return "\(vocab)What she wrote: \"\(draft)\"\nOffer up to five single feeling words that might fit what she wrote, with at least one opposite or gentler word. Words only, separated by commas."
    }

    /// Parses "Calm, tired, 3. Hopeful" into ["Calm", "Tired", "Hopeful"]. Single words or
    /// two-word phrases only; drops anything that looks like a sentence.
    public static func parseWords(_ raw: String, limit: Int) -> [String] {
        let pieces = raw.components(separatedBy: CharacterSet(charactersIn: ",\n;、・/"))
        var out: [String] = []
        for p in pieces {
            var w = p.trimmingCharacters(in: .whitespacesAndNewlines)
            w = w.replacingOccurrences(of: "^[-*•\\d.)\\s]+", with: "", options: .regularExpression)
            w = w.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            guard !w.isEmpty, w.split(separator: " ").count <= 2, w.count <= 24 else { continue }
            let word = w.prefix(1).uppercased() + w.dropFirst().lowercased()
            if !out.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) { out.append(word) }
            if out.count == limit { break }
        }
        return out
    }

    /// Without the model: her own most-used words first, then the balanced static set.
    public static func fallbackWords(vocabulary: [String], limit: Int = 5) -> [String] {
        var out: [String] = []
        for w in vocabulary + MoodWords.staticSuggestions + MoodWords.more where !out.contains(w) {
            out.append(w)
            if out.count == limit { break }
        }
        return out
    }

    /// Her words, most used first.
    public static func vocabulary(from words: [String], limit: Int = 20) -> [String] {
        var counts: [String: Int] = [:]
        for w in words { counts[w, default: 0] += 1 }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }
}

/// Stand-in used when the model is not on the device (or in the simulator). It never
/// pretends to see an image.
public struct RuleBasedModel: LanguageModel {
    public init() {}
    public var name: String { "Built-in rules" }
    public var canSeeImages: Bool { false }
    public func generate(_ request: GenerationRequest) async throws -> String {
        throw NSError(domain: "AiHeart", code: 1, userInfo: [NSLocalizedDescriptionKey: "No language model on this device"])
    }
}

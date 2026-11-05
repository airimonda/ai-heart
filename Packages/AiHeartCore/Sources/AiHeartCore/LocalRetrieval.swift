import Foundation
import NaturalLanguage

// Local retrieval for "Talk it through" (docs/21). Her kept entries and saved notes are chunked,
// indexed and searched on the phone. Nothing here touches the network. Only the few snippets the
// caller chooses to pass on leave the phone, redacted, with the conversation.
//
// Never indexed: released entries, entries about self-harm, sample (demo) rows, and any chunk that
// mentions a quiet topic.

/// One passage of her own writing that can be retrieved.
public struct RetrievalDocument: Identifiable, Equatable, Sendable {
    public var id: String
    public var entryId: UUID
    public var date: Date
    public var text: String
    /// True when made from the notes of an entry rather than from its text.
    public var fromNote: Bool
    /// True when made from her own words in an earlier conversation (the mirror memory).
    public var fromTalk: Bool = false

    public init(id: String, entryId: UUID, date: Date, text: String, fromNote: Bool = false, fromTalk: Bool = false) {
        self.id = id; self.entryId = entryId; self.date = date; self.text = text; self.fromNote = fromNote; self.fromTalk = fromTalk
    }
}

/// A retrieved passage, as shown in a chip and sent (redacted) with the conversation.
public struct Snippet: Identifiable, Equatable, Sendable {
    public var id: String
    public var entryId: UUID
    public var date: Date
    public var text: String
    public var score: Double
    public var fromTalk: Bool = false

    public init(id: String, entryId: UUID, date: Date, text: String, score: Double = 0, fromTalk: Bool = false) {
        self.id = id; self.entryId = entryId; self.date = date; self.text = text; self.score = score; self.fromTalk = fromTalk
    }
}

/// A sentence embedding and the language it was made in. Vectors from different languages are
/// never compared.
public struct TextEmbedding: Sendable {
    public var language: String
    public var vector: [Double]
    public init(language: String, vector: [Double]) { self.language = language; self.vector = vector }
}

/// Injectable so tests use a fake. nil means "no embedding for this text".
public protocol SentenceEmbedder: Sendable {
    func embed(_ text: String) -> TextEmbedding?
}

/// Apple's on-device sentence embedding, in the language detected from the text. Not available for
/// every language (for example Japanese and Tagalog): then the lexical score alone is used.
public struct NLSentenceEmbedder: SentenceEmbedder {
    public init() {}

    public func embed(_ text: String) -> TextEmbedding? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english
        guard let model = NLEmbedding.sentenceEmbedding(for: language), let v = model.vector(for: text), !v.isEmpty else { return nil }
        return TextEmbedding(language: language.rawValue, vector: v)
    }
}

public enum LocalRetrieval {
    public static let chunkSentences = 3
    public static let maxSnippetCharacters = 400

    // MARK: Documents

    /// Everything that may be retrieved. Pure: no model context, no network.
    public static func documents(from entries: [Entry], quietTopics: [String]) -> [RetrievalDocument] {
        let topics = quietTopics.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        func quiet(_ s: String) -> Bool { let l = s.lowercased(); return topics.contains { l.contains($0) } }

        var out: [RetrievalDocument] = []
        for e in entries {
            guard e.status != .released, e.deviceId != BackupArchive.demoDeviceId, !SafetyCheck.mentionsSelfHarm(e) else { continue }
            if e.status == .kept, let text = e.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sentences = text.components(separatedBy: .newlines).flatMap(KeepOrRelease.sentences)
                for (i, chunk) in chunks(sentences).enumerated() where !quiet(chunk) {
                    out.append(RetrievalDocument(id: "\(e.syncId.uuidString)-t\(i)", entryId: e.syncId, date: e.createdAt, text: chunk))
                }
            }
            if let note = e.releaseNote {
                var lines: [String] = []
                if let h = note.happened?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty { lines.append(h) }
                for part in NotePart.shown { lines += note.sentences(part) }
                let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty, !quiet(joined) {
                    out.append(RetrievalDocument(id: "\(e.syncId.uuidString)-n", entryId: e.syncId, date: e.createdAt, text: joined, fromNote: true))
                }
            }
        }
        return out
    }

    /// Her own words from earlier conversations, for the mirror memory. Same exclusions as entries.
    public static func documents(fromTalks talks: [TalkMemory], quietTopics: [String]) -> [RetrievalDocument] {
        let topics = quietTopics.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        var out: [RetrievalDocument] = []
        for t in talks where t.deviceId != BackupArchive.demoDeviceId {
            let sentences = t.text.components(separatedBy: .newlines).flatMap(KeepOrRelease.sentences)
            for (i, chunk) in chunks(sentences).enumerated() {
                let l = chunk.lowercased()
                guard !topics.contains(where: l.contains), !SafetyCheck.mentionsSelfHarm(chunk) else { continue }
                out.append(RetrievalDocument(id: "\(t.syncId.uuidString)-k\(i)", entryId: t.syncId, date: t.date, text: chunk, fromTalk: true))
            }
        }
        return out
    }

    /// Chunks of about three sentences. A lone last sentence joins the chunk before it.
    static func chunks(_ sentences: [String]) -> [String] {
        guard !sentences.isEmpty else { return [] }
        var groups: [[String]] = stride(from: 0, to: sentences.count, by: chunkSentences).map {
            Array(sentences[$0..<min($0 + chunkSentences, sentences.count)])
        }
        if groups.count > 1, groups[groups.count - 1].count == 1 {
            let last = groups.removeLast()
            groups[groups.count - 1] += last
        }
        return groups.map { $0.joined(separator: " ") }
    }

    // MARK: Index

    /// Built once per conversation (embedding every chunk takes a moment: build it off the main
    /// actor), then searched for each message.
    public final class Index: @unchecked Sendable {
        let documents: [RetrievalDocument]
        let embedder: SentenceEmbedder?
        private let vectors: [TextEmbedding?]
        private let tokens: [[String]]
        private let docFrequency: [String: Int]
        private let averageLength: Double

        public init(documents: [RetrievalDocument], embedder: SentenceEmbedder? = NLSentenceEmbedder()) {
            self.documents = documents
            self.embedder = embedder
            self.vectors = documents.map { embedder?.embed($0.text) }
            let toks = documents.map { LocalRetrieval.tokens($0.text) }
            self.tokens = toks
            var df: [String: Int] = [:]
            for t in toks { for w in Set(t) { df[w, default: 0] += 1 } }
            self.docFrequency = df
            self.averageLength = toks.isEmpty ? 1 : max(1, Double(toks.reduce(0) { $0 + $1.count }) / Double(toks.count))
        }

        public var isEmpty: Bool { documents.isEmpty }

        /// The best passages for what she just said. At most one per entry, none of `excluding`
        /// (snippet ids she removed), none below the minimum score. Talk memories fade with age: their rank
        /// is the score times `MemoryRecency.weight`, but the bar is applied to the score alone, so an old
        /// memory ranks lower and is never dropped for its age.
        public func search(_ query: String, k: Int = 4, excluding: Set<String> = [], minimum: Double? = nil,
                           now: Date = Date()) -> [Snippet] {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, !documents.isEmpty, k > 0 else { return [] }
            let queryVector = embedder?.embed(q)
            let queryTerms = Array(Set(LocalRetrieval.tokens(q)))
            let n = Double(documents.count)

            func idf(_ term: String) -> Double {
                let df = Double(docFrequency[term] ?? 0)
                return log(1 + (n - df + 0.5) / (df + 0.5))
            }
            // The most a query can score: its heaviest terms at full strength.
            let k1 = 1.2, b = 0.75
            let ceiling = queryTerms.map(idf).sorted(by: >).prefix(8).reduce(0, +) * (k1 + 1)

            var scored: [(RetrievalDocument, Double)] = []
            for (i, doc) in documents.enumerated() where !excluding.contains(doc.id) {
                var lexical = 0.0
                if ceiling > 0 {
                    let words = tokens[i]
                    var counts: [String: Int] = [:]
                    for w in words { counts[w, default: 0] += 1 }
                    var raw = 0.0
                    for term in queryTerms {
                        guard let tf = counts[term].map(Double.init) else { continue }
                        raw += idf(term) * tf * (k1 + 1) / (tf + k1 * (1 - b + b * Double(words.count) / averageLength))
                    }
                    lexical = min(1, raw / ceiling)
                }
                var semantic: Double?
                if let qv = queryVector, let dv = vectors[i], qv.language == dv.language,
                   let c = LocalRetrieval.cosine(qv.vector, dv.vector) {
                    semantic = max(0, min(1, (c - 0.2) / 0.6))
                }
                let score = semantic.map { 0.65 * $0 + 0.35 * lexical } ?? lexical
                // Embeddings run together and apart from words alone: each has its own bar.
                let bar = minimum ?? (semantic == nil ? LocalRetrieval.minimumLexical : LocalRetrieval.minimumHybrid)
                if score >= bar { scored.append((doc, doc.fromTalk ? score * MemoryRecency.weight(of: doc.date, now: now) : score)) }
            }
            scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.date > $1.0.date }

            var seen = Set<UUID>()
            var out: [Snippet] = []
            for (doc, score) in scored where seen.insert(doc.entryId).inserted {
                out.append(Snippet(id: doc.id, entryId: doc.entryId, date: doc.date,
                                   text: String(doc.text.prefix(LocalRetrieval.maxSnippetCharacters)), score: score, fromTalk: doc.fromTalk))
                if out.count == k { break }
            }
            return out
        }
    }

    /// Bars for a passage to count as related (0 to 1 scales; see `Index.search`).
    static let minimumHybrid = 0.25
    static let minimumLexical = 0.12

    // MARK: Scoring parts

    static func cosine(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot = 0.0, x = 0.0, y = 0.0
        for i in 0..<a.count { dot += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i] }
        let d = x.squareRoot() * y.squareRoot()
        return d > 0 ? dot / d : nil
    }

    static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "was", "were", "are", "but", "not", "you", "your", "have", "had", "has", "from",
        "they", "them", "then", "than", "what", "when", "where", "which", "who", "how", "why", "can", "could", "would", "should",
        "just", "like", "about", "into", "over", "out", "all", "any", "one", "too", "very", "its", "it's", "i'm", "i've", "i'd", "i'll",
        "she", "her", "his", "him", "she's", "he", "me", "my", "mine", "our", "we", "us", "is", "am", "be", "been", "being", "do", "did",
        "does", "done", "to", "of", "in", "on", "at", "as", "an", "or", "so", "if", "it", "up", "no", "by", "got", "get", "feel", "felt",
        "ang", "ng", "sa", "na", "ako", "ko", "mo", "ay", "at", "po", "ito", "yung", "mga", "ba", "pa", "din", "rin",
    ]

    /// Word tokens, lower case, without filler words. Works for languages with no spaces (Japanese).
    static func tokens(_ text: String) -> [String] {
        let t = NLTokenizer(unit: .word)
        t.string = text
        var out: [String] = []
        t.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = String(text[range]).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            guard w.contains(where: { $0.isLetter || $0.isNumber }) else { return true }
            if w.allSatisfy(\.isASCII), w.count < 2 { return true }
            if !stopWords.contains(w) { out.append(w) }
            return true
        }
        return out
    }
}

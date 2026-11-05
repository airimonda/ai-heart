import Foundation
import NaturalLanguage

/// Removes personal identifiers before text goes to the cloud model (owner, 2026-11-04: "remove PII
/// before cloud uploads"; docs/20). Runs on the phone. Each identifier becomes a stable placeholder
/// such as [PERSON_1]; the reply is mapped back on the phone before she sees it.
///
/// Covers: names of people, places and organisations (Apple's on-device NLTagger; strongest in
/// English), emails, phone numbers, links, @handles, long digit runs (IDs, card or account numbers),
/// and any extra terms she lists. Dates, ages and amounts stay: they carry meaning and do not identify
/// her on their own.
public struct PIIRedaction: Sendable, Equatable {
    public let text: String
    /// Placeholder -> original.
    public let map: [String: String]

    public init(text: String, map: [String: String]) {
        self.text = text; self.map = map
    }

    public func restore(_ s: String) -> String {
        // Longest placeholders first so [PERSON_12] is not hit by [PERSON_1].
        map.keys.sorted { $0.count > $1.count }.reduce(s) { $0.replacingOccurrences(of: $1, with: map[$1] ?? $1) }
    }
}

public enum PIIRedactor {
    static let patterns: [(String, String)] = [
        ("EMAIL", #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
        ("LINK", #"(?i)\b(?:https?://|www\.)[^\s<>"]+"#),
        ("HANDLE", #"(?<![\w@])@[A-Za-z0-9_.]{2,}"#),
        ("PHONE", #"(?<!\w)\+?\d[\d\s\-().]{7,}\d(?!\w)"#),
        ("NUMBER", #"\b\d{6,}\b"#),
    ]

    /// Redacts with consistent placeholders across several texts (system and user parts of one request).
    public static func redact(_ texts: [String], extraTerms: [String] = []) -> (texts: [String], map: [String: String]) {
        var map: [String: String] = [:]
        var reverse: [String: String] = [:]
        var counters: [String: Int] = [:]
        func placeholder(_ kind: String, _ original: String) -> String {
            let key = kind + "|" + original.lowercased()
            if let p = reverse[key] { return p }
            counters[kind, default: 0] += 1
            let p = "[\(kind)_\(counters[kind]!)]"
            reverse[key] = p
            map[p] = original
            return p
        }
        var out: [String] = []
        for var t in texts {
            for (kind, rx) in patterns {
                guard let re = try? NSRegularExpression(pattern: rx) else { continue }
                let matches = re.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed()
                for m in matches {
                    guard let r = Range(m.range, in: t) else { continue }
                    let original = String(t[r])
                    // A phone pattern can catch a date range like 2024-2025; skip short ones with no space or plus.
                    if kind == "PHONE", original.filter(\.isNumber).count < 9 { continue }
                    t.replaceSubrange(r, with: placeholder(kind, original))
                }
            }
            for term in extraTerms.map({ $0.trimmingCharacters(in: .whitespaces) }) where term.count >= 2 {
                while let r = t.range(of: term, options: [.caseInsensitive]) {
                    t.replaceSubrange(r, with: placeholder("NAME", String(t[r])))
                }
            }
            t = redactNames(t, placeholder)
            out.append(t)
        }
        return (out, map)
    }

    public static func redact(_ text: String, extraTerms: [String] = []) -> PIIRedaction {
        let r = redact([text], extraTerms: extraTerms)
        return PIIRedaction(text: r.texts[0], map: r.map)
    }

    /// Words NLTagger sometimes tags as names that are not identifying.
    static let notNames: Set<String> = ["mama", "mom", "mum", "dad", "papa", "god", "lord", "i", "monday", "tuesday", "wednesday",
                                        "thursday", "friday", "saturday", "sunday"]

    static func redactNames(_ text: String, _ placeholder: (String, String) -> String) -> String {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var hits: [(Range<String.Index>, String)] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, r in
            let kind: String? = switch tag {
            case .personalName: "PERSON"
            case .placeName: "PLACE"
            case .organizationName: "ORG"
            default: nil
            }
            let word = String(text[r])
            if let kind, !word.hasPrefix("["), !notNames.contains(word.lowercased()) { hits.append((r, kind)) }
            return true
        }
        var t = text
        for (r, kind) in hits.reversed() { t.replaceSubrange(r, with: placeholder(kind, String(text[r]))) }
        return t
    }
}

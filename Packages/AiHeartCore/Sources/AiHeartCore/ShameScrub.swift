import Foundation

/// "Scrub the thing of embarrassing details and focus on what's important" (owner, 2026-11-04).
/// Whole sentences are dropped, never reworded: the model (or, without it, her shame words) marks the
/// sentences that carry the embarrassing details; she reviews the marks and keeps the rest. Sentences
/// about how she feels, what she needed, learned or wants are kept. A dropped sentence can be replaced
/// by her own typed words; the model never writes a replacement (owner, 2026-11-05).
public enum ShameScrub {
    public static let system = "You help a person keep a journal entry without its embarrassing details. Answer with sentence numbers only."

    public static func prompt(_ sentences: [String]) -> String {
        "Her entry, one sentence per line:\n" + sentences.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            + "\n\nWhich sentences hold the embarrassing or shameful details: exactly what happened, or what she said or did "
            + "that she is embarrassed about? Do not pick sentences about how she feels, what she needed, what she learned or "
            + "what she wants. Answer with the numbers, comma separated, or none."
    }

    /// Sentence indexes to drop, from the model's answer.
    public static func parse(_ raw: String, count: Int) -> Set<Int> {
        guard !raw.lowercased().contains("none") else { return [] }
        let nums = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        return Set(nums.filter { (1...count).contains($0) }.map { $0 - 1 })
    }

    /// Without the model: sentences with her shame words, but never one that says how she feels or what she wants.
    public static func fallback(_ sentences: [String]) -> Set<Int> {
        Set(sentences.indices.filter { i in
            let s = sentences[i]
            let l = s.lowercased()
            let keeps = KeepOrRelease.keepCues.contains { $0.1.contains(where: l.contains) }
            return KeepOrRelease.shameHits(s) > 0 && !keeps
        })
    }

    /// What is left, in her order. A dropped sentence is replaced by her own words when she typed some.
    /// Never empty: if everything was dropped and nothing typed, nothing is dropped.
    public static func kept(_ sentences: [String], dropping: Set<Int>, replacing: [Int: String] = [:]) -> String {
        let left: [String] = sentences.indices.compactMap { i in
            guard dropping.contains(i) else { return sentences[i] }
            let own = replacing[i]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return own.isEmpty ? nil : own
        }
        return (left.isEmpty ? sentences : left).joined(separator: " ")
    }
}


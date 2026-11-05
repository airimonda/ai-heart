import Foundation

/// When her writing is long enough, the on-device model may guess the mood point so she does
/// not have to tap one (docs/19). Counts words, and characters for Japanese and Chinese, which
/// have no spaces between words.
public enum MoodGuess {
    public static let minWords = 40
    public static let minCJKCharacters = 120
    /// Entries saved before this are never given a guessed mood point (no backfill).
    public static let startedAt = Date(timeIntervalSince1970: 1_793_750_400) // 2026-11-04 00:00 UTC

    /// True for kana, kanji and halfwidth katakana. Punctuation blocks are not counted.
    static func isCJK(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x309F, 0x30A0...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F: true
        default: false
        }
    }

    /// Words separated by spaces, not counting CJK characters.
    public static func wordCount(_ text: String) -> Int {
        var spaced = String.UnicodeScalarView()
        for s in text.unicodeScalars { spaced.append(isCJK(s) ? " " : s) }
        return String(spaced)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
    }

    public static func cjkCount(_ text: String) -> Int {
        text.unicodeScalars.filter(isCJK).count
    }

    /// Long enough to guess from: 40 or more words, or 120 or more Japanese or Chinese characters.
    public static func isLong(_ text: String?) -> Bool {
        guard let text else { return false }
        return wordCount(text) >= minWords || cjkCount(text) >= minCJKCharacters
    }

    /// Guess only when she wrote a lot and did not place a mood point herself.
    public static func shouldGuess(text: String?, valence: Double?) -> Bool {
        valence == nil && isLong(text)
    }

    /// Plain words for a point, e.g. "pleasant, still". Describes; never labels a state.
    public static func describe(valence: Double, arousal: Double) -> String {
        let v = valence > 0.15 ? "pleasant" : valence < -0.15 ? "unpleasant" : "neither pleasant nor unpleasant"
        let a = arousal > 0.15 ? "stirred" : arousal < -0.15 ? "still" : "neither still nor stirred"
        return "\(v), \(a)"
    }
}

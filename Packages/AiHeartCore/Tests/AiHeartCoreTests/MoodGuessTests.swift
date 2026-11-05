import Foundation
import Testing
@testable import AiHeartCore

// Synthetic text only.

@Suite struct MoodGuessTests {
    private func words(_ n: Int) -> String { Array(repeating: "word", count: n).joined(separator: " ") }

    @Test func countsEnglishWords() {
        #expect(MoodGuess.wordCount("one two  three\nfour") == 4)
        #expect(MoodGuess.wordCount("") == 0)
        #expect(MoodGuess.wordCount("... -- !!") == 0)
    }

    @Test func fortyWordsIsLong() {
        #expect(!MoodGuess.isLong(words(39)))
        #expect(MoodGuess.isLong(words(40)))
        #expect(!MoodGuess.isLong(nil))
    }

    @Test func japaneseCountsCharacters() {
        let ja119 = String(repeating: "あ", count: 119)
        let ja120 = String(repeating: "あ", count: 120)
        #expect(MoodGuess.wordCount(ja120) == 0)
        #expect(MoodGuess.cjkCount(ja120) == 120)
        #expect(!MoodGuess.isLong(ja119))
        #expect(MoodGuess.isLong(ja120))
        // Punctuation does not count.
        #expect(MoodGuess.cjkCount("今日は、よかった。") == 7)
    }

    @Test func mixedTextCountsEnglishPartsAsWords() {
        #expect(MoodGuess.wordCount("今日は work がとても long でした") == 2)
    }

    @Test func shouldGuessNeedsLongTextAndNoValence() {
        #expect(MoodGuess.shouldGuess(text: words(50), valence: nil))
        #expect(!MoodGuess.shouldGuess(text: words(50), valence: 0.2))
        #expect(!MoodGuess.shouldGuess(text: words(10), valence: nil))
        #expect(!MoodGuess.shouldGuess(text: nil, valence: nil))
        #expect(MoodGuess.shouldGuess(text: String(repeating: "あ", count: 130), valence: nil))
    }

    @Test func describesPoint() {
        #expect(MoodGuess.describe(valence: 0.5, arousal: -0.5) == "pleasant, still")
        #expect(MoodGuess.describe(valence: -0.5, arousal: 0.5) == "unpleasant, stirred")
        #expect(MoodGuess.describe(valence: 0, arousal: 0) == "neither pleasant nor unpleasant, neither still nor stirred")
    }
}

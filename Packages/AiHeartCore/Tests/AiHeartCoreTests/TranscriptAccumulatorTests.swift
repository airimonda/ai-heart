import Testing
@testable import AiHeartCore

// Synthetic phrases only.

@Suite struct TranscriptAccumulatorTests {
    @Test func keepsTextWhenTheRecognizerRestartsAfterAPause() {
        var a = TranscriptAccumulator()
        for r in ["Work", "Work was long", "Work was long today and I am tired of it"] { a.update(r) }
        // Pause: the recognizer starts again with only the new words.
        for r in ["I", "I want to rest"] { a.update(r) }
        #expect(a.text == "Work was long today and I am tired of it I want to rest")
    }

    @Test func revisionsReplaceInsteadOfDuplicating() {
        var a = TranscriptAccumulator()
        for r in ["I want to go", "I wanted to go home", "I wanted to go home early"] { a.update(r) }
        #expect(a.text == "I wanted to go home early")
        var b = TranscriptAccumulator()
        for r in ["Wean I woke up", "When I woke up"] { b.update(r) }
        #expect(b.text == "When I woke up")
    }

    @Test func finalRunsAreKeptAndTheNextStartsFresh() {
        var a = TranscriptAccumulator()
        a.update("First part.")
        a.finishRun()
        a.update("Second part.")
        a.finishRun()
        a.finishRun()
        #expect(a.text == "First part. Second part.")
        #expect(a.current.isEmpty)
    }

    @Test func emptyResultsChangeNothing() {
        var a = TranscriptAccumulator()
        a.update("  ")
        #expect(a.text.isEmpty)
        a.update("Something")
        a.update("")
        #expect(a.text == "Something")
    }
}

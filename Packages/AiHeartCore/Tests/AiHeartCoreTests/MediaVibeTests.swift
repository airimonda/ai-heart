import Testing
@testable import AiHeartCore

// Synthetic model outputs only.

@Suite struct MediaVibeTests {
    @Test func parsesFixedForm() {
        let raw = "tags: Bittersweet, dreamy, upbeat\npleasant=0.3 energy=0.5\nline: Mostly wistful indie songs with a few bright dance tracks."
        let v = MediaVibe.parse(raw, weekKey: "2026-10-26")!
        #expect(v.tags == ["bittersweet", "dreamy", "upbeat"])
        #expect(v.valence == 0.3 && v.energy == 0.5)
        #expect(v.line.hasPrefix("Mostly"))
        #expect(MediaVibe.parse("It was a nice week.", weekKey: "x") == nil)
        let noTone = MediaVibe.parse("tags: calm, soft\nline: Quiet acoustic songs.", weekKey: "x")!
        #expect(noTone.valence == 0 && noTone.energy == 0)
    }
}

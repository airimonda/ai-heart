import Testing
@testable import AiHeartCore

@Suite struct MoodColorTests {
    @Test func cornersAndMiddle() {
        #expect(MoodColor.color(valence: 1, arousal: 1) == MoodColor.excited)
        #expect(MoodColor.color(valence: 1, arousal: -1) == MoodColor.calm)
        #expect(MoodColor.color(valence: -1, arousal: 1) == MoodColor.tense)
        #expect(MoodColor.color(valence: -1, arousal: -1) == MoodColor.low)
        #expect(MoodColor.color(valence: 0, arousal: 0) == MoodColor.neutral)
    }

    @Test func neverSaturatedRed() {
        for v in stride(from: -1.0, through: 1, by: 0.1) {
            for a in stride(from: -1.0, through: 1, by: 0.1) {
                let c = MoodColor.color(valence: v, arousal: a)
                let h = MoodColor.hue(c)
                let sat = max(c.r, c.g, c.b) - min(c.r, c.g, c.b)
                // Strong colors stay outside the red band.
                if sat > 0.25 { #expect(h > 15 && h < 345, "v \(v) a \(a) hue \(h)") }
            }
        }
    }

    @Test func words() {
        #expect(MoodColor.words(valence: 0.6, arousal: -0.5) == "pleasant and still")
        #expect(MoodColor.words(valence: 0, arousal: 0) == "near neutral")
    }
}

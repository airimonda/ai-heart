import Testing
@testable import AiHeartCore

// Synthetic points only.

@Suite struct DayMoodTests {
    @Test func noPointsNoMood() { #expect(DayMood([]) == nil) }

    @Test func meanOfAllEntries() {
        let d = DayMood([MoodPoint(valence: 0.6, arousal: 0.2), MoodPoint(valence: 0.2, arousal: -0.2)])!
        #expect(abs(d.valence - 0.4) < 1e-9 && abs(d.arousal) < 1e-9)
        #expect(d.count == 2 && !d.mixed)
    }

    @Test func oneHardMomentAmongFineOnesIsMixed() {
        let d = DayMood([MoodPoint(valence: 0.5, arousal: 0), MoodPoint(valence: 0.4, arousal: 0), MoodPoint(valence: -0.6, arousal: 0.5)])!
        #expect(d.mixed)
        #expect(d.lowest.valence == -0.6 && d.highest.valence == 0.5)
        // The mean alone would read as a mildly pleasant day.
        #expect(d.valence > 0)
    }

    @Test func singleEntryIsNeverMixed() {
        #expect(DayMood([MoodPoint(valence: -1, arousal: 0)])!.mixed == false)
    }
}

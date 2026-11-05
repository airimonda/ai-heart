import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only. Owner, 2026-11-04: heavy entries are kept; embarrassing or shameful ones
// are offered for letting go or for keeping without the embarrassing parts.

@Suite struct KeepOrReleaseTests {
    let hard = "[synthetic] It was an awful day. We had a fight and I cried for an hour. A walk helped a bit. I needed someone to listen. Tomorrow I will rest."
    let cringe = "[synthetic] I said something so stupid in the meeting and everyone went quiet. I'm so embarrassed. I needed a minute alone. Next time I will pause before I speak."

    @Test func defaultIsKeep() {
        #expect(KeepOrRelease.decide(text: "[synthetic] Coffee by the window.", word: "Calm", valence: 0.5) == .keep)
        #expect(KeepOrRelease.decide(text: nil, word: "Low", valence: -0.8) == .keep)
    }

    @Test func heavyStoriesAreKept() {
        #expect(KeepOrRelease.decide(text: hard, word: "Heavy", valence: -0.8) == .keep)
        #expect(KeepOrRelease.decide(text: "[synthetic] Terrible fight. I cried. Worst night.", word: nil, valence: -0.8) == .keep)
    }

    @Test func embarrassingEntriesAreOfferedKeepingHerLines() {
        guard case .letGo(let lines, let c) = KeepOrRelease.decide(text: cringe, word: nil, valence: -0.4) else {
            Issue.record("expected an offer"); return
        }
        #expect(c >= KeepOrRelease.threshold)
        #expect(lines.allSatisfy { cringe.contains($0) })
        #expect(lines.contains("Next time I will pause before I speak."))
    }

    @Test func japaneseAndTagalogShameWords() {
        if case .letGo = KeepOrRelease.decide(text: "[synthetic] 会議で変なことを言って本当に恥ずかしい。", word: nil, valence: nil) {} else { Issue.record("ja") }
        if case .letGo = KeepOrRelease.decide(text: "[synthetic] Grabe, nakakahiya yung ginawa ko kanina.", word: nil, valence: nil) {} else { Issue.record("tl") }
    }

    @Test func modelCanOfferOrVeto() {
        // Model says it is shameful even without the words: offered.
        if case .letGo = KeepOrRelease.decide(text: "[synthetic] I tripped on stage in front of everyone.", word: nil, valence: nil, themeIsShameful: true) {} else {
            Issue.record("expected an offer")
        }
        // One weak word and the model says no: kept.
        #expect(KeepOrRelease.decide(text: "[synthetic] Awkward start to the class, then a good chat.", word: nil, valence: nil, themeIsShameful: false) == .keep)
    }

    @Test func selfHarmAndHopelessWinOverShame() {
        #expect(KeepOrRelease.decide(text: "[synthetic] So embarrassed, I wanted to hurt myself", word: nil, valence: -0.9) == .safetyKeep)
        #expect(KeepOrRelease.decide(text: "[synthetic] So ashamed. It feels hopeless.", word: nil, valence: -0.9) == .heavyKeep)
    }

    @Test func scrubDropsEmbarrassingSentencesNotFeelingsOrWants() {
        let s = KeepOrRelease.sentences(cringe)
        let drop = ShameScrub.fallback(s)
        #expect(drop.contains(0))                      // what she said
        #expect(!drop.contains(2) && !drop.contains(3)) // what she needed, what she will do
        #expect(ShameScrub.parse("1, 2", count: s.count) == [0, 1])
        #expect(ShameScrub.parse("none", count: s.count).isEmpty)
        #expect(ShameScrub.kept(s, dropping: [0, 1]) == "I needed a minute alone. Next time I will pause before I speak.")
        #expect(ShameScrub.kept(s, dropping: Set(s.indices)) == s.joined(separator: " "))
        // A dropped sentence is replaced only by her own typed words.
        #expect(ShameScrub.kept(s, dropping: [0], replacing: [0: " [synthetic] It was a hard day. "]) == (["[synthetic] It was a hard day."] + s.dropFirst()).joined(separator: " "))
        #expect(ShameScrub.kept(s, dropping: [0], replacing: [0: "  "]) == s.dropFirst().joined(separator: " "))
    }

    @Test func tags() {
        #expect(KeepOrRelease.tag("A walk helped.") == "helped")
        #expect(KeepOrRelease.tag("I learned to ask.") == "learned")
        #expect(KeepOrRelease.tag("Rain.") == nil)
    }
}

import Foundation
import Testing
@testable import AiHeartCore

// Synthetic text only. Typed entries must be caught by the same list as Listen (docs/17).

@Suite struct SafetyGapTests {
    @Test func indirectAndTagalogPhrasesStopReleaseInTypedEntries() {
        for t in ["[synthetic] Everyone would be better off without me.",
                  "[synthetic] I can’t go on like this.",
                  "[synthetic] Gusto ko nang mamatay.",
                  "[synthetic] ＷＡＮＴ ＴＯ ＤＩＥ"] {
            #expect(SafetyCheck.mentionsSelfHarm(t), "\(t)")
            #expect(KeepOrRelease.decide(text: t, word: "Heavy", valence: -0.9) == .safetyKeep, "\(t)")
        }
    }

    @Test func hopelessEntriesAreKeptNotLetGo() {
        let t = "[synthetic] Awful fight, I cried for hours. It feels hopeless and I am so alone."
        #expect(KeepOrRelease.decide(text: t, word: "Heavy", valence: -0.9) == .heavyKeep)
        #expect(KeepOrRelease.decide(text: "[synthetic] Wala nang pag-asa. Ang bigat.", word: nil, valence: -0.8) == .heavyKeep)
        #expect(KeepOrRelease.decide(text: "[synthetic] もう無理。最悪の日。", word: nil, valence: -0.8) == .heavyKeep)
    }

    @Test func ordinaryHardDayIsKept() {
        // Owner, 2026-11-04: heavy entries are kept; only embarrassing ones are offered for letting go.
        let t = "[synthetic] It was an awful day. We had a fight and I cried for an hour. A walk helped a bit."
        #expect(KeepOrRelease.decide(text: t, word: "Heavy", valence: -0.7) == .keep)
    }
}

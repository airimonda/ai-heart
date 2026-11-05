import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct ReleaseNoteV2Tests {
    let text = "[synthetic] Big presentation tomorrow. I keep checking my slides again and again. "
        + "If I mess up everyone will think I'm a fraud. My stomach is in knots. "
        + "Checking calms me for a minute, then it starts again. I want to just go to sleep early."

    @Test func labelsMapToHerWholeSentences() {
        let s = ReleaseNotes.noteSentences(text)
        #expect(s.count == 6)
        let labels = ReleaseNotes.parseLabels("1: TRIGGER\n2: ACTION\n3: THOUGHT\n4: BODY\n5: PAYOFF\n6: WANT\n7: COST\nx: BODY\n2: NONSENSE", count: s.count)
        #expect(labels.count == 6)
        let n = ReleaseNotes.assemble(sentences: s, labels: labels, summary: "You're anxious about tomorrow's presentation.",
                                      feelings: [.anxious], strength: (.strong, 2),
                                      needs: [NeedNote(need: .capable, met: false, quote: s[2])], text: text)
        #expect(n.version == 2)
        #expect(n.sentences(.action) == [s[1]])
        #expect(n.sentences(.payoff) == [s[4]])
        #expect(n.sentences(.want) == [s[5]])
        #expect(n.thought == s[2])
        #expect(n.intensityQuote == s[2])
        #expect(n.happened == "You're anxious about tomorrow's presentation.")
        #expect(n.allText.allSatisfy { $0 == n.happened || s.contains($0) })
    }

    @Test func strengthAndNeedParsing() {
        #expect(ReleaseNotes.parseStrength("very strong | 3", count: 6)! == (.veryStrong, 2))
        #expect(ReleaseNotes.parseStrength("none | 1", count: 6) == nil)
        #expect(ReleaseNotes.parseStrength("strong | 9", count: 6)!.1 == nil)
        #expect(ReleaseNotes.parseNeedPick("capable | 3.", count: 6)! == (.capable, 2))
        #expect(ReleaseNotes.parseNeedPick("validation | 3", count: 6) == nil)
        #expect(ReleaseNotes.parseNeedPick("none", count: 6) == nil)
        #expect(ReleaseNotes.parseFeelings("happy, close, longing, happy") == [.happy, .close])
    }

    @Test func summaryWithAdviceIsDroppedAndQuietTopicsSkipped() {
        let s = ReleaseNotes.noteSentences(text)
        let n = ReleaseNotes.assemble(sentences: s, labels: [0: .trigger, 1: .action], summary: "You should rest more.",
                                      feelings: [], strength: nil, needs: [], text: text, quietTopics: ["presentation"])
        #expect(n.happened == nil)
        #expect(n.sentences(.trigger).isEmpty)
        #expect(n.sentences(.action) == [s[1]])
    }

    @Test func versionOneNotesStillDecode() {
        let old = #"{"thought":"[synthetic] a thought","version":1,"helped":[],"byModel":true,"feelings":["sad"],"needs":[]}"#
        let n = ReleaseNote.decode(old)
        #expect(n?.thought == "[synthetic] a thought")
        #expect(n?.parts == nil)
    }

    @Test func fallbackHelpedOnlyFromHelpedLines() {
        let n = ReleaseNotes.fallback(text: text, keptLines: ["When I need a comparison to make sense of things.", "A walk helped."])
        #expect(n.helped == ["A walk helped."])
    }
}

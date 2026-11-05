import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct ReleaseNoteV3Tests {
    let text = "[synthetic] Big presentation tomorrow. I keep checking my slides again and again. "
        + "If I mess up everyone will think I'm a fraud. My stomach is in knots. "
        + "Checking calms me for a minute, then it starts again. I want to just go to sleep early."

    func note() -> (ReleaseNote, [String]) {
        let s = ReleaseNotes.noteSentences(text)
        let n = ReleaseNotes.assemble(sentences: s, labels: [0: .trigger, 1: .action, 2: .thought, 3: .body, 4: .payoff, 5: .want],
                                      summary: nil, feelings: [.anxious], strength: nil, needs: [], text: text)
        return (n, s)
    }

    @Test func promptListsOnlyPresentParts() {
        let (n, _) = note()
        let p = ReleaseNotes.partSummaryPrompt(n)!
        #expect(p.contains("TRIGGER (") && p.contains("WANT ("))
        #expect(!p.contains("COST ("))
        #expect(ReleaseNotes.partSummaryPrompt(ReleaseNote()) == nil)
    }

    @Test func summariesParsedCheckedAndLimitedToPresentParts() {
        let (n, _) = note()
        let raw = """
        TRIGGER: You have a big presentation tomorrow.
        ACTION: You keep checking your slides.
        COST: You pay for it later.
        WANT: You should rest more.
        """
        let out = ReleaseNotes.parsePartSummaries(raw, note: n, text: text)
        #expect(out["trigger"] == "You have a big presentation tomorrow.")
        #expect(out["action"] == "You keep checking your slides.")
        #expect(out["cost"] == nil)   // no sentences in that part
        #expect(out["want"] == nil)   // advice fails the check
    }

    @Test func keyLinesAreHerSentencesAtMostTwo() {
        let (_, s) = note()
        #expect(ReleaseNotes.parseKeyLines("3, 6, 2", sentences: s) == [s[2], s[5]])
        #expect(ReleaseNotes.parseKeyLines("none", sentences: s).isEmpty)
        #expect(ReleaseNotes.parseKeyLines("9", sentences: s).isEmpty)
        #expect(ReleaseNotes.parseKeyLines("1", sentences: s, quietTopics: ["presentation"]).isEmpty)
    }

    @Test func letGoSummaryDropsKeyLinesAndPartSummaries() {
        var (n, s) = note()
        n.partSummaries = ["trigger": "You have a big presentation tomorrow."]
        n.keyLines = [s[2]]
        let sum = n.summary
        #expect(sum.keyLines == nil && sum.partSummaries == nil && sum.parts == nil)
    }

    @Test func emotionalHurtDoesNotForceSafety() {
        let txt = "[synthetic] I still think about a teacher who hurt me years ago. It would hurt me if they forgot. I want to let it rest."
        let s = ReleaseNotes.noteSentences(txt)
        let n = ReleaseNotes.assemble(sentences: s, labels: [0: .action, 2: .want], summary: nil, feelings: [], strength: nil,
                                      needs: [NeedNote(need: .understood, met: false, quote: s[1])], text: txt)
        #expect(n.needs.map(\.need) == [.understood])
        let hit = "[synthetic] He hit me last night."
        let m = ReleaseNotes.assemble(sentences: [hit], labels: [:], summary: nil, feelings: [], strength: nil, needs: [], text: hit)
        #expect(m.needs.first?.need == .safety)
    }

    @Test func feelingsPromptAsksForFewer() {
        #expect(ReleaseNotes.feelingsPrompt(["[synthetic] A line."]).contains("never to fill the list"))
    }
}

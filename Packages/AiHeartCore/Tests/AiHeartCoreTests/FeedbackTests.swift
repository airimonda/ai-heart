import Foundation
import Testing
@testable import AiHeartCore

// Synthetic data only.

@Suite struct FeedbackTests {
    let d0 = AnchoredDay(year: 2026, month: 10, day: 1)

    @Test func leanRecordAndPause() {
        var answers: [AnchoredDay: Bool] = [:]
        for i in 0..<10 { answers[d0.adding(days: i)] = i < 3 }
        let s = LeanRecord.summarize(leans: [d0: .lessPleasant, d0.adding(days: 1): .usual],
                                     answers: answers, mood: [d0: -0.4, d0.adding(days: 1): 0.5], usual: 0)
        #expect(s.answered == 10 && s.fit == 3)
        #expect(s.checked == 2 && s.matched == 1)
        #expect(s.paused)
        #expect(LeanRecord.text(s) == "Fit on 3 of 10 days you answered; matched your entries on 1 of 2 days.")
    }

    @Test func notPausedEarly() {
        let s = LeanRecord.summarize(leans: [:], answers: [d0: false, d0.adding(days: 1): false], mood: [:], usual: 0)
        #expect(!s.paused)
    }

    @Test func wordsGiveWayOnlyWithEvidence() {
        let words = ["Wired", "Tired", "Bright", "Calm"]
        // Never picked Wired after 6 showings, picked Tense 4 times: swap.
        let adjusted = WordPreference.adjust(words, picks: ["Tense": 4], shown: ["Wired": 6])
        #expect(adjusted == ["Tense", "Tired", "Bright", "Calm"])
        // Not enough showings yet: keep.
        #expect(WordPreference.adjust(words, picks: ["Tense": 4], shown: ["Wired": 2]) == words)
        // Still one per quadrant.
        let quadrantOf = { (w: String) in WordPreference.quadrants.firstIndex { $0.contains(w) } }
        #expect(Set(adjusted.compactMap(quadrantOf)).count == 4)
    }
}

@Suite struct AboutMeProposalTests {
    func link(_ t: String, _ est: Double, clear: Bool) -> Patterns.Link {
        Patterns.Link(id: t, title: t, interval: Stats.Interval(estimate: est, low: clear ? est - 0.1 : -0.2, high: clear ? est + 0.1 : 0.3, n: 70), pairs: 70)
    }

    @Test func onlyClearFindings() {
        let p = AboutMeProposals.make(links: [link("Sleep", 0.3, clear: true), link("Steps", 0.1, clear: false)],
                                      lift: [], phases: [], keptLines: [], words: [])
        #expect(p.count == 1)
        #expect(p[0].text == "Longer sleep went with more pleasant days for me (70 days, clearer than chance).")
        #expect(p[0].id == "link:Sleep:+")
    }

    @Test func repeatedHelpedLinesAndWords() {
        let p = AboutMeProposals.make(links: [], lift: [], phases: [],
                                      keptLines: ["[synthetic] A walk helped.", "[synthetic] a walk helped.", "[synthetic] once"],
                                      words: [("Calm", 14), ("Tired", 4)])
        #expect(p.contains { $0.text == "Something that has helped me: [synthetic] A walk helped." })
        #expect(!p.contains { $0.text.contains("once") })
        #expect(p.contains { $0.id == "word:calm" })
        #expect(!p.contains { $0.id == "word:tired" })
        #expect(p.allSatisfy { !$0.id.contains("walk") }) // ids carry no readable content
    }

    @Test func neverLabelsOrAdvises() {
        let p = AboutMeProposals.make(links: [link("Resting HR", -0.3, clear: true), link("HRV", 0.25, clear: true)],
                                      lift: [], phases: [], keptLines: [], words: [])
        for t in p.map({ $0.text.lowercased() }) {
            for banned in ["you should", "anxious", "depress", "disorder", "manic", "try to"] { #expect(!t.contains(banned)) }
        }
    }

    @Test func addGoesToOwnSectionOnce() {
        let prop = AboutMeProposals.Proposal(id: "x", text: "[synthetic] noticed line.")
        var doc = AboutMeDoc.template
        doc = AboutMeProposals.add(prop, to: doc)
        doc = AboutMeProposals.add(prop, to: doc)
        let s = doc.sections.first { $0.title == AboutMeProposals.sectionTitle }!
        #expect(s.body == "- [synthetic] noticed line.")
        #expect(AboutMeDoc.parse(doc.markdown) == doc)
    }
}

@Suite struct AboutMeWriterTests {
    @Test func keepsOnlyCleanNewLines() {
        let raw = """
        1. I notice mornings feel calmer when I sleep well.
        - You should sleep more.
        I think I might be manic sometimes.
        I like long walks.
        I like long walks.
        """
        let policy = OutputPolicy(input: "", userText: "[synthetic]", quietTopics: [])
        let lines = AboutMeWriter.lines(from: raw, policy: policy, existing: "- I like long walks.")
        #expect(lines == ["I notice mornings feel calmer when I sleep well."])
    }

    @Test func quietTopicEntriesNeverReachTheModel() {
        let e = AboutMeWriter.entryLines([(word: "Tense", text: "[synthetic] work was long"), (word: "Calm", text: "[synthetic] tea")],
                                         quietTopics: ["work"])
        #expect(e == ["Calm: [synthetic] tea"])
    }
}

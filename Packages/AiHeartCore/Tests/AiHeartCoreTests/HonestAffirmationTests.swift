import Foundation
import Testing
@testable import AiHeartCore

// Synthetic notes only.

@Suite struct HonestAffirmationTests {
    func note(_ parts: [NotePart: [String]], feelings: [NoteFeeling] = [], intensity: NoteIntensity? = nil) -> ReleaseNote {
        var n = ReleaseNote()
        n.version = 2
        n.parts = Dictionary(uniqueKeysWithValues: parts.map { ($0.key.rawValue, $0.value) })
        n.feelings = feelings
        n.intensity = intensity
        return n
    }

    @Test func neverTraitsPromisesOrReassurance() {
        let all = HonestAffirmations.from(note([.want: ["[synthetic] I want to stop."], .action: ["[synthetic] I keep checking again."],
                                                .payoff: ["[synthetic] It calms me."], .helped: ["[synthetic] A walk helped."]],
                                               feelings: [.ashamed, .sad], intensity: .veryStrong))
        #expect(!all.isEmpty && all.count <= HonestAffirmations.maxShown)
        for a in all {
            let l = a.text.lowercased()
            for banned in ["you are strong", "you're strong", "lovable", "will be fine", "will be okay", "proud of you", "don't worry"] {
                #expect(!l.contains(banned))
            }
            #expect(OutputValidator.check(a.text, OutputPolicy(input: a.text, userText: a.text, maxCharacters: 400)).isEmpty)
        }
    }

    @Test func avoidanceIsNotAffirmedAsAValue() {
        let a = HonestAffirmations.from(note([.want: ["[synthetic] I don't want to think about what happened."]], feelings: [.scared], intensity: .veryStrong))
        #expect(!a.contains { $0.text.contains("You wrote what you want") })
    }

    @Test func oneOffEventsAreNotCalledHabits() {
        let panic = HonestAffirmations.from(note([.trigger: ["[synthetic] Panic on the train."], .action: ["[synthetic] I got off and breathed."],
                                                  .payoff: ["[synthetic] It passed after ten minutes."]], feelings: [.scared, .anxious], intensity: .strong))
        #expect(!panic.contains { $0.text.contains("habits form") || $0.text.contains("caught the pattern") })
    }

    @Test func goodDayIsNotCalledHard() {
        let a = HonestAffirmations.from(note([.want: ["[synthetic] I want more days like this."]], feelings: [.happy, .close]))
        #expect(a.first?.text.contains("\u{201C}[synthetic] I want more days like this.\u{201D}") == true)
        #expect(!a.contains { $0.text.contains("hard") || $0.text.contains("heavy") })
        let racing = HonestAffirmations.from(note([.action: ["[synthetic] Started three projects."]], feelings: [.happy, .overwhelmed, .hopeful], intensity: .strong))
        #expect(!racing.contains { $0.text.hasPrefix("This was hard") })
    }

    @Test func noCreditForFeelingsTheModelPicked() {
        let a = HonestAffirmations.from(note([.action: ["[synthetic] I went home."]], feelings: [.sad, .hurt, .angry], intensity: .strong))
        #expect(!a.contains { $0.text.contains("feelings apart") || $0.text.contains("Not just") })
        let b = HonestAffirmations.from(note([.feeling: ["[synthetic] I was sad and angry."]], feelings: [.sad, .angry], intensity: .strong))
        #expect(b.contains { $0.text.contains("sad, angry") })
    }

    @Test func selfHarmOrHopelessThoughtsAreNotHeldUp() {
        for t in ["[synthetic] I wish I could disappear and not exist.", "[synthetic] I can't do this anymore.", "[synthetic] What's the use."] {
            let a = HonestAffirmations.from(note([.thought: [t]], feelings: [.sad], intensity: .veryStrong))
            #expect(!a.contains { $0.text.contains(t) }, "\(t)")
        }
    }

    @Test func dangerFromSomeoneElseMeansSafety() {
        let s = ["[synthetic] He grabbed my arm tonight.", "[synthetic] I'm in a cafe."]
        let n = ReleaseNotes.assemble(sentences: s, labels: [0: .trigger, 1: .action], summary: nil, feelings: [.scared], strength: (.strong, 0),
                                      needs: [NeedNote(need: .expression, met: false, quote: s[0])], text: s.joined(separator: " "))
        #expect(n.missingNeeds.map(\.need) == [.safety])
    }

    @Test func keptEntriesAreAskedTheModelToo() async {
        // Short, no keywords: rules keep it; a model yes must still open safety.
        let d = await ModelChecks.decide(text: "[synthetic] I don't see the point of waking up tomorrow.", word: nil, valence: nil) { prompt in
            prompt.hasPrefix("Does this text mention self-harm") ? true : false
        }
        #expect(d == .safetyKeep)
        let h = await ModelChecks.decide(text: "[synthetic] Nothing I do changes anything.", word: nil, valence: nil) { prompt in
            prompt.hasPrefix("Does the writer sound hopeless") ? true : false
        }
        #expect(h == .heavyKeep)
        let none = await ModelChecks.decide(text: "[synthetic] Coffee by the window.", word: nil, valence: nil) { _ in nil }
        #expect(none == .keep)
    }
}

// Written by the model, checked by fixed rails (owner, 2026-11-05).
@Suite struct WrittenAffirmationTests {
    static let entry = "[synthetic] I wanted to be there for my sister. I went to her place after work. I was exhausted the whole way. "
        + "I asked for a quiet corner and sat down. Nobody noticed I was shaking."
    let sentences = ReleaseNotes.noteSentences(WrittenAffirmationTests.entry)

    func parse(_ line: String, sentences: [String]? = nil) -> WrittenAffirmation? {
        HonestAffirmations.parseLine(line, sentences: sentences ?? self.sentences, text: Self.entry)
    }
    func row(_ text: String, cites: String = "1,2") -> String {
        "LINE: \(text) | SENTENCES: \(cites) | APPROACH: values | BASIS: Both sentences show what matters to you."
    }

    @Test func goodLinePassesAndKeepsAnchors() throws {
        let a = try #require(parse(row("You wanted to be there for her, and you went to her place even though you were exhausted.", cites: "1,2,3")))
        #expect(a.anchors.count == 3 && a.anchors[0].contains("sister"))
        #expect(a.basis.hasPrefix("Self-affirmation"))
        let q = parse(row("You went, and you asked for \"a quiet corner\" when you needed one.", cites: "2,4"))
        #expect(q != nil)
    }

    @Test func parserReadsRowsAndCapsAtTwo() {
        let raw = [row("You wanted to be there for her, and you went to her place."),
                   "- " + row("You were exhausted and still went, which shows what she means to you.", cites: "2,3"),
                   row("You sat down and asked for what you needed after a long day.", cites: "4,3"), "none"].joined(separator: "\n")
        let out = HonestAffirmations.parseWritten(raw, sentences: sentences, text: Self.entry)
        #expect(out.count == 2)
        #expect(HonestAffirmations.parseWritten("none", sentences: sentences, text: Self.entry).isEmpty)
        #expect(HonestAffirmations.parseWritten("LINE: no fields at all", sentences: sentences, text: Self.entry).isEmpty)
    }

    @Test func railsRejectBadLines() {
        let bad: [String: String] = [
            "You are strong, and you went to her place.": "trait",
            "You're such a good person for going to her place.": "trait",
            "It will be okay, you went to her place.": "promise",
            "Things will get better now that you went.": "promise",
            "Don't worry, you went to her place.": "reassurance",
            "You should keep going to her place after work.": "advice",
            "Try to remember that you went to her place.": "advice",
            "Remember how you went to her place after work.": "imperative",
            "Keep going to her place after work, as you did.": "imperative",
            "I think you did well to go to her place.": "I voice",
            "You went to her place, and that is a sign of a depressive episode.": "label",
            "You went to her place and said \"I love you all\" at the door.": "invented quote",
        ]
        for (line, why) in bad {
            #expect(parse(row(line)) == nil, "\(why): \(line)")
            #expect(HonestAffirmations.writtenRejection(line, text: Self.entry) != nil, "\(why): \(line)")
        }
        #expect(HonestAffirmations.writtenRejection("You went to her place after work.", text: Self.entry) == nil)
    }

    @Test func mustCiteValidSentences() {
        let line = "You wanted to be there for her, and you went to her place."
        #expect(parse("LINE: \(line) | APPROACH: values | BASIS: Backed by your words.") == nil)
        #expect(parse(row(line, cites: "")) == nil)
        #expect(parse(row(line, cites: "9")) == nil)
        #expect(parse(row(line, cites: "0")) == nil)
        #expect(parse("LINE: \(line) | SENTENCES: 1 | APPROACH: charisma | BASIS: Backed by your words.") == nil)
    }

    @Test func citedSelfHarmOrHopelessSentenceDropsTheLine() {
        let s = ["[synthetic] I wanted to see my sister.", "[synthetic] Some days I think about ending my life.",
                 "[synthetic] There is no point in anything."]
        let line = "You wanted to see her, and you kept it in mind."
        #expect(HonestAffirmations.parseLine(row(line, cites: "1"), sentences: s, text: s.joined(separator: " ")) != nil)
        #expect(HonestAffirmations.parseLine(row(line, cites: "1,2"), sentences: s, text: s.joined(separator: " ")) == nil)
        #expect(HonestAffirmations.parseLine(row(line, cites: "3"), sentences: s, text: s.joined(separator: " ")) == nil)
        #expect(!HonestAffirmations.mayWrite(for: s.joined(separator: " ")))
        #expect(HonestAffirmations.mayWrite(for: Self.entry))
        // The prompt never shows the model those sentences.
        let p = HonestAffirmations.prompt(sentences: s, labels: [:], note: ReleaseNote())
        #expect(p.contains("sister") && !p.contains("ending my life") && !p.contains("no point"))
    }

    @Test func shownPrefersWrittenAndFallsBackToTemplates() {
        var n = ReleaseNote()
        n.version = 3
        n.parts = [NotePart.want.rawValue: ["[synthetic] I want to rest."]]
        #expect(HonestAffirmations.shown(n).first?.text.contains("want") == true)
        n.affirmations = [WrittenAffirmation(text: "You named rest.", basis: "b", anchors: ["[synthetic] I want to rest."])]
        #expect(HonestAffirmations.shown(n).map(\.text) == ["You named rest."])
        n.affirmations = []
        #expect(HonestAffirmations.shown(n).first?.text.contains("want") == true)
    }

    @Test func letGoSummaryDropsHerWords() {
        var n = ReleaseNote()
        n.parts = [NotePart.want.rawValue: ["[synthetic] I want to rest."]]
        n.affirmations = [WrittenAffirmation(text: "You named rest.", basis: "b", anchors: ["[synthetic] I want to rest."])]
        #expect(n.allText.contains("You named rest."))
        #expect(n.summary.affirmations?.first?.anchors.isEmpty == true && n.summary.summaryOnly == true)
        #expect(n.summary.parts == nil)
    }

    @Test func oldNotesDecodeAndNewOnesRoundTrip() throws {
        let old = ReleaseNote.decode(#"{"feelings":[],"needs":[],"helped":[],"byModel":true,"version":3}"#)
        #expect(old != nil && old?.affirmations == nil)
        var n = ReleaseNote()
        n.affirmations = [WrittenAffirmation(text: "t", basis: "b", anchors: ["a"])]
        #expect(ReleaseNote.decode(n.encoded())?.affirmations == n.affirmations)
    }
}

@Suite struct LetGoAffirmationTests {
    @Test func letGoKeepsOnlyQuoteFreeLinesWithoutAnchors() {
        var n = ReleaseNote()
        n.version = 3
        n.affirmations = [
            WrittenAffirmation(text: "You wanted to be fair to him, and you stopped to think it through.", basis: "Values.", anchors: ["[synthetic] a line"]),
            WrittenAffirmation(text: "You wrote \u{201C}[synthetic] a line\u{201D} and meant it.", basis: "Values.", anchors: ["[synthetic] a line"]),
        ]
        let s = n.summary
        #expect(s.affirmations?.count == 1)
        #expect(s.affirmations?.first?.anchors.isEmpty == true)
        #expect(HonestAffirmations.shown(s).count == 1)
    }

    @Test func letGoWithoutWrittenLinesShowsNoTemplates() {
        var n = ReleaseNote()
        n.feelings = [.ashamed]
        n.intensity = .strong
        #expect(HonestAffirmations.shown(n.summary).isEmpty)
    }

    @Test func noQuotesPromptSaysSo() {
        #expect(HonestAffirmations.prompt(sentences: ["[synthetic] A line."], labels: [0: .want], note: ReleaseNote(), noQuotes: true)
            .contains("Do not quote her"))
    }
}

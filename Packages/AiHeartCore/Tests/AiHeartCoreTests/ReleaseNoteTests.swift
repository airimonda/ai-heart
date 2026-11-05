import Foundation
import Testing
@testable import AiHeartCore

// Synthetic entries only.

@Suite struct ReleaseNoteTests {
    let text = "[synthetic] We had a fight at dinner and I cried for an hour. I kept thinking I always ruin everything. "
        + "My chest was tight the whole time. I just wanted to leave the room. Nobody listened to me. "
        + "I felt so alone. A walk helped a bit."

    @Test func modelLinesSurviveOnlyWhenTheyAreHerWords() {
        let raw = """
        HAPPENED: A disagreement at dinner.
        THOUGHT: I always ruin everything
        FELT: hurt, lonely, devastated, sad
        BODY: My chest was tight
        URGE: She probably wanted to escape her problems
        INTENSITY: very strong
        SHOWN_BY: I cried for an hour
        """
        var note = ReleaseNote()
        ReleaseNotes.parseReaction(raw, text: text, into: &note)
        #expect(note.happened == "A disagreement at dinner.")
        #expect(note.thought == "I always ruin everything")
        #expect(note.feelings == [.hurt, .lonely, .sad])           // "devastated" is not on the list
        #expect(note.body == "My chest was tight")
        #expect(note.urge == nil)                                  // not her words
        #expect(note.intensity == .veryStrong)
        #expect(note.intensityQuote == "I cried for an hour")
    }

    @Test func summaryWithPainfulDetailOrAdviceIsDropped() {
        #expect(ReleaseNotes.checkedSummary("A terrible fight at dinner", text: text) == nil)
        #expect(ReleaseNotes.checkedSummary("You should talk to them", text: text) == nil)
        #expect(ReleaseNotes.checkedSummary("A depressive episode at dinner", text: text) == nil)
        #expect(ReleaseNotes.checkedSummary("A disagreement at dinner", text: text) != nil)
    }

    @Test func intensityNeedsHerWords() {
        var note = ReleaseNote()
        ReleaseNotes.parseReaction("INTENSITY: strong\nSHOWN_BY: she was clearly falling apart", text: text, into: &note)
        #expect(note.intensity == nil)
    }

    @Test func needsComeFromTheListWithHerWords() {
        let raw = """
        NEED: understood | missing | Nobody listened to me
        NEED: connection | missing | I felt so alone
        NEED: validation | missing | Nobody listened to me
        NEED: rest | missing | she needs more sleep
        NEED: safety | maybe | I felt so alone
        HELPED: A walk helped a bit
        """
        var note = ReleaseNote()
        ReleaseNotes.parseNeeds(raw, text: text, into: &note)
        #expect(note.needs.map(\.need) == [.understood, .connection])
        #expect(note.needs.allSatisfy { !$0.met })
        #expect(note.helped == ["A walk helped a bit"])
    }

    @Test func fallbackCopiesHerWordsAndPicksFromLists() {
        let note = ReleaseNotes.fallback(text: text, keptLines: ["A walk helped a bit."])
        #expect(note.feelings.contains(.sad))
        #expect(note.thought?.contains("I always ruin everything") == true)
        #expect(note.body?.contains("chest") == true)
        #expect(note.urge?.contains("wanted to leave") == true)
        #expect(note.intensity != nil)
        #expect(note.missingNeeds.map(\.need).contains(.understood))
        #expect(note.missingNeeds.map(\.need).contains(.connection))
        #expect(note.helped == ["A walk helped a bit."])
        let sentences = KeepOrRelease.sentences(text)
        for q in [note.thought, note.body, note.urge].compactMap({ $0 }) + note.needs.map(\.quote) {
            #expect(sentences.contains { $0.hasPrefix(q.replacingOccurrences(of: "…", with: "")) })
        }
    }

    @Test func quietTopicsNeverAppear() {
        let note = ReleaseNotes.fallback(text: text, keptLines: [], quietTopics: ["dinner"])
        #expect(!note.allText.contains { $0.lowercased().contains("dinner") })
        #expect(ReleaseNotes.checkedQuote("We had a fight at dinner", text: text, quietTopics: ["dinner"]) == nil)
    }

    @Test func mergeKeepsModelAndFillsGaps() {
        var model = ReleaseNote()
        model.happened = "A disagreement at dinner."
        let rules = ReleaseNotes.fallback(text: text, keptLines: ["A walk helped a bit."])
        let m = ReleaseNotes.merged(model: model, rules: rules)
        #expect(m.byModel)
        #expect(m.happened == "A disagreement at dinner.")
        #expect(m.thought == rules.thought)
        #expect(m.helped == ["A walk helped a bit."])
    }

    @Test func storedOnTheEntryAndClearedOnBringBack() throws {
        let e = Entry(kind: .feeling)
        e.text = text
        try EntryLifecycle.letGo(e, restDays: 7)
        e.releaseNote = ReleaseNotes.fallback(text: text, keptLines: [])
        #expect(e.releaseNote?.feelings.isEmpty == false)
        try EntryLifecycle.bringBack(e)
        #expect(e.releaseNote == nil)
    }

    @Test func selfHarmInNotesBlocksRelease() {
        let e = Entry(kind: .feeling)
        var n = ReleaseNote()
        n.thought = "[synthetic] I want to die"
        e.releaseNote = n
        #expect(SafetyCheck.mentionsSelfHarm(e))
    }

    @Test func moodPointLineUsesHerTapOnly() {
        #expect(ReleaseNotes.moodPointLine(valence: nil, arousal: 0.8) == nil)
        #expect(ReleaseNotes.moodPointLine(valence: -0.8, arousal: 0.6) == "Very unpleasant, stirred up")
        #expect(ReleaseNotes.moodPointLine(valence: -0.3, arousal: nil) == "Unpleasant")
    }
}

import Foundation
import Testing
@testable import AiHeartCore

// Synthetic text only. A fake embedder and a scripted model stand in for the real ones.

/// Maps words to fixed axes so cosine similarity is predictable.
struct FakeEmbedder: SentenceEmbedder {
    let axes: [String: Int]
    var language = "en"
    func embed(_ text: String) -> TextEmbedding? {
        var v = [Double](repeating: 0, count: 4)
        let l = text.lowercased()
        for (word, i) in axes where l.contains(word) { v[i] += 1 }
        guard v.contains(where: { $0 > 0 }) else { return TextEmbedding(language: language, vector: [0.01, 0.01, 0.01, 0.01]) }
        return TextEmbedding(language: language, vector: v)
    }
}

struct NoEmbedder: SentenceEmbedder {
    func embed(_ text: String) -> TextEmbedding? { nil }
}

private func entry(_ text: String, status: EntryStatus = .kept, device: String = "dev", daysAgo: Int = 1) -> Entry {
    let e = Entry(kind: .write, createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!)
    e.text = text
    e.status = status
    e.deviceId = device
    return e
}

@Suite struct LocalRetrievalDocumentTests {
    @Test func keptEntriesAreChunkedAboutThreeSentences() {
        let e = entry("[synthetic] One. Two. Three. Four. Five. Six. Seven.")
        let docs = LocalRetrieval.documents(from: [e], quietTopics: [])
        // 7 sentences: chunks of 3, 3, and a lone last one joins the second chunk.
        #expect(docs.count == 2)
        #expect(docs.allSatisfy { $0.entryId == e.syncId && !$0.fromNote })
    }

    @Test func releasedDemoSelfHarmAndQuietAreExcluded() {
        let kept = entry("[synthetic] The bus was late and I missed the start of the meeting.")
        let released = entry("[synthetic] A released story about the garden.", status: .released)
        let demo = entry("[synthetic] A sample entry about the market.", device: BackupArchive.demoDeviceId)
        let harm = entry("[synthetic] I want to die laughing. Also the bus was late.")
        let quiet = entry("[synthetic] We talked about the orchard today.")
        let docs = LocalRetrieval.documents(from: [kept, released, demo, harm, quiet], quietTopics: ["Orchard"])
        #expect(docs.map(\.entryId) == [kept.syncId])
    }

    @Test func restingEntryContributesOnlyItsNote() {
        let e = entry("[synthetic] The full text of a resting entry.", status: .resting)
        var note = ReleaseNote()
        note.happened = "[synthetic] A plan fell through."
        note.parts = [NotePart.thought.rawValue: ["I did not do enough."], NotePart.want.rawValue: ["I want a quieter week."]]
        e.releaseNote = note
        let docs = LocalRetrieval.documents(from: [e], quietTopics: [])
        #expect(docs.count == 1)
        #expect(docs[0].fromNote)
        #expect(docs[0].text.contains("A plan fell through."))
        // A let-go entry's note keeps only its summary (owner, 2026-11-05), so her lines are not retrieved.
        #expect(!docs[0].text.contains("I want a quieter week."))
        #expect(!docs[0].text.contains("full text"))
    }

    @Test func noteWithQuietTopicOrSelfHarmIsSkipped() {
        let a = entry("", status: .resting)
        var n1 = ReleaseNote(); n1.happened = "[synthetic] The orchard was sold."
        a.releaseNote = n1
        let b = entry("", status: .resting)
        var n2 = ReleaseNote(); n2.parts = [NotePart.thought.rawValue: ["I want to die."]]
        b.releaseNote = n2
        #expect(LocalRetrieval.documents(from: [a, b], quietTopics: ["orchard"]).isEmpty)
    }

    @Test func emptyTextGivesNoDocuments() {
        #expect(LocalRetrieval.documents(from: [entry("   \n ")], quietTopics: []).isEmpty)
    }
}

@Suite struct LocalRetrievalSearchTests {
    let axes = ["boss": 0, "manager": 0, "meeting": 0, "garden": 1, "walk": 1, "sister": 2, "money": 2]
    func docs() -> [RetrievalDocument] {
        let now = Date()
        return [
            RetrievalDocument(id: "a", entryId: UUID(), date: now, text: "[synthetic] My manager criticised my report in the meeting."),
            RetrievalDocument(id: "b", entryId: UUID(), date: now, text: "[synthetic] A quiet walk in the garden."),
            RetrievalDocument(id: "c", entryId: UUID(), date: now, text: "[synthetic] An argument with my sister about money."),
        ]
    }

    @Test func hybridRankingUsesEmbeddingAndWords() {
        let index = LocalRetrieval.Index(documents: docs(), embedder: FakeEmbedder(axes: axes))
        // No shared words with the first document, but the same axis in the fake embedding.
        let r = index.search("My boss was unkind at work today.")
        #expect(r.first?.id == "a")
        #expect(!r.contains { $0.id == "b" })
    }

    @Test func wordsAloneWorkWithoutEmbeddings() {
        let index = LocalRetrieval.Index(documents: docs(), embedder: NoEmbedder())
        let r = index.search("The argument with my sister was about money")
        #expect(r.first?.id == "c")
        // Nothing shares a word with this, so nothing comes back.
        #expect(index.search("Completely unrelated vegetables").isEmpty)
    }

    @Test func worksForTextWithoutSpaces() {
        let d = [RetrievalDocument(id: "j", entryId: UUID(), date: .now, text: "今日は会議でとても疲れました。"),
                 RetrievalDocument(id: "k", entryId: UUID(), date: .now, text: "公園を散歩して花を見ました。")]
        let index = LocalRetrieval.Index(documents: d, embedder: NoEmbedder())
        #expect(index.search("会議が長くて疲れた").first?.id == "j")
    }

    @Test func oneSnippetPerEntryAndExcludedIdsAreSkipped() {
        let shared = UUID()
        let d = [RetrievalDocument(id: "x1", entryId: shared, date: .now, text: "[synthetic] The meeting with my manager."),
                 RetrievalDocument(id: "x2", entryId: shared, date: .now, text: "[synthetic] The manager and the meeting again."),
                 RetrievalDocument(id: "y", entryId: UUID(), date: .now, text: "[synthetic] Another manager meeting.")]
        let index = LocalRetrieval.Index(documents: d, embedder: NoEmbedder())
        let all = index.search("manager meeting", k: 4)
        #expect(all.count == 2)
        #expect(Set(all.map(\.entryId)).count == 2)
        let without = index.search("manager meeting", k: 4, excluding: ["x1", "x2"])
        #expect(without.map(\.id) == ["y"])
    }

    @Test func limitsKAndEmptyIndex() {
        let many = (0..<10).map { RetrievalDocument(id: "d\($0)", entryId: UUID(), date: .now, text: "[synthetic] Manager meeting number \($0).") }
        #expect(LocalRetrieval.Index(documents: many, embedder: NoEmbedder()).search("manager meeting").count == 4)
        #expect(LocalRetrieval.Index(documents: [], embedder: NoEmbedder()).search("manager").isEmpty)
    }

    @Test func differentLanguagesAreNotCompared() {
        struct Mixed: SentenceEmbedder {
            func embed(_ text: String) -> TextEmbedding? {
                TextEmbedding(language: text.contains("query") ? "en" : "es", vector: [1, 0, 0, 0])
            }
        }
        let index = LocalRetrieval.Index(documents: [RetrievalDocument(id: "z", entryId: UUID(), date: .now, text: "otro texto")], embedder: Mixed())
        #expect(index.search("query without overlap").isEmpty)
    }
}

@Suite struct TalkMirrorTests {
    let her = "[synthetic] I yelled at my sister again and now I feel awful. I just want us to be close."

    @Test func bodyQuestionsAtMostOncePerTalk() {
        let first = "That sounds heavy. Where do you notice it in your body right now?"
        #expect(TalkItThrough.check(reply: first, herWords: her, quietTopics: []) == nil)
        let again = "The tightness may still be there. Is it in your chest?"
        #expect(TalkItThrough.check(reply: again, herWords: her, quietTopics: [], earlierReplies: [first]) == "repeat body")
        #expect(TalkItThrough.check(reply: "What do you need most right now?", herWords: her, quietTopics: [], earlierReplies: [first]) == nil)
        // Rescue drops only the body question.
        let saved = TalkItThrough.salvage("It sounds like this has been building. Where do you feel it physically?", herWords: her, snippets: [], dropBodyQuestions: true)
        #expect(saved == "It sounds like this has been building.")
    }

    @Test func openQuestionsAreNotAdvice() {
        let q = "Under the tiredness there is a lot of trying. What would it be like to let yourself rest tonight?"
        #expect(TalkItThrough.check(reply: q, herWords: her, quietTopics: []) == nil)
        let advice = "You should let yourself rest tonight. What else is on your mind?"
        #expect(TalkItThrough.check(reply: advice, herWords: her, quietTopics: []) != nil)
    }

    @Test func tentativeReflectionsPass() {
        for r in ["It sounds like under the anger there is hurt, and you want to be close to her. What happened just before you yelled?",
                  "There may be a gap between yelling and wanting to be close. How does that gap feel right now?"] {
            #expect(TalkItThrough.check(reply: r, herWords: her, quietTopics: []) == nil, "\(r)")
        }
    }

    @Test func certaintyAndHiddenMeaningsFail() {
        for r in ["You always push people away. Why do you think that is?",
                  "That's why you yell: deep down you feel unloved. What do you think?",
                  "This is a sign of something bigger. What else is going on?"] {
            #expect(TalkItThrough.check(reply: r, herWords: her, quietTopics: []) != nil, "\(r)")
        }
    }

    @Test func aboutMeIsContextWithoutQuietTopicsAndCannotBeQuoted() {
        let block = TalkItThrough.aboutMeBlock("[synthetic] I like long walks.\n[synthetic] My old job at the bakery.", quietTopics: ["bakery"])
        #expect(block.contains("long walks") && !block.contains("bakery"))
        #expect(TalkItThrough.aboutMeBlock("", quietTopics: []).isEmpty)
        let quoting = "It sounds like you said \"I like long walks\" somewhere. What do walks give you?"
        #expect(TalkItThrough.check(reply: quoting, herWords: her, quietTopics: []) == "invented quote")
    }

    @Test func inventedQuotesAndPlaceholdersFail() {
        let invented = "It sounds like this hurts. On <date> you wrote, \u{201C}I feel like I'm not good enough for her.\u{201D} Does that fit?"
        #expect(TalkItThrough.check(reply: invented, herWords: her, quietTopics: []) != nil)
        let fake = "There may be a link to when you wrote \"nobody ever listens to me\". How does that sit now?"
        #expect(TalkItThrough.check(reply: fake, herWords: her, quietTopics: []) == "invented quote")
        let snip = Snippet(id: "a", entryId: UUID(), date: Date(), text: "[synthetic] I keep checking his page when I feel lonely at night.", fromTalk: true)
        let real = "There may be a link to when you said \u{201C}I keep checking his page when I feel lonely at night\u{201D}. Does tonight feel similar?"
        let why = TalkItThrough.check(reply: real, herWords: her, quietTopics: [], snippets: [snip]); #expect(why == nil, "\(why ?? "")")
        let ownWords = "It sounds like when you say \"I just want us to be close\" there is a lot of longing. What is that longing like?"
        #expect(TalkItThrough.check(reply: ownWords, herWords: her, quietTopics: []) == nil)
    }

    @Test func inventedMemoryIsCutNotTheWholeReply() {
        let r = "It sounds like you are carrying a lot. On <date> you wrote, \u{201C}I feel like I am failing at everything,\u{201D} which echoes this. What makes it feel heavier today?"
        #expect(TalkItThrough.check(reply: r, herWords: her, quietTopics: []) != nil)
        let saved = TalkItThrough.salvage(r, herWords: her, snippets: [])
        #expect(!saved.contains("<date>") && saved.hasSuffix("?"))
        #expect(TalkItThrough.check(reply: saved, herWords: her, quietTopics: []) == nil)
    }

    @Test func talkNotesAreAddressedToHerAndChecked() {
        let ok = "[synthetic] You talked about yelling at your sister and how awful it felt afterwards. You want you two to be close."
        #expect(TalkItThrough.checkNotes(ok, herWords: her, quietTopics: []) == ok)
        // First person would read as her own writing.
        #expect(TalkItThrough.checkNotes("[synthetic] I yelled at my sister again and felt awful.", herWords: her, quietTopics: []) == nil)
        #expect(TalkItThrough.checkNotes("[synthetic] You should call her and apologise.", herWords: her, quietTopics: []) == nil)
        #expect(TalkItThrough.checkNotes("", herWords: her, quietTopics: []) == nil)
        #expect(TalkItThrough.notesSystem.contains("\"you\""))
        #expect(TalkItThrough.notesSystem.contains("Never write as her"))
        let p = TalkItThrough.notesPrompt(turns: [TalkTurn(.her, "a"), TalkTurn(.app, "b")])
        #expect(p.contains("Her: a\nApp: b") && p.contains("addressed to her as \"you\""))
    }

    @Test func onlyUsedPassagesGetChips() {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let a = Snippet(id: "a", entryId: UUID(), date: d, text: "[synthetic] I keep checking his page when I feel lonely at night.")
        let b = Snippet(id: "b", entryId: UUID(), date: d.addingTimeInterval(-86400 * 9), text: "[synthetic] A calm walk by the river.")
        let reply = "On \(TalkItThrough.dateText(d, calendar: cal)) you wrote \u{201C}I keep checking his page when I feel lonely at night\u{201D}. Does tonight feel similar?"
        #expect(TalkItThrough.usedSnippets(reply: reply, snippets: [a, b], calendar: cal).map(\.id) == ["a"])
        #expect(TalkItThrough.usedSnippets(reply: "What feels heaviest right now?", snippets: [a, b], calendar: cal).isEmpty)
    }

    @Test func fallbacksNeverRepeatBackToBack() {
        let a = TalkItThrough.fallback(after: [])
        let b = TalkItThrough.fallback(after: [a])
        let c = TalkItThrough.fallback(after: [a, b])
        #expect(a != b && b != c && a != c)
    }

    @Test func memoryInstructionsOnlyWhenPassagesAreSent() {
        #expect(!TalkItThrough.system(hasPassages: false, hasAboutMe: false).contains("on Nov 3"))
        #expect(TalkItThrough.system(hasPassages: true, hasAboutMe: false).contains("on Nov 3"))
        #expect(!TalkItThrough.system.contains("<date>"))
    }

    @Test func talkMemoriesAreRetrievableButNotSelfHarmChunks() {
        let ok = TalkMemory(text: "[synthetic] I felt left out at dinner again. I wanted someone to ask how I was.")
        let bad = TalkMemory(text: "[synthetic] I want to die some days.")
        let docs = LocalRetrieval.documents(fromTalks: [ok, bad], quietTopics: [])
        #expect(docs.count == 1 && docs[0].fromTalk)
    }
}

@Suite struct TalkPromptTests {
    @Test func systemTextIsTheReviewedWording() {
        #expect(TalkItThrough.system.hasPrefix("You are Claude, inside her private journal app, talking with her through a hard moment."))
        #expect(TalkItThrough.system.hasSuffix("Reply in the language she uses."))
        #expect(TalkItThrough.system.contains("under 90 words"))
        #expect(TalkItThrough.system.contains("never agree that a harsh belief about herself is true"))
        #expect(TalkItThrough.system.contains("do not describe a relationship"))
        #expect(!TalkItThrough.system.contains("  "))
        #expect(!TalkItThrough.system.contains("\n"))
    }

    @Test func promptHasSnippetBlockAndLastTwelveTurns() {
        let turns = (0..<20).map { TalkTurn($0 % 2 == 0 ? .her : .app, "[synthetic] turn \($0)") }
        let snippet = Snippet(id: "s", entryId: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000), text: "[synthetic] A note line.")
        let p = TalkItThrough.prompt(turns: turns, snippets: [snippet])
        #expect(p.hasPrefix("Notes from her journal:"))
        #expect(p.contains("A note line."))
        #expect(p.contains("Your note from"))
        #expect(p.hasSuffix("Your reply:"))
        let conversationLines = p.split(separator: "\n").filter { $0.hasPrefix("Her: ") || $0.hasPrefix("You: ") }
        #expect(conversationLines.count == 12)
        #expect(p.contains("Begin this one differently"))
        #expect(p.contains("[synthetic] turn 19"))
        #expect(p.contains("[synthetic] turn 8"))
        #expect(!p.contains("[synthetic] turn 7\n"))
    }

    @Test func noSnippetsNoBlock() {
        let p = TalkItThrough.prompt(turns: [TalkTurn(.her, "[synthetic] Hello")], snippets: [])
        #expect(!p.contains("Notes from her journal"))
        #expect(p.hasPrefix("Conversation:"))
    }
}

@Suite struct TalkCheckTests {
    let her = "[synthetic] My boss said my work was careless. I think I am useless."
    func check(_ r: String, snippets: [Snippet] = []) -> String? {
        TalkItThrough.check(reply: r, herWords: her, quietTopics: [], snippets: snippets)
    }

    @Test func acceptsAReflectionWithOneQuestion() {
        #expect(check("You said your boss called your work careless. What went through your mind when you heard that?") == nil)
        #expect(check("You think you are useless. What makes it feel true, and what does not?") == nil)
    }

    @Test func rejectsAdvice() {
        #expect(check("You should talk to your boss. What happened?") != nil)
        #expect(check("Try to breathe slowly. What did you feel?") != nil)
    }

    @Test func rejectsReassurance() {
        #expect(check("It will be okay. What did you need?") != nil)
        #expect(check("It will be fine.") != nil)
        #expect(check("This will pass. What did you need?") != nil)
        #expect(check("Don't worry about it. What happened next?") != nil)
    }

    @Test func rejectsAgreeingWithHarshBeliefsButAllowsValidation() {
        #expect(check("You're right, your work was careless. What now?") != nil)
        // Claude's own voice (owner, 2026-11-04): warmth and validation are fine.
        #expect(check("That makes sense. What went through your mind?") == nil)
        #expect(check("I'm so sorry that happened in front of everyone. What's sitting with you most right now?") == nil)
    }

    @Test func rejectsRelationshipTalkButAllowsCare() {
        for r in ["I love you. What happened?", "I'll always be here for you. What happened?", "Our bond matters. What did you need?",
                  "I'm so proud of you. What happened?"] {
            #expect(check(r) != nil, "\(r)")
        }
        #expect(check("I'm glad you told me. What happened next?") == nil)
    }

    @Test func suggestionsOnlyWhenSheAsks() {
        let r = "One small thing that sometimes helps is to step outside for a few minutes. Would that feel okay?"
        #expect(check(r) == nil || check(r) == "advice")
        let asked = "[synthetic] My boss said my work was careless. What should I do tonight?"
        #expect(TalkItThrough.check(reply: "You could try writing down what you would say to her. Would that help?", herWords: asked, quietTopics: []) == nil)
        #expect(TalkItThrough.check(reply: "You should talk to your boss. What happened?", herWords: "[synthetic] It was awful.", quietTopics: []) == "advice")
    }

    @Test func rejectsTwoQuestionsAndLongReplies() {
        #expect(check("What happened? What did you feel?") != nil)
        let long = (["word"] + Array(repeating: "again", count: 95)).joined(separator: " ") + "?"
        #expect(check(long) != nil)
    }

    @Test func rejectsLabelsAndEmpty() {
        #expect(check("That sounds like depression. What happened?") != nil)
        #expect(check("  ") == "empty")
    }

    @Test func aNotesDateIsAllowedButOtherNumbersAreNot() {
        let s = Snippet(id: "s", entryId: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000), text: "[synthetic] Note.")
        let date = TalkItThrough.dateText(s.date)
        #expect(check("Your note from \(date) is about something like this. Is it?", snippets: [s]) == nil)
        #expect(check("Your note from \(date) is about something like this. Is it?") != nil)
        #expect(check("It happened 17 times. What do you make of it?") != nil)
    }
}

@Suite struct TalkSafetyTests {
    @Test func selfHarmHeavyAndOrdinary() {
        #expect(TalkItThrough.safety(herMessage: "[synthetic] I want to kill myself") == .selfHarm)
        #expect(TalkItThrough.safety(herMessage: "[synthetic] I wish I was dead") == .selfHarm)
        #expect(TalkItThrough.safety(herMessage: "[synthetic] It is all too much and I give up") == .heavy)
        #expect(TalkItThrough.safety(herMessage: "[synthetic] Everything feels hopeless") == .heavy)
        #expect(TalkItThrough.safety(herMessage: "[synthetic] My boss was short with me today") == .none)
    }

    @Test func softWrapAfterTwentyMinutesOrThirtyMessages() {
        let start = Date()
        #expect(!TalkItThrough.shouldWrap(startedAt: start, now: start.addingTimeInterval(19 * 60), herMessages: 29))
        #expect(TalkItThrough.shouldWrap(startedAt: start, now: start.addingTimeInterval(20 * 60), herMessages: 3))
        #expect(TalkItThrough.shouldWrap(startedAt: start, now: start, herMessages: 30))
    }
}

@Suite struct TalkReplyTests {
    struct Failing: LanguageModel {
        var name: String { "failing" }
        var canSeeImages: Bool { false }
        func generate(_ request: GenerationRequest) async throws -> String { throw URLError(.notConnectedToInternet) }
    }
    let turns = [TalkTurn(.her, "[synthetic] My boss said my work was careless.")]

    @Test func passingReplyIsReturned() async {
        let m = ScriptedModel(outputs: ["You said your boss called your work careless. What went through your mind?"])
        let r = await TalkItThrough.reply(model: m, turns: turns, snippets: [], quietTopics: [])
        #expect(r == .model("You said your boss called your work careless. What went through your mind?"))
    }

    @Test func retriesOnceThenReturnsTheFixedLine() async {
        let bad = ScriptedModel(outputs: ["I love you so much. What happened?"])
        #expect(await TalkItThrough.reply(model: bad, turns: turns, snippets: [], quietTopics: []) == .fallback(TalkItThrough.fallbackReply))
        // Advice is dropped and the question kept, instead of the fixed line.
        let advice = ScriptedModel(outputs: ["You should quit. What happened?"])
        #expect(await TalkItThrough.reply(model: advice, turns: turns, snippets: [], quietTopics: []) == .model("What happened?"))
        let second = ScriptedModel(outputs: ["It will be fine.", "What went through your mind when she said that?"])
        #expect(await TalkItThrough.reply(model: second, turns: turns, snippets: [], quietTopics: []) == .model("What went through your mind when she said that?"))
    }

    @Test func fallbackLineItselfPassesTheChecks() {
        #expect(TalkItThrough.check(reply: TalkItThrough.fallbackReply, herWords: "", quietTopics: []) == nil)
    }

    @Test func unreachableModelIsReportedNotFaked() async {
        #expect(await TalkItThrough.reply(model: Failing(), turns: turns, snippets: [], quietTopics: []) == .unavailable)
    }
}

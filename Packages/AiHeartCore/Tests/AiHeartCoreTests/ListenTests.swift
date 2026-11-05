import Foundation
import SwiftData
import Testing
@testable import AiHeartCore

// Synthetic strings only. No real journal text.

@Suite struct ListenValidatorTests {
    let transcript = "[synthetic] Work felt heavy today. I needed to stop early. I had 3 meetings."
    func reject(_ reply: String, said: String? = nil, quiet: [String] = []) -> String? {
        ListenRules.rejection(reply, transcript: said ?? transcript, quietTopics: quiet)
    }

    @Test func acceptsGoodReflections() {
        for r in ["You said work felt heavy today, and that you needed to stop early. I may have it wrong.",
                  "Work felt heavy. Where does that sit in your body?",
                  "You had 3 meetings.",
                  "Heavy, and you needed to stop early."] {
            #expect(reject(r) == nil, "\(r)")
        }
    }

    @Test func rejectsAdvice() {
        for r in ["You should rest.", "Try to rest.", "Have you tried resting?", "Make sure you eat.", "Consider a break.",
                  "Remember to breathe.", "It's important to stop.", "Maybe you could try resting", "You need to slow down."] {
            #expect(reject(r) != nil, "\(r)")
        }
        // Whole words only: "country" and "entry" are not "try".
        #expect(reject("Your entry about the country felt heavy.") == nil)
    }

    @Test func rejectsLabelsUnlessSheSaidThem() {
        for r in ["That sounds triggered.", "You may be dissociating.", "A trauma response, maybe.", "You seem manic.",
                  "You feel depressed.", "An anxiety disorder, perhaps."] {
            #expect(reject(r) != nil, "\(r)")
        }
        let said = "I felt depressed and triggered all day."
        #expect(reject("You felt depressed and triggered.", said: said) == nil)
        #expect(reject("You felt manic.", said: said) != nil)
    }

    @Test func rejectsReassurancePersonaAndEmpathyClaims() {
        for r in ["It will be okay.", "Everything will pass.", "You're doing great.", "You've got this.", "I understand how you feel.",
                  "I'm here for you.", "As your friend, I hear you.", "I care about you.", "I'm proud of you."] {
            #expect(reject(r) != nil, "\(r)")
        }
    }

    @Test func rejectsShapeProblems() {
        #expect(reject("Work felt heavy. You stopped early. It was a lot.") == "too many sentences")
        #expect(reject("Heavy? Or tired?") == "too many questions")
        #expect(reject("") == "empty")
        #expect(reject(String(repeating: "heavy ", count: 80)) == "too long")
        #expect(reject("You had 7 meetings.") == "number")
        #expect(reject("You had 3 meetings.") == nil)       // she said 3
    }

    @Test func rejectsQuietTopicMention() {
        #expect(reject("You said the garden felt heavy.", quiet: ["Garden"]) != nil)
        #expect(reject("You said work felt heavy.", quiet: ["Garden"]) == nil)
    }

    @Test func rejectionReasonHasNoContent() {
        let reason = reject("You should visit the secret-word garden.") ?? ""
        #expect(!reason.contains("secret-word") && reason.count < 30)
    }

    @Test func adversarialReplies() {
        let said = "[synthetic] I have not slept and the deadline is close."
        for r in ["Maybe you could try resting", "This sounds like burnout", "It seems like you are overwhelmed because you work too much.",
                  "You are probably exhausted, so rest.", "That's a sign you need a break.",
                  "I'm worried about you. Please call a crisis line.", "You are not alone, I am here with you.",
                  "Stay with me, I will talk you through this.", "You deserve better than this.", "It's normal to feel this way.",
                  "Try to breathe, you are safe.", "Take a deep breath."] {
            #expect(ListenRules.rejection(r, transcript: said, quietTopics: []) != nil, Comment(rawValue: r))
        }
    }

    @Test func systemPromptCarriesTheRules() {
        let s = ListenRules.system.lowercased()
        for k in ["2 short sentences", "1 question", "never give advice", "never reassure", "no name"] { #expect(s.contains(k)) }
        #expect(ListenRules.reflectionPrompt(transcript: "[synthetic] hello").contains("[synthetic] hello"))
    }
}

@Suite struct ListenReflectionTests {
    let said = "[synthetic] Work felt heavy today. I needed to stop early."

    @Test func promptNoLongerAsksForTheHedge() {
        #expect(!ListenRules.reflectionPrompt(transcript: said).lowercased().contains("then add"))
        #expect(!ListenRules.reflectionPrompt(transcript: said).contains("I may have it wrong"))
        #expect(!ListenRules.system.contains("I may have it wrong"))
    }

    @Test func hedgeIsRemovedAndHerWordsStay() {
        #expect(ListenRules.cleanedReflection("Work felt heavy today. I may have it wrong.") == "Work felt heavy today.")
        #expect(ListenRules.cleanedReflection("Work felt heavy. I\u{2019}m not sure, I may not have it right.") == "Work felt heavy.")
    }

    @Test func aHedgeAloneLeavesNothing() {
        #expect(ListenRules.cleanedReflection("I may have it wrong.").isEmpty)
        #expect(ListenRules.rejection(ListenRules.cleanedReflection("I may have it wrong."), transcript: said, quietTopics: []) == "empty")
    }

    @Test func replyMustCarryHerWords() {
        #expect(ListenRules.echoesHer("Work felt heavy, and you needed to stop.", transcript: said))
        #expect(!ListenRules.echoesHer("I hear you.", transcript: said))
        #expect(!ListenRules.echoesHer("That is something you said about this.", transcript: said))
        #expect(ListenRules.echoesHer("仕事が重かった。", transcript: "[synthetic] 今日は仕事が重かった。"))
        #expect(!ListenRules.echoesHer("わかりました。", transcript: "[synthetic] 今日は仕事が重かった。"))
    }
}

@Suite struct ListenSortTests {
    let said = "[synthetic] The meeting ran late and my plan fell through. I feel so tired and tense. I know I need to rest and send the email tomorrow."

    @Test func fallbackSortsHerWords() {
        let s = ListenSort.fallback(said)
        #expect(s.happened == ["[synthetic] The meeting ran late and my plan fell through."])
        #expect(s.felt == ["I feel so tired and tense."])
        #expect(s.know == ["I know I need to rest and send the email tomorrow."])
    }

    @Test func fallbackOnlyUsesHerWords() {
        let s = ListenSort.fallback(said)
        for line in s.happened + s.felt + s.know { #expect(ListenSort.isHerWords(line, transcript: said), "\(line)") }
    }

    @Test func iCantIsNotSomethingSheKnows() {
        #expect(ListenSort.fallback("[synthetic] I can't sleep at night.").know.isEmpty)
        #expect(ListenSort.fallback("[synthetic] I don't know what happened at work.").know.isEmpty)
    }

    @Test func fallbackRespectsQuietTopics() {
        let s = ListenSort.fallback(said, quietTopics: ["meeting"])
        #expect(s.happened.isEmpty)
        #expect(!s.felt.isEmpty)
    }

    @Test func longRunOfSpeechIsCut() {
        let run = "[synthetic] the train was late and everyone was shouting at the door and I felt so tense the whole way there but I know I need to leave earlier next time"
        let s = ListenSort.fallback(run)
        #expect(!s.felt.isEmpty)
        #expect(!s.know.isEmpty)
    }

    @Test func parseKeepsHerLines() throws {
        let raw = "HAPPENED: The meeting ran late.\nFELT: so tired and tense\nKNOW: I need to rest"
        let s = try #require(ListenSort.parse(raw, transcript: said, quietTopics: []))
        #expect(s.happened == ["The meeting ran late."])
        #expect(s.felt == ["so tired and tense"])
        #expect(s.know == ["I need to rest"])
    }

    @Test func parseDropsNoneAdviceAndInventedLines() {
        let none = ListenSort.parse("HAPPENED: The meeting ran late.\nFELT: none\nKNOW: none", transcript: said, quietTopics: [])
        #expect(none?.felt.isEmpty == true && none?.know.isEmpty == true)
        let advice = ListenSort.parse("KNOW: You should try to rest", transcript: said, quietTopics: [])
        #expect(advice == nil)
        let invented = ListenSort.parse("KNOW: Call your manager about a new role", transcript: said, quietTopics: [])
        #expect(invented == nil)
        #expect(ListenSort.parse("no lines here", transcript: said, quietTopics: []) == nil)
    }

    @Test func promptAddsNothingOfItsOwn() {
        #expect(ListenSort.prompt(transcript: said).contains("[synthetic]"))
        #expect(ListenSort.system.lowercased().contains("no advice"))
    }
}

@Suite struct ListenHeavyTests {
    @Test func heavyWordsShowTheCard() {
        for t in ["[synthetic] It is all too much today.", "[synthetic] I can\u{2019}t cope with this.", "[synthetic] I feel hopeless.",
                  "[synthetic] もう無理。", "[synthetic] Hindi ko na kaya."] {
            #expect(ListenSafety.feelsHeavy(t), "\(t)")
        }
    }

    @Test func anOrdinaryDayDoesNot() {
        for t in ["[synthetic] Work was busy and I felt tired.", "[synthetic] I went for a walk."] { #expect(!ListenSafety.feelsHeavy(t), "\(t)") }
    }

    @Test func theSelfHarmStopIsSeparateAndUnchanged() {
        #expect(!ListenSafety.flags("[synthetic] It is all too much today."))
    }
}

@Suite struct ListenFallbackTests {
    func words(_ s: String) -> [String] { s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }

    let long = "[synthetic] Today was strange. Work felt heavy and I kept losing track of what I was doing, and then the afternoon dragged on, and I could not make myself stand up from the desk at all. I went home early. Then I sat in the kitchen for a long time."

    @Test func usesOnlyHerWordsAndIsShort() {
        let out = ListenRules.fallbackReflection(long)
        let input = Set(words(long))
        #expect(!out.isEmpty)
        #expect(words(out).allSatisfy { input.contains($0) })
        #expect(ListenRules.sentences(in: out).count <= 2)
        for s in ListenRules.sentences(in: out) { #expect(s.split(separator: " ").count <= 22) }
    }

    @Test func prefersFeelingSentences() {
        let out = ListenRules.fallbackReflection("I opened the window. I felt so tired and heavy all day. Then I made tea.")
        #expect(out.contains("tired and heavy"))
    }

    @Test func emptyAndShortInputs() {
        #expect(ListenRules.fallbackReflection("") == "")
        #expect(ListenRules.fallbackReflection("   \n ") == "")
        #expect(ListenRules.fallbackReflection("Tired.") == "Tired.")
        #expect(ListenRules.fallbackReflection("no punctuation here at all") == "no punctuation here at all.")
    }

    @Test func skipsQuietTopics() {
        let t = "The garden is what hurts. Work felt heavy today."
        let out = ListenRules.fallbackReflection(t, quietTopics: ["garden"])
        #expect(!out.lowercased().contains("garden") && out.contains("Work felt heavy"))
        // Only quiet sentences: nothing is shown rather than a quiet topic.
        #expect(ListenRules.fallbackReflection("The garden hurts.", quietTopics: ["garden"]) == "")
    }

    @Test func japaneseIsTrimmedByCharacters() {
        let t = "今日はとても疲れました。仕事が重くて、何も考えられなくて、午後はずっと机の前で動けないままでした。"
        let out = ListenRules.fallbackReflection(t)
        #expect(!out.isEmpty && out.count <= 90)
        #expect(ListenRules.fallbackReflection("疲れた。") == "疲れた。")
    }

    @Test func fallbackPassesItsOwnValidator() {
        let out = ListenRules.fallbackReflection(long)
        #expect(ListenRules.rejection(out, transcript: long, quietTopics: []) == nil)
    }
}

@Suite struct ListenSafetyTests {
    @Test func englishJapaneseTagalog() {
        for t in ["I have no reason to live", "they'd be better off without me", "I just can\u{2019}t go on", "I want to end it all",
                  "I have a plan to die", "I want to kill myself", "消えてしまいたい", "もう生きていたくない", "死にたい",
                  "Ayoko nang mabuhay", "gusto ko nang MAMATAY", "naisip kong magpakamatay", "ｱﾖｺ ayoko  nang mabuhay"] {
            #expect(ListenSafety.flags(t), "\(t)")
        }
    }

    @Test func ordinaryTextDoesNotFire() {
        for t in ["I'm dying to see the concert", "Work felt heavy today", "今日は疲れた", "Pagod na ako ngayon", "I cut the cake", ""] {
            #expect(!ListenSafety.flags(t), "\(t)")
        }
    }

    @Test func negationsStillFireOnPurpose() {
        // Documented: safety first. A calm page for a false alarm costs little.
        #expect(ListenSafety.flags("I would never hurt myself"))
    }
}

@Suite struct ListenPacingTests {
    @Test func nudgeTiming() {
        #expect(!ListenRules.shouldNudge(silence: 60, offers: .ask, nudgesSoFar: 0, secondsSinceLastNudge: nil))
        #expect(!ListenRules.shouldNudge(silence: 11.9, offers: .sometimes, nudgesSoFar: 0, secondsSinceLastNudge: nil))
        #expect(ListenRules.shouldNudge(silence: 12, offers: .sometimes, nudgesSoFar: 0, secondsSinceLastNudge: nil))
        #expect(ListenRules.shouldNudge(silence: 12, offers: .sometimes, nudgesSoFar: 1, secondsSinceLastNudge: 50))
        #expect(!ListenRules.shouldNudge(silence: 30, offers: .sometimes, nudgesSoFar: 2, secondsSinceLastNudge: nil))
        #expect(!ListenRules.shouldNudge(silence: 7.9, offers: .often, nudgesSoFar: 0, secondsSinceLastNudge: nil))
        #expect(ListenRules.shouldNudge(silence: 8, offers: .often, nudgesSoFar: 3, secondsSinceLastNudge: nil))
        #expect(!ListenRules.shouldNudge(silence: 30, offers: .often, nudgesSoFar: 4, secondsSinceLastNudge: nil))
        // Never two within 45 s.
        #expect(!ListenRules.shouldNudge(silence: 30, offers: .often, nudgesSoFar: 1, secondsSinceLastNudge: 44.9))
        #expect(ListenRules.shouldNudge(silence: 30, offers: .often, nudgesSoFar: 1, secondsSinceLastNudge: 45))
    }

    @Test func longSession() {
        #expect(!ListenRules.shouldSayLong(elapsed: 1199, enabled: true, alreadySaid: false))
        #expect(ListenRules.shouldSayLong(elapsed: 1200, enabled: true, alreadySaid: false))
        #expect(!ListenRules.shouldSayLong(elapsed: 5000, enabled: true, alreadySaid: true))
        #expect(!ListenRules.shouldSayLong(elapsed: 5000, enabled: false, alreadySaid: false))
    }

    @Test func fixedLinesPassTheValidatorsRules() {
        #expect(ListenRules.nudges == ["Take your time.", "Anything else?", "Where does that sit in your body?"])
        #expect(ListenRules.longSessionLine == "We have been at this a while. Want to stop here?")
        #expect(ListenOffers.allCases.map(\.label) == ["Only when I ask", "Sometimes", "Often"])
    }
}

@Suite struct ListenStorageTests {
    @Test func settingsDefaultsAndAccessor() {
        let s = AppSettings()
        #expect(s.listenOffers == .ask && !s.listenSpeak && !s.listenLongNote && !s.listenOfferPerson)
        s.listenOffers = .sometimes
        #expect(s.listenOffersRaw == "sometimes")
        s.listenOffersRaw = "junk"
        #expect(s.listenOffers == .ask)
    }

    @Test func sessionBacksUpMergesAndSkipsDemo() throws {
        let a = ModelContext(try exportContainer())
        a.insert(ListenSession(date: t0, seconds: 90, offerRaw: "nothing", deviceId: "dev-1"))
        a.insert(ListenSession(date: t0, seconds: 5, deviceId: "demo"))
        try a.save()
        let archive = try BackupArchive.make(context: a)
        let b = ModelContext(try exportContainer())
        let first = try BackupArchive.restore(archive, into: b)
        #expect(first.added["ListenSession"] == 1)
        let again = try BackupArchive.restore(archive, into: b)
        #expect(again.added["ListenSession"] == nil)
        let rows = try b.fetch(FetchDescriptor<ListenSession>())
        #expect(rows.count == 1 && rows[0].offerRaw == "nothing" && rows[0].helpedRaw == nil)
    }

    @Test func oldBackupWithoutListenFieldsRestores() throws {
        let a = ModelContext(try exportContainer())
        seedEverything(a)
        var files = try ZipReader.entries(BackupArchive.make(context: a))
        var settings = try JSONSerialization.jsonObject(with: files["appSettings.json"]!) as! [[String: Any]]
        for k in ["listenOffersRaw", "listenSpeak", "listenLongNote", "listenOfferPerson"] { settings[0].removeValue(forKey: k) }
        files["appSettings.json"] = try JSONSerialization.data(withJSONObject: settings)
        files.removeValue(forKey: "listenSessions.json")
        var z = ZipWriter()
        for (k, v) in files { z.add(k, v) }
        let b = ModelContext(try exportContainer())
        _ = try BackupArchive.restore(z.finish(), into: b)
        let s = try #require(try b.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(s.listenOffers == .ask && s.safetyPage == "[synthetic] safety")
    }
}

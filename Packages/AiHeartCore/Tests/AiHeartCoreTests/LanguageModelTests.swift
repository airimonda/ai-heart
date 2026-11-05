import Foundation
import Testing
@testable import AiHeartCore

// Synthetic outputs only. A scripted model stands in for Gemma.

struct ScriptedModel: LanguageModel {
    let outputs: [String]
    let counter = Counter()
    var name: String { "scripted" }
    var canSeeImages: Bool { true }
    func generate(_ request: GenerationRequest) async throws -> String {
        let i = await counter.next()
        return outputs[min(i, outputs.count - 1)]
    }

    actor Counter {
        var n = 0
        func next() -> Int { defer { n += 1 }; return n }
    }
}

@Suite struct OutputValidatorTests {
    @Test func numbersMustComeFromInput() {
        let p = OutputPolicy(input: "sleep 6.5 h, resting HR 62")
        #expect(OutputValidator.check("Sleep was 6.5 hours and resting HR 62.", p).isEmpty)
        #expect(OutputValidator.check("Sleep was 7 hours.", p) == [.numberNotInInput("7")])
    }

    @Test func labelsAllowedOnlyIfSheWroteThem() {
        let p = OutputPolicy(input: "", userText: "")
        #expect(OutputValidator.check("This looks manic.", p).contains(.label("manic")))
        let mine = OutputPolicy(input: "", userText: "I felt a bit manic today")
        #expect(!OutputValidator.check("You wrote that it felt manic.", mine).contains(.label("manic")))
    }

    @Test func noAdviceNoReassuranceNoDose() {
        let p = OutputPolicy(input: "")
        #expect(OutputValidator.check("You should rest more.", p).contains(.advice("you should")))
        #expect(OutputValidator.check("Maybe increase your dose.", p).contains(.advice("increase your dose")))
        #expect(OutputValidator.check("Don't worry, it passes.", p).contains(.reassurance("don't worry")))
    }

    @Test func quietTopicsNeverRaised() {
        let p = OutputPolicy(input: "", quietTopics: ["Work"])
        #expect(OutputValidator.check("Tense, like work days.", p) == [.quietTopic("Work")])
    }

    @Test func regeneratesUntilClean() async {
        let m = ScriptedModel(outputs: ["You should rest. Calm", "Calm, heavy, bright"])
        let out = await OutputValidator.generate(m, GenerationRequest(system: "", prompt: ""), policy: OutputPolicy(input: ""))
        #expect(out == "Calm, heavy, bright")
    }

    @Test func dropsWhenNothingPasses() async {
        let m = ScriptedModel(outputs: ["Don't worry"])
        let out = await OutputValidator.generate(m, GenerationRequest(system: "", prompt: ""), policy: OutputPolicy(input: ""))
        #expect(out == nil)
    }
}

@Suite struct WordTaskTests {
    @Test func parsesMessyLists() {
        #expect(WordTasks.parseWords("1. calm\n2. Tired,  hopeful.", limit: 3) == ["Calm", "Tired", "Hopeful"])
        #expect(WordTasks.parseWords("Calm, calm, this is a long sentence about things, Light", limit: 3) == ["Calm", "Light"])
        #expect(WordTasks.parseWords("静か、疲れた", limit: 3) == ["静か", "疲れた"])
    }

    @Test func parsesCaptionAndWords() {
        let r = WordTasks.parsePhoto("Line 1: A cup of tea by the window\nLine 2: calm, quiet, warm")
        #expect(r.caption == "A cup of tea by the window")
        #expect(r.words == ["Calm", "Quiet", "Warm"])
        let noCap = WordTasks.parsePhoto("Calm, quiet, warm")
        #expect(noCap.caption == nil)
        #expect(noCap.words == ["Calm", "Quiet", "Warm"])
        let long = WordTasks.parsePhoto("This is a very long sentence that goes on and on about the photo\nCalm, warm, soft")
        #expect(long.caption == nil)
        #expect(long.words.count == 3)
    }

    @Test func parsesVibe() {
        #expect(WordTasks.parseVibe("Quiet reflection") == "Quiet reflection")
        #expect(WordTasks.parseVibe("\"slow sunny morning.\"\n") == "Slow sunny morning")
        #expect(WordTasks.parseVibe("Caption: A quiet evening") == "A quiet evening")
        #expect(WordTasks.parseVibe("This photo shows a very long description of many many things at once") == nil)
        #expect(WordTasks.parseVibe("  ") == nil)
    }

    @Test func vocabularyByUse() {
        #expect(WordTasks.vocabulary(from: ["Calm", "Tired", "Calm", "Wired"]) == ["Calm", "Tired", "Wired"])
    }

    @Test func fallbackStartsWithHerWords() {
        let w = WordTasks.fallbackWords(vocabulary: ["Steady", "Calm"], limit: 4)
        #expect(w.first == "Steady")
        #expect(w.count == 4)
        #expect(Set(w).count == 4)
    }

    @Test func ruleBasedModelNeverPretends() async {
        let m = RuleBasedModel()
        #expect(!m.canSeeImages)
        let out = await OutputValidator.generate(m, GenerationRequest(system: "", prompt: ""), policy: OutputPolicy(input: ""))
        #expect(out == nil)
    }
}

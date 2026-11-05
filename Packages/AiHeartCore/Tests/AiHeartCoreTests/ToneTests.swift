import Testing
@testable import AiHeartCore

// Synthetic strings only.

@Suite struct ToneTests {
    @Test func parses() {
        #expect(WordTasks.parseTone("pleasant=0.6 energy=-0.2")! == (0.6, -0.2))
        #expect(WordTasks.parseTone("Pleasant: -0.4\nEnergy: 0.5")! == (-0.4, 0.5))
        #expect(WordTasks.parseTone("pleasant=3 energy=-9")! == (1, -1))
        #expect(WordTasks.parseTone("It felt nice") == nil)
        #expect(WordTasks.tonePrompt(text: nil).contains("photo"))
        #expect(WordTasks.tonePrompt(text: "[synthetic] a calm walk").contains("calm walk"))
    }
}

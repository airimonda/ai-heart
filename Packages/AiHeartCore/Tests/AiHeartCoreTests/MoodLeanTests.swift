import Foundation
import Testing
@testable import AiHeartCore

@Suite struct MoodLeanTests {
    func link(_ t: String, _ est: Double, clear: Bool, n: Int = 60) -> Patterns.Link {
        let iv = clear ? Stats.Interval(estimate: est, low: est - 0.1, high: est + 0.1, n: n)
                       : Stats.Interval(estimate: est, low: -0.2, high: 0.3, n: n)
        return Patterns.Link(id: t, title: t, interval: iv, pairs: n)
    }

    @Test func notYetWithoutClearLinks() {
        #expect(MoodLean.compute(links: [link("Sleep", 0.1, clear: false)], z: ["Sleep": -2]) == nil)
        #expect(MoodLean.sentence(nil).hasPrefix("Not yet"))
    }

    @Test func shortSleepWithPositiveLinkLeansLessPleasant() {
        let r = MoodLean.compute(links: [link("Sleep", 0.3, clear: true), link("Steps", 0.2, clear: false)],
                                 z: ["Sleep": -2, "Steps": 3])!
        #expect(r.direction == .lessPleasant)
        #expect(r.from == ["Sleep"])
        let text = MoodLean.sentence(r)
        #expect(text.contains("A lean, not a rule."))
        for banned in ["will be", "you should", "expect"] { #expect(!text.lowercased().contains(banned)) }
    }

    @Test func usualWhenSignalsAreUsual() {
        #expect(MoodLean.compute(links: [link("Sleep", 0.3, clear: true)], z: ["Sleep": 0.1])?.direction == .usual)
    }

    @Test func promptsFollowBodyThenRotate() {
        let d = AnchoredDay(year: 2026, month: 11, day: 1)
        #expect(WritingPrompts.pick(day: d, body: BodyToday(sleepZ: -2)) == "How did the short night show up today?")
        #expect(WritingPrompts.pick(day: d, body: nil) != WritingPrompts.pick(day: d, body: nil, skip: 1))
        let all = WritingPrompts.general + WritingPrompts.bodyPrompts(BodyToday(sleepZ: -2, restingHRZ: 2, hrvZ: -2))
        for p in all.map({ $0.lowercased() }) {
            for banned in ["should", "streak", "haven't", "must", "trauma", "why do you"] { #expect(!p.contains(banned)) }
        }
    }
}

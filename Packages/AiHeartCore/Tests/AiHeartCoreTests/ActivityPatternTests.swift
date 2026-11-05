import Testing
@testable import AiHeartCore

// Synthetic days only.

@Suite struct ActivityPatternTests {
    @Test func groupsActiveQuietAndKinds() {
        let d0 = AnchoredDay(year: 2026, month: 6, day: 1)
        var mood: [AnchoredDay: Double] = [:]
        var acts: [AnchoredDay: Set<ActivityGroup>] = [:]
        for i in 0..<40 {
            let d = d0.adding(days: i)
            let kind: ActivityGroup? = i % 4 == 0 ? nil : (i % 4 == 1 ? .walk : (i % 4 == 2 ? .yoga : .aerobics))
            mood[d] = kind == nil ? -0.1 : 0.3
            if let kind { acts[d] = [kind] }
        }
        var input = PatternInput(mood: mood, signals: [:], load: [:], liftDays: [], phase: { _ in nil }, today: d0.adding(days: 40))
        input.activityDays = acts
        let g = Patterns.activityGroups(input)
        #expect(g[0].label == "Active days" && g[1].label == "Quiet days")
        #expect(g.contains { $0.label == "Walk or jog" } && g.contains { $0.label == "Yoga" })
        #expect(Patterns.describeActivity(g).contains("higher"))
        #expect(ActivityGroup.of(.dance) == .aerobics && ActivityGroup.of(.run) == .walk)
        #expect(ActivityGroup.movedEnough(steps: 7200, exerciseMin: nil))
    }
}

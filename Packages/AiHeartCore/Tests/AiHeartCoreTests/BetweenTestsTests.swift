import Testing
@testable import AiHeartCore

// Synthetic checks only.

@Suite struct BetweenTestsTests {
    let d0 = AnchoredDay(year: 2026, month: 6, day: 1)

    @Test func groupsByLabsNewestFirst() {
        let checks = (0..<16).map { i in
            BetweenTests.Check(week: d0.adding(days: 7 * i), symptoms: i < 8 ? ["Tired": 2, "Cold": i % 2] : ["Racing heart": 1])
        }
        let labs = [d0.adding(days: 20), d0.adding(days: 60)]
        let p = BetweenTests.periods(checks: checks, labDays: labs, doses: [(d0.adding(days: 30), "50 to 75")], today: d0.adding(days: 112))
        #expect(p.count == 3)
        #expect(p[0].startLab == labs[1] && p[0].endLab == nil)
        #expect(p[0].counts.first == .init(symptom: "Racing heart", weeks: p[0].checked))
        #expect(p[1].startLab == labs[0] && p[1].endLab == labs[1])
        #expect(p[1].doses.count == 1)
        #expect(p[1].counts.first?.symptom == "Tired")
        #expect(p[2].startLab == nil)
    }

    @Test func noLabsOneStretch() {
        let checks = [BetweenTests.Check(week: d0, symptoms: [:])]
        let p = BetweenTests.periods(checks: checks, labDays: [], doses: [], today: d0.adding(days: 10))
        #expect(p.count == 1)
        #expect(BetweenTests.quietLine(p[0]) == "Nothing ticked. Near your usual.")
    }
}

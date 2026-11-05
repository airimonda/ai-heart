import Foundation
import Testing
@testable import AiHeartCore

// Synthetic values only.

@Suite struct LabsTests {
    @Test func symptomScoreSignAndRange() {
        #expect(BodyBalance.symptomScore(signs: [:]) == 0)
        #expect(BodyBalance.symptomScore(signs: ["Tired": 2, "Foggy": 1]) < 0)
        #expect(BodyBalance.symptomScore(signs: ["Racing heart": 2]) > 0)
        let all = Dictionary(uniqueKeysWithValues: BodySigns.higher.map { ($0, 2) })
        #expect(BodyBalance.symptomScore(signs: all) == 1)
    }

    @Test func signalDirections() {
        #expect(BodyBalance.signalScore(rhrZ: 2, hrvZ: -2, tempZ: nil, sleepZ: -2)! > 0)
        #expect(BodyBalance.signalScore(rhrZ: -2, hrvZ: 2, tempZ: nil, sleepZ: 2)! < 0)
        #expect(BodyBalance.signalScore(rhrZ: nil, hrvZ: nil, tempZ: nil, sleepZ: nil) == nil)
        #expect(BodyBalance.signalScore(rhrZ: 10, hrvZ: nil, tempZ: nil, sleepZ: nil) == 1)
    }

    @Test func combineWeightsCheckMore() {
        #expect(BodyBalance.combine(symptoms: 1, signals: -1)! > 0)
        #expect(BodyBalance.combine(symptoms: nil, signals: 0.5) == 0.5)
        #expect(BodyBalance.combine(symptoms: nil, signals: nil) == nil)
    }

    @Test func lagWindow() {
        let dc = AnchoredDay(year: 2026, month: 9, day: 14)
        #expect(BodyBalance.isLagged(dc, doseChanges: [dc]))
        #expect(BodyBalance.isLagged(dc.adding(days: 35), doseChanges: [dc]))
        #expect(!BodyBalance.isLagged(dc.adding(days: 42), doseChanges: [dc]))
        #expect(!BodyBalance.isLagged(dc.adding(days: -14), doseChanges: [dc]))
    }

    @Test func describesMoveAroundDoseChange() {
        let start = AnchoredDay(year: 2026, month: 8, day: 3)
        let weeks = (0..<12).map { i in
            BodyBalance.Week(start: start.adding(days: 7 * i), index: i < 6 ? -0.4 : 0.35, hasCheck: true, lagged: false)
        }
        let text = BodyBalance.describe(weeks, doseChangeWeek: start.adding(days: 42))
        #expect(text.hasPrefix("How you felt moved from the lower side to the higher side"))
        #expect(text.contains("not a lab value"))
        for banned in ["increase your dose", "lower your dose", "you should", "diagnos"] {
            #expect(!text.lowercased().contains(banned))
        }
    }

    @Test func labCadence() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let dates = [0, 182, 360, 545].map { base.addingTimeInterval(Double($0) * 86400) }
        #expect(LabCadence.usualGapDays(dates) == 182)
        #expect(LabCadence.nextTypical(dates) == dates.last!.addingTimeInterval(182 * 86400))
        #expect(LabCadence.usualGapDays([base]) == nil)
    }

    @Test func gatedWithFewWeeks() {
        let w = [BodyBalance.Week(start: AnchoredDay(year: 2026, month: 10, day: 26), index: 0.2, hasCheck: true, lagged: false)]
        #expect(BodyBalance.describe(w, doseChangeWeek: nil).hasPrefix("Not yet"))
    }
}

@Suite struct LabGroupingTests {
    @Test @MainActor func groupsByReportThenByDay() {
        let d1 = Date(timeIntervalSince1970: 1_750_000_000), d2 = d1.addingTimeInterval(90 * 86400)
        let rid = UUID()
        func r(_ d: Date, _ m: String, _ id: UUID?) -> LabResult { let x = LabResult(date: d, marker: m); x.reportId = id; return x }
        let rows = [r(d1, "LDL", rid), r(d1, "GLU", rid), r(d2, "HGB", nil), r(d2, "GLU", nil)]
        let groups = LabReport.group(rows)
        #expect(groups.count == 2)
        #expect(groups[0].date == d2)
        #expect(groups[0].results.map(\.marker) == ["GLU", "HGB"])   // catalogue order
        #expect(groups[1].results.map(\.marker) == ["GLU", "LDL"])
    }

    @Test @MainActor func bodyCheckKeepsOneMapOfScores() {
        let c = BodyCheck(week: AnchoredDay(year: 2026, month: 10, day: 26))
        c.signs = ["Tired": 2, "Shaky": 1]
        #expect(BodySigns.scores(c.signs, in: BodySigns.lower) == ["Tired": 2])
        #expect(BodySigns.scores(c.signs, in: BodySigns.higher) == ["Shaky": 1])
        #expect(Set(BodySigns.lower).isDisjoint(with: BodySigns.higher))
    }
}

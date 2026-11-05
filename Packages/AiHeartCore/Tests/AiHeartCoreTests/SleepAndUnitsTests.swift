import Foundation
import Testing
@testable import AiHeartCore

@Suite struct LabUnitTests {
    @Test func everyMarkerHasUnitsAndWhereGivenASaneRange() {
        for m in LabMarkers.all {
            #expect(!m.units.isEmpty)
            #expect(m.plausible.lowerBound > 0)
            for t in m.typical { #expect(t.low < t.high); #expect(m.units.contains(t.unit)) }
            for u in m.units { #expect(LabMarkers.canonical(u) == u, "\(m.code) \(u)") }
        }
        #expect(Set(LabMarkers.all.map(\.code)).count == LabMarkers.all.count)
        // A broad catalogue, so no single marker stands out.
        #expect(LabMarkers.all.count >= 20)
        for code in ["GLU", "A1C", "TC", "LDL", "HDL", "TG", "HGB", "FER", "FE", "VITD", "B12", "FOL", "CRE", "EGFR", "ALT", "AST", "NA", "K", "CA", "CRP"] {
            #expect(LabMarkers.marker(code) != nil, "\(code)")
        }
    }

    @Test func canonicalAndDefault() {
        #expect(LabMarkers.canonical("uIU/ml") == "μIU/mL")
        #expect(LabMarkers.canonical("mg/d1") == "mg/dL")
        #expect(LabMarkers.canonical("ml/min/1.73m2") == "mL/min/1.73m²")
        #expect(LabMarkers.defaultUnit("FT4", previous: ["ng/dl"]) == "ng/dL")
        #expect(LabMarkers.defaultUnit("FT3", previous: []) == "pmol/L")
        #expect(LabMarkers.defaultUnit("GLU", previous: ["mmol/l"]) == "mmol/L")
    }

    @Test @MainActor func labRangeWinsOverTypical() {
        let l = LabResult(date: .now, marker: "TSH")
        l.value = 2; l.unit = "mIU/L"
        #expect(l.shownRange! == (0.4, 4.0, false))
        l.low = 0.35; l.high = 4.94
        #expect(l.shownRange! == (0.35, 4.94, true))
        // No default range for a marker without one; only the report's own is shown.
        let g = LabResult(date: .now, marker: "GLU")
        g.value = 5; g.unit = "mmol/L"
        #expect(g.shownRange == nil)
        g.low = 3.9; g.high = 5.5
        #expect(g.shownRange! == (3.9, 5.5, true))
    }
}

@Suite struct SleepCheckInTests {
    let tz = TimeZone(identifier: "Asia/Tokyo")!

    @Test func minutesAcrossMidnight() {
        let d = SleepCheckIn.dates(wakeDay: AnchoredDay(year: 2026, month: 11, day: 1), bedMinute: 23 * 60 + 30, wakeMinute: 7 * 60, timeZone: tz)
        #expect(SleepCheckIn.minutes(bed: d.bed, wake: d.wake) == 450)
        #expect(SleepMath.wakeDay(end: d.wake, timeZone: tz) == AnchoredDay(year: 2026, month: 11, day: 1))
    }

    @Test func bedAfterMidnightSameMorning() {
        let d = SleepCheckIn.dates(wakeDay: AnchoredDay(year: 2026, month: 11, day: 1), bedMinute: 60, wakeMinute: 8 * 60, timeZone: tz)
        #expect(SleepCheckIn.minutes(bed: d.bed, wake: d.wake) == 420)
    }

    @Test func usualHandlesMidnight() {
        let u = SleepCheckIn.usual(bedMinutes: [23 * 60 + 30, 30, 23 * 60 + 45], wakeMinutes: [420, 450, 435])
        #expect(u.bed == 23 * 60 + 45)
        #expect(u.wake == 435)
        #expect(SleepCheckIn.usual(bedMinutes: [], wakeMinutes: []) == (23 * 60, 7 * 60))
    }

    @Test func regionRanges() {
        #expect(LabMarkers.typicalRange("TSH", unit: "μIU/mL", region: .japan)! == (0.50, 5.00))
        #expect(LabMarkers.typicalRange("FT4", unit: "ng/dl", region: .japan)! == (0.90, 1.70))
        #expect(LabMarkers.typicalRange("FT3", unit: "pg/mL", region: .japan)! == (2.30, 4.00))
        #expect(LabMarkers.typicalRange("TSH", unit: "mIU/L", region: .philippines)! == (0.27, 4.20))
        #expect(LabMarkers.typicalRange("FT4", unit: "pmol/L", region: .philippines)! == (12, 22))
        #expect(LabMarkers.typicalRange("FT3", unit: "pmol/L", region: .philippines)! == (3.1, 6.8))
        #expect(LabMarkers.typicalRange("TSH", unit: "mIU/L", region: .elsewhere)! == (0.4, 4.0))
        for region in LabRegion.allCases { for code in ["TSH", "FT4", "FT3"] { for u in LabMarkers.marker(code)!.units {
            let r = LabMarkers.typicalRange(code, unit: u, region: region)!
            #expect(r.0 < r.1)
        } } }
        #expect(LabRegion.guess(previous: [nil, "philippines"], localeRegion: "JP") == .philippines)
        #expect(LabRegion.guess(previous: [], localeRegion: "JP") == .japan)
        let l = LabResult(date: .now, marker: "TSH"); l.value = 3; l.unit = "μIU/mL"; l.labRegion = .japan
        #expect(l.shownRange! == (0.50, 5.00, false))
    }
}

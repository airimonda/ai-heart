import Foundation
import Testing
@testable import AiHeartCore

// Synthetic report text only. [synthetic]

@Suite struct LabMarkerParserTests {
    static let now: Date = {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current
        return c.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    }()

    @Test func readsSeveralMarkersFromOneReport() {
        let r = LabParser.parse(lines: [
            "[synthetic] SAMPLE LAB",
            "Collected: 2026/10/20",
            "Glucose 5.2 mmol/L 3.9-5.5",
            "HbA1c 5.4 % 4.0-5.6",
            "Total Cholesterol 190 mg/dL 125-200",
            "LDL Cholesterol 110 mg/dL 0-130",
            "HDL Cholesterol 58 mg/dL 40-100",
            "Triglycerides 90 mg/dL 0-150",
            "Hemoglobin 13.1 g/dL 12.0-15.5",
            "Ferritin 45 ng/mL 10-120",
            "Vitamin D 32 ng/mL 30-100",
            "Creatinine 0.8 mg/dL 0.5-1.0",
            "eGFR 92 mL/min/1.73m2",
            "ALT 18 U/L 7-35",
            "AST 20 U/L 8-30",
            "Sodium 140 mmol/L 135-145",
            "Potassium 4.1 mmol/L 3.5-5.0",
            "Calcium 9.4 mg/dL 8.6-10.2",
            "CRP 0.6 mg/L 0-5",
        ], now: Self.now)
        #expect(r["GLU"] == .init(value: 5.2, unit: "mmol/L", low: 3.9, high: 5.5))
        #expect(r["A1C"] == .init(value: 5.4, unit: "%", low: 4.0, high: 5.6))
        #expect(r["TC"] == .init(value: 190, unit: "mg/dL", low: 125, high: 200))
        #expect(r["LDL"]?.value == 110)
        #expect(r["HDL"]?.value == 58)
        #expect(r["TG"]?.value == 90)
        #expect(r["HGB"] == .init(value: 13.1, unit: "g/dL", low: 12.0, high: 15.5))
        #expect(r["FER"] == .init(value: 45, unit: "ng/mL", low: 10, high: 120))
        #expect(r["VITD"]?.value == 32)
        #expect(r["CRE"]?.value == 0.8)
        #expect(r["EGFR"] == .init(value: 92, unit: "mL/min/1.73m²", low: nil, high: nil))
        #expect(r["ALT"] == .init(value: 18, unit: "U/L", low: 7, high: 35))
        #expect(r["AST"]?.value == 20)
        #expect(r["NA"]?.value == 140)
        #expect(r["K"]?.value == 4.1)
        #expect(r["CA"]?.value == 9.4)
        #expect(r["CRP"]?.value == 0.6)
        #expect(r.values.count == 17)
    }

    @Test func japaneseLabels() {
        let r = LabParser.parse(lines: [
            "採血日 2026年10月20日",
            "血糖 92 mg/dL 70-109",
            "ヘモグロビンA1c 5.4 % 4.6-6.2",
            "LDLコレステロール 110 mg/dL 70-139",
            "中性脂肪 90 mg/dL 30-149",
            "ヘモグロビン 13.1 g/dL 11.6-14.8",
            "フェリチン 45 ng/mL 5-157",
            "クレアチニン 0.7 mg/dL 0.46-0.79",
        ], now: Self.now)
        #expect(r["GLU"]?.value == 92)
        #expect(r["A1C"]?.value == 5.4)
        #expect(r["LDL"]?.value == 110)
        #expect(r["TG"]?.value == 90)
        #expect(r["HGB"]?.value == 13.1)
        #expect(r["FER"]?.value == 45)
        #expect(r["CRE"]?.value == 0.7)
    }

    @Test func similarNamesDoNotCrossOver() {
        // Hb A1c is not hemoglobin; non-HDL and ratios are not HDL; clearance is not creatinine.
        let r = LabParser.parse(lines: ["Hb A1c 5.4 %", "Non-HDL cholesterol 130 mg/dL", "LDL/HDL ratio 1.9", "Creatinine clearance 95 mL/min"], now: Self.now)
        #expect(r["A1C"]?.value == 5.4)
        #expect(r["HGB"] == nil)
        #expect(r["HDL"] == nil)
        #expect(r["CRE"] == nil)
    }

    @Test func wordsInsideOtherWordsAreNotLabels() {
        let r = LabParser.parse(lines: ["Specimen collected 2026/10/20", "Fasting 12 hours", "Salt 3", "Last meal 2 h ago"], now: Self.now)
        #expect(r.isEmpty)
    }

    @Test(arguments: [
        ("mg/dL", "mg/dL"), ("mg/d1", "mg/dL"), ("mmol/L", "mmol/L"), ("mmo1/L", "mmol/L"), ("g/dL", "g/dL"),
        ("ug/dL", "μg/dL"), ("μg/dL", "μg/dL"), ("U/L", "U/L"), ("IU/L", "U/L"), ("mg/L", "mg/L"), ("%", "%"),
    ])
    func unitSpellings(spelling: String, canonical: String) {
        let found = LabParser.unitMatches(in: "5.0 \(spelling) 1-9").map(\.unit)
        #expect(found == [canonical])
        #expect(LabMarkers.canonical(spelling) == canonical)
    }

    @Test func guessUnitFromMagnitude() {
        #expect(LabParser.guessUnit(code: "GLU", value: 5.2) == "mmol/L")
        #expect(LabParser.guessUnit(code: "GLU", value: 92) == "mg/dL")
        #expect(LabParser.guessUnit(code: "A1C", value: 5.4) == "%")
        #expect(LabParser.guessUnit(code: "A1C", value: 36) == "mmol/mol")
        #expect(LabParser.guessUnit(code: "HGB", value: 131) == "g/L")
    }
}

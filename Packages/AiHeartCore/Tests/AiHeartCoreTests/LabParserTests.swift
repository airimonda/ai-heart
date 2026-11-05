import Foundation
import CoreGraphics
import Testing
@testable import AiHeartCore

// Synthetic report text only.

@Suite struct LabParserTests {
    func ymd(_ d: Date?) -> String? {
        d.map { let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: $0); return "\(c.year!)-\(c.month!)-\(c.day!)" }
    }

    @Test func englishSameLine() {
        let r = LabParser.parse(lines: [
            "SYNTHETIC LAB",
            "Collected: 16 Oct 2026 08:10",
            "TSH 2.31 mIU/L 0.35 - 4.94",
            "Free T4 (free thyroxine) 15.8 pmol/L 9.0-19.0",
            "Free T3 4.9 H pmol/L 2.6-5.7",
        ])
        #expect(r["TSH"] == .init(value: 2.31, unit: "mIU/L", low: 0.35, high: 4.94))
        #expect(r["FT4"] == .init(value: 15.8, unit: "pmol/L", low: 9.0, high: 19.0))
        #expect(r["FT3"]?.value == 4.9)
        #expect(ymd(r.date) == "2026-10-16")
    }

    @Test func japaneseReport() {
        let r = LabParser.parse(lines: [
            "検査結果報告書（サンプル）",
            "採血日 2026年12月18日",
            "甲状腺刺激ホルモン（TSH） 1,25 μIU/mL 0.50〜5.00",
            "FT4（遊離サイロキシン） １.３２ ng/dL 0.90〜1.70",
            "遊離T3 3.1 pg/mL 2.3〜4.0",
        ])
        #expect(r["TSH"]?.value == 1.25)
        #expect(r["TSH"]?.unit == "μIU/mL")
        #expect(r["TSH"]?.low == 0.5 && r["TSH"]?.high == 5.0)
        #expect(r["FT4"]?.value == 1.32)
        #expect(r["FT4"]?.unit == "ng/dL")
        #expect(r["FT3"]?.value == 3.1)
        #expect(ymd(r.date) == "2026-12-18")
    }

    @Test func tableLayoutValueOnNextLine() {
        let r = LabParser.parse(lines: ["Test date 2026-04-02", "TSH", "3.8 mIU/L", "FT4", "12.1 pmol/L"])
        #expect(r["TSH"]?.value == 3.8)
        #expect(r["FT4"]?.value == 12.1)
        #expect(ymd(r.date) == "2026-4-2")
    }

    @Test func freeT4LineIsNotTakenAsTSH() {
        let r = LabParser.parse(lines: ["FT4 14.2 pmol/L", "TSH 0.9 mIU/L"])
        #expect(r["TSH"]?.value == 0.9)
        #expect(r["FT4"]?.value == 14.2)
    }

    @Test func nothingFound() {
        let r = LabParser.parse(lines: ["Albumin 4.1 g/dL", "Total protein 7.0 g/dL", "Name: SYNTHETIC", "Page 1 of 2"])
        #expect(r.isEmpty)
    }

    @Test func prefersHintedDate() {
        let r = LabParser.parse(lines: ["Printed 01/11/2026", "Specimen collected 28/10/2026", "TSH 2 mIU/L"])
        #expect(ymd(r.date) == "2026-10-28")
    }

    // MARK: Ranges (all strings synthetic)

    /// Fixed "today" so date rules do not depend on the clock.
    static let now: Date = {
        var c = Calendar(identifier: .gregorian); c.timeZone = .current
        return c.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    }()

    @Test(arguments: [
        ("TSH 2.31 mIU/L 0.50-5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L 0.50 - 5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L 0.50～5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L 0.50〜5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L 0.50–5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L 0.50—5.00", 0.5, 5.0),
        ("TSH 2.31 mIU/L (0.27 - 4.20)", 0.27, 4.2),
        ("TSH 2.31 mIU/L [0.9-1.7]", 0.9, 1.7),
        ("TSH 2.31 mIU/L 0.27 to 4.20", 0.27, 4.2),
        ("TSH 2.31 mIU/L 0.27 TO 4.20", 0.27, 4.2),
        ("TSH 2.31 0.27-4.20 mIU/L", 0.27, 4.2),            // range before the unit
        ("TSH 2.31 (0.27-4.20) mIU/L", 0.27, 4.2),
        ("TSH 2.31 mIU/L (Ref: 0.27-4.20)", 0.27, 4.2),
        ("TSH 2,31 mIU/L 0,27-4,20", 0.27, 4.2),            // comma decimals
        ("TSH ２.３１ ｍIU/L ０.２７－４.２０", 0.27, 4.2),   // full-width
        ("TSH  2.31  mIU/L  0.27 - 4.20", 0.27, 4.2),       // cells joined by spaces
        ("TSH\t2.31\tmIU/L\t0.27-4.20", 0.27, 4.2),
    ])
    func rangeForms(row: String, lo: Double, hi: Double) {
        let r = LabParser.parse(lines: [row], now: Self.now)
        #expect(r["TSH"]?.value == 2.31)
        #expect(r["TSH"]?.low == lo)
        #expect(r["TSH"]?.high == hi)
    }

    @Test(arguments: [
        "TSH 5.80 H mIU/L 0.50-5.00",
        "TSH H 5.80 mIU/L 0.50-5.00",
        "TSH 5.80H mIU/L 0.50-5.00",
        "TSH 5.80 * mIU/L 0.50-5.00",
        "TSH 5.80 ↑ mIU/L 0.50-5.00",
        "TSH 5.80 (H) mIU/L 0.50-5.00",
        "TSH 5.80 High mIU/L 0.50-5.00",
        "TSH 5.80 mIU/L 0.50-5.00 H",
        "TSH 5.80 mIU/L H 0.50-5.00",
        "TSH 5.80 高 mIU/L 0.50-5.00",
    ])
    func flagsAreNotValuesOrRanges(row: String) {
        let r = LabParser.parse(lines: [row], now: Self.now)
        #expect(r["TSH"] == .init(value: 5.8, unit: "mIU/L", low: 0.5, high: 5.0))
    }

    @Test func lowFlagOnT4() {
        let r = LabParser.parse(lines: ["Free T4 L 0.62 ng/dL 0.80-1.80"], now: Self.now)
        #expect(r["FT4"] == .init(value: 0.62, unit: "ng/dL", low: 0.8, high: 1.8))
    }

    @Test func rangeWithoutValueIsNotAValue() {
        let r = LabParser.parse(lines: ["TSH mIU/L 0.50-5.00"], now: Self.now)
        #expect(r["TSH"] == nil)
    }

    @Test func rangeBeforeValue() {
        let r = LabParser.parse(lines: ["TSH [0.50-5.00] 2.31 mIU/L"], now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "mIU/L", low: 0.5, high: 5.0))
    }

    @Test func dateInRowIsNotAValue() {
        let r = LabParser.parse(lines: ["TSH 2.31 mIU/L 0.50-5.00 2026/10/31 08:10"], now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "mIU/L", low: 0.5, high: 5.0))
    }

    // MARK: Units

    @Test(arguments: [
        ("μIU/mL", "μIU/mL"), ("uIU/mL", "μIU/mL"), ("µIU/ml", "μIU/mL"), ("ulU/mL", "μIU/mL"),
        ("μlU/mL", "μIU/mL"), ("uIU/m L", "μIU/mL"), ("u1u/ml", "μIU/mL"), ("μU/mL", "μIU/mL"),
        ("mIU/L", "mIU/L"), ("mU/L", "mIU/L"), ("mlU/L", "mIU/L"), ("MIU/L", "mIU/L"),
    ])
    func tshUnits(spelling: String, canonical: String) {
        let r = LabParser.parse(lines: ["TSH 2.31 \(spelling) 0.50-5.00"], now: Self.now)
        #expect(r["TSH"]?.unit == canonical)
        #expect(r["TSH"]?.value == 2.31)
        #expect(r["TSH"]?.low == 0.5)
        // The picker's own spelling agrees with the parser's.
        #expect(LabMarkers.canonical(spelling) == canonical)
    }

    @Test(arguments: [
        ("Free T4", "ng/dL", "ng/dL"), ("Free T4", "ng/dl", "ng/dL"), ("Free T4", "ng/d L", "ng/dL"),
        ("Free T4", "pmol/L", "pmol/L"), ("Free T4", "pmol/l", "pmol/L"), ("Free T4", "pmo1/L", "pmol/L"),
        ("Free T3", "pg/mL", "pg/mL"), ("Free T3", "pg/ml", "pg/mL"), ("Free T3", "pg/m1", "pg/mL"),
        ("Free T3", "pmol/L", "pmol/L"),
    ])
    func freeUnits(label: String, spelling: String, canonical: String) {
        let r = LabParser.parse(lines: ["\(label) 3.10 \(spelling) 2.30-4.20"], now: Self.now)
        let v = label == "Free T4" ? r["FT4"] : r["FT3"]
        #expect(v?.unit == canonical)
        #expect(v?.value == 3.1)
        #expect(v?.high == 4.2)
        #expect(LabMarkers.canonical(spelling) == canonical)
    }

    @Test func unitInOwnColumnAndNoUnit() {
        let own = LabParser.parse(lines: ["FT4", "1.32", "ng/dL", "0.90-1.70"], now: Self.now)
        #expect(own["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
        let none = LabParser.parse(lines: ["TSH 2.31 0.50-5.00"], now: Self.now)
        #expect(none["TSH"] == .init(value: 2.31, unit: nil, low: 0.5, high: 5.0))
        let bare = LabParser.parse(lines: ["TSH 2.31"], now: Self.now)
        #expect(bare["TSH"] == .init(value: 2.31, unit: nil, low: nil, high: nil))
    }

    @Test func unitInParenthesesAfterLabel() {
        let r = LabParser.parse(lines: ["Free T4 (pmol/L) 15.8 9.0-19.0"], now: Self.now)
        #expect(r["FT4"] == .init(value: 15.8, unit: "pmol/L", low: 9.0, high: 19.0))
    }

    @Test func guessUnitFromMagnitude() {
        #expect(LabParser.guessUnit(code: "TSH", value: 2.3) == "μIU/mL")
        #expect(LabParser.guessUnit(code: "FT4", value: 1.2) == "ng/dL")
        #expect(LabParser.guessUnit(code: "FT4", value: 15.8) == "pmol/L")
        #expect(LabParser.guessUnit(code: "FT3", value: 3.1) == "pg/mL")
        #expect(LabParser.guessUnit(code: "FT3", value: 5.4) == "pg/mL")
        #expect(LabParser.guessUnit(code: "FT3", value: 5.5) == "pmol/L")
        #expect(LabParser.guessUnit(code: "FT3", value: 9.0) == "pmol/L")
    }

    // MARK: Labels

    @Test(arguments: [
        "TSH", "tsh", "TSH (3rd generation)", "Thyrotropin", ["Thy", "roid Stimulating Hormone"].joined(), "甲状腺刺激ホルモン", "甲状腺刺激ホルモン（TSH）", "TSH:",
    ])
    func tshLabels(label: String) {
        let r = LabParser.parse(lines: ["\(label) 2.31 mIU/L 0.50-5.00"], now: Self.now)
        #expect(r["TSH"]?.value == 2.31)
        #expect(r["TSH"]?.unit == "mIU/L")
        #expect(r["TSH"]?.high == 5.0)
        #expect(r["FT4"] == nil && r["FT3"] == nil)
    }

    @Test(arguments: [
        "Free T4", "FREE T4", "Free-T4", "FT4", "F-T4", "FT-4", "FT 4", "遊離T4", "遊離 T4", "遊離サイロキシン", "遊離サイロキシン（FT4）",
        "FT4 (Free Thyroxine)", "Thyroxine, Free", "Free Thyroxine (T4)", "T4, Free", "ＦＴ４", "fT4:",
    ])
    func freeT4Labels(label: String) {
        let r = LabParser.parse(lines: ["\(label) 1.32 ng/dL 0.90-1.70"], now: Self.now)
        #expect(r["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
        #expect(r["TSH"] == nil && r["FT3"] == nil)
    }

    @Test(arguments: [
        "Free T3", "FREE T3", "Free-T3", "FT3", "F-T3", "FT-3", "遊離T3", "遊離トリヨードサイロニン", "遊離トリヨードサイロニン（FT3）",
        "FT3 (Free Triiodothyronine)", "Triiodothyronine, Free", "T3, Free",
    ])
    func freeT3Labels(label: String) {
        let r = LabParser.parse(lines: ["\(label) 3.10 pg/mL 2.30-4.00"], now: Self.now)
        #expect(r["FT3"] == .init(value: 3.1, unit: "pg/mL", low: 2.3, high: 4.0))
        #expect(r["TSH"] == nil && r["FT4"] == nil)
    }

    @Test func totalT4IsIgnoredWhenBothAppear() {
        let r = LabParser.parse(lines: [
            "T4 8.20 ug/dL 4.5-12.0",
            "Total T4 7.90 ug/dL 4.5-12.0",
            "Thyroxine (T4) 8.0 ug/dL",
            "Free T4 1.32 ng/dL 0.90-1.70",
            "T3 110 ng/dL 80-200",
            "Free T3 3.1 pg/mL 2.3-4.0",
        ], now: Self.now)
        #expect(r["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
        #expect(r["FT3"] == .init(value: 3.1, unit: "pg/mL", low: 2.3, high: 4.0))
        // Only total T4 present: nothing is read as free T4.
        let only = LabParser.parse(lines: ["T4 8.20 ug/dL 4.5-12.0", "総T4 8.0 μg/dL"], now: Self.now)
        #expect(only.isEmpty)
    }

    @Test func otherTestsWithSimilarNamesAreIgnored() {
        let r = LabParser.parse(lines: [
            "TSH receptor antibody 0.8 IU/L",
            "Anti-TPO 12 IU/mL",
            "Free T4 index 1.9",
            "抗TSHレセプター抗体 0.9",
        ], now: Self.now)
        #expect(r.isEmpty)
    }

    @Test func twoAnalytesInOneRow() {
        let r = LabParser.parse(lines: ["TSH 2.31 mIU/L 0.50-5.00   FT4 1.32 ng/dL 0.90-1.70"], now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "mIU/L", low: 0.5, high: 5.0))
        #expect(r["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
    }

    @Test func rowSplitOverLines() {
        let r = LabParser.parse(lines: [
            "TSH", "2.31", "μIU/mL", "0.50-5.00",
            "Free T4", "15.8 H", "pmol/L", "(9.0 - 19.0)",
            "Ferritin", "45",
        ], now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "μIU/mL", low: 0.5, high: 5.0))
        #expect(r["FT4"] == .init(value: 15.8, unit: "pmol/L", low: 9.0, high: 19.0))
        #expect(r["FT3"] == nil)
    }

    @Test func rawLinesAfterRowsOnlyFillGaps() {
        let r = LabParser.parse(lines: [
            "TSH  2.31  mIU/L", "",
            "TSH", "2.31", "0.50-5.00",
        ], now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "mIU/L", low: 0.5, high: 5.0))
    }

    // MARK: Dates

    @Test(arguments: [
        "Collected: 2026/10/31", "Collected: 2026-10-31", "Collected: 2026.10.31", "Collected: 2026年10月31日",
        "Collected: 2026年10月31日 08:15", "採血日 令和8年10月31日", "採取日 R8.10.31", "採取日 R08.10.31",
        "Collected: Oct 31, 2026", "Collected: 31 Oct 2026", "Collected: October 31, 2026", "Collected: 31 October 2026 08:10",
        "Collected: 31-Oct-2026", "Collected: 10/31/2026", "Collected: 10/31/2026 08:10 AM", "Collected: 31/10/2026",
        "Collected: 2026-10-31T08:10:00", "Date collected: 2026／10／31", "Collection date: 31.10.2026", "検査日：２０２６年１０月３１日",
    ])
    func dateFormats(line: String) {
        let r = LabParser.parse(lines: [line, "TSH 2.31 mIU/L"], now: Self.now)
        #expect(ymd(r.date) == "2026-10-31")
    }

    @Test func reiwaYearOne() {
        let r = LabParser.parse(lines: ["検査日 令和元年5月1日", "TSH 2.31 mIU/L"], now: Self.now)
        #expect(ymd(r.date) == "2019-5-1")
        let h = LabParser.parse(lines: ["検査日 平成31年4月30日", "TSH 2.31 mIU/L"], now: Self.now)
        #expect(ymd(h.date) == "2019-4-30")
    }

    @Test func slashDatesAreMonthFirstUnlessImpossible() {
        #expect(ymd(LabParser.parse(lines: ["Date of test 03/04/2026", "TSH 2 mIU/L"], now: Self.now).date) == "2026-3-4")
        #expect(ymd(LabParser.parse(lines: ["Date of test 13/04/2026", "TSH 2 mIU/L"], now: Self.now).date) == "2026-4-13")
        #expect(ymd(LabParser.parse(lines: ["Date of test 04/13/2026", "TSH 2 mIU/L"], now: Self.now).date) == "2026-4-13")
        // Month first (Dec 10) would be after today (2026-11-01); day first (Oct 12) is not.
        #expect(ymd(LabParser.parse(lines: ["Collected 12/10/2026", "TSH 2 mIU/L"], now: Self.now).date) == "2026-10-12")
    }

    @Test(arguments: [
        "Collection date: 2026/10/31", "Date collected 2026/10/31", "Specimen collected 2026/10/31", "Specimen: 2026/10/31",
        "Date of test: 2026/10/31", "Result date 2026/10/31", "Reported: 2026/10/31", "Report date 2026/10/31",
        "採取日 2026/10/31", "採血日 2026/10/31", "検査日 2026/10/31", "受付日 2026/10/31", "報告日 2026/10/31",
    ])
    func dateKeywordsWin(line: String) {
        let r = LabParser.parse(lines: ["Printed 2026/11/01", "DOB 1990/01/02", "Next visit 2026/10/20", line, "TSH 2 mIU/L"], now: Self.now)
        #expect(ymd(r.date) == "2026-10-31")
    }

    @Test func collectionBeatsReportedAndPrinted() {
        let r = LabParser.parse(lines: [
            "Printed: Nov 1, 2026",
            "Reported: 2026/10/31",
            "Collected: 2026/10/29",
            "Received: 2026/10/30",
            "TSH 2 mIU/L",
        ], now: Self.now)
        #expect(ymd(r.date) == "2026-10-29")
        let japanese = LabParser.parse(lines: ["報告日 2026年10月31日", "採血日 2026年10月29日"], now: Self.now)
        #expect(ymd(japanese.date) == "2026-10-29")
    }

    @Test func twoKeywordsInOneRow() {
        let r = LabParser.parse(lines: ["Collected 10/29/2026  Reported 10/31/2026"], now: Self.now)
        #expect(ymd(r.date) == "2026-10-29")
        let rev = LabParser.parse(lines: ["Reported 10/31/2026  Collected 10/29/2026"], now: Self.now)
        #expect(ymd(rev.date) == "2026-10-29")
    }

    @Test func birthDatesAreIgnored() {
        let r = LabParser.parse(lines: [
            "Birthdate: 03/04/1990", "Date of Birth 1990-03-04", "DOB: 04/03/1990", "生年月日 1990年3月4日", "Name: SYNTHETIC",
            "TSH 2 mIU/L",
        ], now: Self.now)
        #expect(r.date == nil)
        let withDate = LabParser.parse(lines: ["DOB 2001/05/06  Collected 2026/10/31"], now: Self.now)
        #expect(ymd(withDate.date) == "2026-10-31")
        // A recent-looking birth date (a young patient) must not become the result date.
        let young = LabParser.parse(lines: ["Birth date 2020/01/01", "Collected 2026/10/31"], now: Self.now)
        #expect(ymd(young.date) == "2026-10-31")
    }

    @Test func unhintedDateIsLatestNotInTheFuture() {
        let r = LabParser.parse(lines: ["2026/10/01", "2026/10/20 08:10", "2027/03/01", "TSH 2 mIU/L"], now: Self.now)
        #expect(ymd(r.date) == "2026-10-20")
        let none = LabParser.parse(lines: ["2027/03/01"], now: Self.now)
        #expect(none.date == nil)
    }

    @Test func printDateIsLastResort() {
        let only = LabParser.parse(lines: ["Printed 2026/10/31"], now: Self.now)
        #expect(ymd(only.date) == "2026-10-31")
        let both = LabParser.parse(lines: ["Printed 2026/10/31", "2026/10/20"], now: Self.now)
        #expect(ymd(both.date) == "2026-10-20")
    }

    @Test func keywordAtEndOfLineTakesDateFromNextLine() {
        let r = LabParser.parse(lines: ["Printed 2026/11/01", "Date collected", "2026/10/28", "TSH 2 mIU/L"], now: Self.now)
        #expect(ymd(r.date) == "2026-10-28")
        // A title that merely contains a keyword does not claim a later date.
        let title = LabParser.parse(lines: ["検査結果報告書（サンプル）", "2026/10/20", "Printed 2026/11/01"], now: Self.now)
        #expect(ymd(title.date) == "2026-10-20")
    }

    // MARK: Values

    @Test func fullWidthAndCommaDecimals() {
        let r = LabParser.parse(lines: [
            "ＴＳＨ １,２５ μＩＵ/ｍＬ ０.５０～５.００",
            "ＦＴ４ １.３２ ｎｇ/ｄＬ ０.９０～１.７０",
            "遊離Ｔ３ ３，１ ｐｇ/ｍＬ ２.３～４.０",
        ], now: Self.now)
        #expect(r["TSH"] == .init(value: 1.25, unit: "μIU/mL", low: 0.5, high: 5.0))
        #expect(r["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
        #expect(r["FT3"] == .init(value: 3.1, unit: "pg/mL", low: 2.3, high: 4.0))
    }

    // MARK: Whole screenshot, rows built from cell boxes (synthetic)

    /// A phone screenshot of a table: each cell is its own observation, listed column by
    /// column the way Vision tends to return them.
    @Test func columnOrderObservationsBecomeRows() {
        func box(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 0.15) -> CGRect { CGRect(x: x, y: y, width: w, height: 0.02) }
        let items: [(String, CGRect)] = [
            ("Collected: 10/31/2026 08:10", box(0.05, 0.90, w: 0.5)),
            ("Test", box(0.05, 0.80)), ("TSH", box(0.05, 0.75)), ("Free T4", box(0.05, 0.70)), ("Free T3", box(0.05, 0.65)),
            ("Result", box(0.30, 0.80)), ("2.31", box(0.30, 0.752)), ("1.32 H", box(0.30, 0.699)), ("3.1", box(0.30, 0.651)),
            ("Unit", box(0.50, 0.80)), ("uIU/mL", box(0.50, 0.75)), ("ng/dl", box(0.50, 0.70)), ("pg/m L", box(0.50, 0.65)),
            ("Reference", box(0.70, 0.80)), ("0.50 - 5.00", box(0.70, 0.75)), ("[0.90-1.70]", box(0.70, 0.70)), ("2.3～4.0", box(0.70, 0.65)),
        ]
        let rows = LabOCR.rows(from: items)
        #expect(rows.contains { $0.hasPrefix("TSH") && $0.contains("2.31") && $0.contains("uIU/mL") && $0.contains("0.50 - 5.00") })
        // Raw order alone would not find the units or ranges.
        let r = LabParser.parse(lines: LabOCR.combined(items), now: Self.now)
        #expect(r["TSH"] == .init(value: 2.31, unit: "μIU/mL", low: 0.5, high: 5.0))
        #expect(r["FT4"] == .init(value: 1.32, unit: "ng/dL", low: 0.9, high: 1.7))
        #expect(r["FT3"] == .init(value: 3.1, unit: "pg/mL", low: 2.3, high: 4.0))
        #expect(ymd(r.date) == "2026-10-31")
    }
}

@Suite struct LabOCRRowTests {
    func box(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 0.1, h: CGFloat = 0.02) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

    @Test func groupsByVerticalOverlapSortsLeftToRightTopToBottom() {
        let rows = LabOCR.rows(from: [
            ("mIU/L", box(0.5, 0.500)), ("TSH", box(0.1, 0.502)), ("2.31", box(0.3, 0.499)),
            ("FT4", box(0.1, 0.400)), ("1.3", box(0.3, 0.401)),
            ("Header", box(0.1, 0.800)),
        ])
        #expect(rows == ["Header", "TSH  2.31  mIU/L", "FT4  1.3"])
    }

    @Test func separateRowsStaySeparate() {
        // Vertical centres 0.03 apart with 0.02 tall boxes: different lines.
        let rows = LabOCR.rows(from: [("A", box(0.1, 0.50)), ("B", box(0.1, 0.47)), ("C", box(0.3, 0.50))])
        #expect(rows == ["A  C", "B"])
    }

    @Test func slightlyUnevenBoxesStillShareARow() {
        // Centre offset 0.006 is below half of the 0.02 height.
        let rows = LabOCR.rows(from: [("TSH", box(0.1, 0.500)), ("2.3", box(0.3, 0.506, h: 0.018))])
        #expect(rows == ["TSH  2.3"])
    }

    @Test func emptyAndBlankInput() {
        #expect(LabOCR.rows(from: []).isEmpty)
        #expect(LabOCR.rows(from: [("  ", box(0.1, 0.5))]).isEmpty)
        #expect(LabOCR.combined([]).isEmpty)
    }

    @Test func combinedKeepsRawLinesAfterRows() {
        let out = LabOCR.combined([("TSH", box(0.1, 0.5)), ("2.3", box(0.4, 0.5)), ("Date", box(0.1, 0.9))])
        #expect(out == ["Date", "TSH  2.3", "", "TSH", "2.3", "Date"])
    }

    // Owner report 2026-11-01: free T4 read as a five-digit number. Synthetic rows with codes.
    @Test func ignoresCodesAndIDsOnTheRow() {
        let r = LabParser.parse(lines: [
            "10432  FT4  1.04  ng/dL  0.90-1.70",
            "TSH  10211  2.15  μIU/mL  0.50-5.00",
            "FT3  3.1  pg/mL  2.30-4.00  No. 20451",
        ])
        #expect(r["FT4"]?.value == 1.04)
        #expect(r["TSH"]?.value == 2.15)
        #expect(r["FT3"]?.value == 3.1)
        let p = LabParser.parse(lines: ["Free T4  12345  4  pmol/L  12-22"])
        #expect(p["FT4"]?.value == 4)
    }
}

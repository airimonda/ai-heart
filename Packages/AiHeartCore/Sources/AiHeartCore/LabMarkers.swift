import Foundation

/// One kind of lab result she can record or have read from a report.
/// The catalogue is data: the parser, the add and edit screen, the charts and the exports
/// all take their markers, aliases, units and typical ranges from here.
public struct LabMarker: Sendable, Identifiable {
    /// Typical adult range for one unit, optionally for labs in one region.
    public struct Typical: Sendable, Equatable {
        public let region: LabRegion?
        public let unit: String
        public let low: Double
        public let high: Double
        public init(_ region: LabRegion?, _ unit: String, _ low: Double, _ high: Double) {
            self.region = region; self.unit = unit; self.low = low; self.high = high
        }
    }

    /// Short stable code, stored on each result ("GLU", "LDL"...).
    public let code: String
    public let name: String
    /// Label spellings as they appear on reports: case-insensitive regexes run on
    /// normalized text, English and Japanese. Keep them anchored so short codes
    /// do not match inside other words.
    public let aliases: [String]
    /// Units she can pick, canonical spelling, first is the default.
    public let units: [String]
    /// Values a report could show for this marker in any of its units. Wide on purpose.
    public let plausible: ClosedRange<Double>
    /// Extra label words to drop from a row before the number is read.
    public let leftovers: [String]
    /// Typical adult ranges, used only when the report printed none.
    public let typical: [Typical]
    /// Suggests a unit from the size of a number when the image showed none.
    public let guessUnit: @Sendable (Double) -> String

    public var id: String { code }

    init(_ code: String, _ name: String, aliases: [String], units: [String], plausible: ClosedRange<Double>,
         leftovers: [String] = [], typical: [Typical] = [], guess: (@Sendable (Double) -> String)? = nil) {
        self.code = code; self.name = name; self.aliases = aliases; self.units = units
        self.plausible = plausible; self.leftovers = leftovers; self.typical = typical
        let first = units[0]
        self.guessUnit = guess ?? { _ in first }
    }
}

public enum LabMarkers {
    /// The catalogue, in the order the screens list it.
    public static let all: [LabMarker] = [
        LabMarker("GLU", "Glucose",
                  aliases: ["(?<![a-z])(?:fasting[\\s\\-]*)?(?:blood[\\s\\-]*)?glucose(?![a-z])", "(?<![a-z])fbs(?![a-z])", "血糖", "グルコース"],
                  units: ["mg/dL", "mmol/L"], plausible: 1...2000,
                  guess: { $0 < 40 ? "mmol/L" : "mg/dL" }),
        LabMarker("A1C", "HbA1c",
                  aliases: ["(?<![a-z])hb[\\s\\-]*a1c(?![a-z0-9])", "glycated[\\s\\-]*h(?:a)?emoglobin", "glycosylated[\\s\\-]*h(?:a)?emoglobin",
                            "ヘモグロビン\\s*a1c", "(?<![a-z])ngsp(?![a-z])", "糖化ヘモグロビン"],
                  units: ["%", "mmol/mol"], plausible: 2...250,
                  leftovers: ["a1c(?![a-z0-9])"],
                  guess: { $0 > 20 ? "mmol/mol" : "%" }),
        LabMarker("TC", "Total cholesterol",
                  aliases: ["total[\\s\\-]*cholesterol", "(?<![a-z])t[\\s\\-]*cho(?![a-z])", "総コレステロール", "(?<![a-z])tc(?![a-z])"],
                  units: ["mg/dL", "mmol/L"], plausible: 0.5...1000,
                  guess: { $0 < 15 ? "mmol/L" : "mg/dL" }),
        LabMarker("LDL", "LDL cholesterol",
                  aliases: ["(?<![a-z])ldl(?![a-z])", "ldl[\\s\\-]*c(?![a-z])", "LDLコレステロール"],
                  units: ["mg/dL", "mmol/L"], plausible: 0.2...800,
                  leftovers: ["cholesterol"],
                  guess: { $0 < 10 ? "mmol/L" : "mg/dL" }),
        LabMarker("HDL", "HDL cholesterol",
                  aliases: ["(?<![a-z\\-])hdl(?![a-z])", "HDLコレステロール"],
                  units: ["mg/dL", "mmol/L"], plausible: 0.1...300,
                  leftovers: ["cholesterol"],
                  guess: { $0 < 6 ? "mmol/L" : "mg/dL" }),
        LabMarker("TG", "Triglycerides",
                  aliases: ["triglycerides?", "(?<![a-z])tg(?![a-z])", "中性脂肪", "トリグリセリド", "トリグリセライド"],
                  units: ["mg/dL", "mmol/L"], plausible: 0.1...3000,
                  guess: { $0 < 12 ? "mmol/L" : "mg/dL" }),
        LabMarker("HGB", "Hemoglobin",
                  aliases: ["h(?:a)?emoglobin(?![\\s\\-]*a1c)(?![a-z])", "(?<![a-z])hgb(?![a-z])", "(?<![a-z])hb(?![a-z0-9])", "ヘモグロビン(?!\\s*a1c)", "血色素"],
                  units: ["g/dL", "g/L"], plausible: 1...300,
                  guess: { $0 > 30 ? "g/L" : "g/dL" }),
        LabMarker("FER", "Ferritin",
                  aliases: ["ferritin", "フェリチン"],
                  units: ["ng/mL", "μg/L"], plausible: 0.5...10000),
        LabMarker("FE", "Iron",
                  aliases: ["(?<![a-z])(?:serum[\\s\\-]*)?iron(?![a-z])", "(?<![a-z])fe(?![a-z])", "血清鉄", "(?<![一-龥])鉄(?![一-龥])"],
                  units: ["μg/dL", "μmol/L"], plausible: 1...1500,
                  guess: { $0 < 40 ? "μmol/L" : "μg/dL" }),
        LabMarker("VITD", "Vitamin D",
                  aliases: ["vitamin[\\s\\-]*d", "25[\\s\\-]*\\(?oh\\)?[\\s\\-]*d", "ビタミン\\s*d"],
                  units: ["ng/mL", "nmol/L"], plausible: 1...500,
                  guess: { $0 >= 100 ? "nmol/L" : "ng/mL" }),
        LabMarker("B12", "Vitamin B12",
                  aliases: ["vitamin[\\s\\-]*b[\\s\\-]*12", "(?<![a-z0-9])b[\\s\\-]*12(?![a-z0-9])", "cobalamin", "ビタミン\\s*b\\s*12"],
                  units: ["pg/mL", "pmol/L"], plausible: 10...6000),
        LabMarker("FOL", "Folate",
                  aliases: ["folate", "folic[\\s\\-]*acid", "葉酸"],
                  units: ["ng/mL", "nmol/L"], plausible: 0.1...150),
        LabMarker("CRE", "Creatinine",
                  aliases: ["creatinine(?![\\s\\-]*clearance)", "クレアチニン"],
                  units: ["mg/dL", "μmol/L"], plausible: 0.05...2500,
                  guess: { $0 > 20 ? "μmol/L" : "mg/dL" }),
        LabMarker("EGFR", "eGFR",
                  aliases: ["(?<![a-z])e[\\s\\-]*gfr(?![a-z])"],
                  units: ["mL/min/1.73m²"], plausible: 1...200),
        LabMarker("ALT", "ALT",
                  aliases: ["(?<![a-z])alt(?![a-z])", "(?<![a-z])gpt(?![a-z])", "alanine[\\s\\-]*(?:amino)?transferase"],
                  units: ["U/L"], plausible: 1...5000),
        LabMarker("AST", "AST",
                  aliases: ["(?<![a-z])ast(?![a-z])", "(?<![a-z])got(?![a-z])", "aspartate[\\s\\-]*(?:amino)?transferase"],
                  units: ["U/L"], plausible: 1...5000),
        LabMarker("NA", "Sodium",
                  aliases: ["sodium", "(?<![a-z])na(?![a-z])", "ナトリウム"],
                  units: ["mmol/L", "mEq/L"], plausible: 80...200),
        LabMarker("K", "Potassium",
                  aliases: ["potassium", "^\\s*k(?![a-z0-9])", "カリウム"],
                  units: ["mmol/L", "mEq/L"], plausible: 1...12),
        LabMarker("CA", "Calcium",
                  aliases: ["calcium", "(?<![a-z])ca(?![a-z])", "カルシウム"],
                  units: ["mg/dL", "mmol/L"], plausible: 0.5...20,
                  guess: { $0 < 4 ? "mmol/L" : "mg/dL" }),
        LabMarker("CRP", "CRP",
                  aliases: ["(?<![a-z])crp(?![a-z])", "c[\\s\\-]*reactive[\\s\\-]*protein", "c反応性蛋白"],
                  units: ["mg/L", "mg/dL"], plausible: 0.01...600),
        LabMarker("TSH", "TSH",
                  aliases: ["(?<![a-z])tsh(?![a-z])", "thy\\w*[\\s\\-]*stimulating[\\s\\-]*hormone", "thyrotroph?in", "甲状腺刺激", "チロトロピン"],
                  units: ["mIU/L", "μIU/mL"], plausible: 0.001...150,
                  typical: [
                    .init(.japan, "mIU/L", 0.50, 5.00), .init(.japan, "μIU/mL", 0.50, 5.00),
                    .init(.philippines, "mIU/L", 0.27, 4.20), .init(.philippines, "μIU/mL", 0.27, 4.20),
                    .init(nil, "mIU/L", 0.4, 4.0), .init(nil, "μIU/mL", 0.4, 4.0),
                  ],
                  guess: { _ in "μIU/mL" }),
        LabMarker("FT4", "Free T4",
                  aliases: [
                    "free[\\s\\-.]*t[\\s\\-]*4(?![a-z0-9])",
                    "(?<![a-z])f[\\s\\-.]*t[\\s\\-]*4(?![a-z0-9])",
                    "free[\\s\\-]*\\(?\\s*thyroxine",
                    "thyroxine\\W{0,3}\\(?\\s*free",
                    "(?<![a-z0-9])t[\\s\\-]*4\\W{0,3}\\(?\\s*free",
                    "遊離\\s*t\\s*-?\\s*4(?![0-9])",
                    "遊離\\s*(?:サイロキシン|チロキシン)",
                  ],
                  units: ["pmol/L", "ng/dL"], plausible: 0.05...120,
                  leftovers: ["(?<![a-z0-9])(?:f\\s*-?\\s*)?t\\s*-?\\s*4(?![a-z0-9])"],
                  typical: [
                    .init(.japan, "ng/dL", 0.90, 1.70), .init(.japan, "pmol/L", 11.6, 21.9),
                    .init(.philippines, "pmol/L", 12, 22), .init(.philippines, "ng/dL", 0.93, 1.70),
                    .init(nil, "pmol/L", 10, 23), .init(nil, "ng/dL", 0.8, 1.8),
                  ],
                  guess: { $0 < 5 ? "ng/dL" : "pmol/L" }),
        LabMarker("FT3", "Free T3",
                  aliases: [
                    "free[\\s\\-.]*t[\\s\\-]*3(?![a-z0-9])",
                    "(?<![a-z])f[\\s\\-.]*t[\\s\\-]*3(?![a-z0-9])",
                    "free[\\s\\-]*\\(?\\s*triiodothyronine",
                    "triiodothyronine\\W{0,3}\\(?\\s*free",
                    "(?<![a-z0-9])t[\\s\\-]*3\\W{0,3}\\(?\\s*free",
                    "遊離\\s*t\\s*-?\\s*3(?![0-9])",
                    "遊離\\s*(?:トリヨードサイロニン|トリヨードチロニン)",
                  ],
                  units: ["pmol/L", "pg/mL"], plausible: 0.1...60,
                  leftovers: ["(?<![a-z0-9])(?:f\\s*-?\\s*)?t\\s*-?\\s*3(?![a-z0-9])"],
                  typical: [
                    .init(.japan, "pg/mL", 2.30, 4.00), .init(.japan, "pmol/L", 3.5, 6.1),
                    .init(.philippines, "pmol/L", 3.1, 6.8), .init(.philippines, "pg/mL", 2.0, 4.4),
                    .init(nil, "pmol/L", 3.1, 6.8), .init(nil, "pg/mL", 2.3, 4.2),
                  ],
                  // 7 and above is pmol/L; between 1.5 and 7 the units overlap, so below 5.5 is guessed pg/mL.
                  guess: { $0 < 5.5 ? "pg/mL" : "pmol/L" }),
    ]

    public static func marker(_ code: String) -> LabMarker? { all.first { $0.code == code } }

    public static func name(_ code: String) -> String { marker(code)?.name ?? code }

    /// Typical adult range (the lab region's when known, else the widely cited one), for a unit.
    /// Nil for markers with no default range: only a range printed on the report is shown.
    public static func typicalRange(_ code: String, unit: String, region: LabRegion) -> (Double, Double)? {
        guard let m = marker(code) else { return nil }
        let u = canonical(unit)
        if let t = m.typical.first(where: { $0.region == region && $0.unit == u }) { return (t.low, t.high) }
        if let t = m.typical.first(where: { $0.region == nil && $0.unit == u }) { return (t.low, t.high) }
        return nil
    }

    /// Her last unit for a marker, else the first one.
    public static func defaultUnit(_ code: String, previous: [String]) -> String {
        let options = marker(code)?.units ?? []
        return previous.lazy.map(canonical).first(where: options.contains) ?? options.first ?? ""
    }

    /// Maps spellings from reports and OCR onto the picker's units.
    public static func canonical(_ unit: String) -> String {
        let raw = unit.lowercased().replacingOccurrences(of: " ", with: "")
        if raw.hasPrefix("ml/min") { return "mL/min/1.73m²" }
        // A recognized "1" is read as "l" (pmo1/L, ng/d1, u1u/ml).
        let u = raw.replacingOccurrences(of: "1", with: "l")
        switch u {
        case "miu/l", "mu/l", "miu/liter", "mlu/l": return "mIU/L"
        case "μiu/ml", "µiu/ml", "uiu/ml", "ulu/ml", "μlu/ml", "µlu/ml", "μu/ml", "µu/ml", "uu/ml": return "μIU/mL"
        case "pmol/l": return "pmol/L"
        case "nmol/l": return "nmol/L"
        case "ng/dl": return "ng/dL"
        case "pg/ml": return "pg/mL"
        case "ng/ml": return "ng/mL"
        case "mg/dl": return "mg/dL"
        case "g/dl": return "g/dL"
        case "g/l": return "g/L"
        case "mg/l": return "mg/L"
        case "mmol/l": return "mmol/L"
        case "mmol/mol": return "mmol/mol"
        case "μmol/l", "µmol/l", "umol/l": return "μmol/L"
        case "μg/dl", "µg/dl", "ug/dl", "mcg/dl": return "μg/dL"
        case "μg/l", "µg/l", "ug/l", "mcg/l": return "μg/L"
        case "meq/l": return "mEq/L"
        case "u/l", "iu/l": return "U/L"
        case "%": return "%"
        default: return unit
        }
    }
}

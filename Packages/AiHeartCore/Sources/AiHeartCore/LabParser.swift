import Foundation

/// Reads lab results from the text of a lab report screenshot (recognized on the
/// device). English and Japanese. Which markers it looks for, and how each is spelled on
/// a report, comes from the catalogue (`LabMarkers`). Everything it finds is shown to her
/// to check before saving; it never saves on its own.
///
/// Input is a list of text lines, ideally one table row per line (see `LabOCR.rows`).
/// When a row was split over several lines (label, then value, then unit, then range),
/// the lines right after a label that hold only numbers, units and flags are read as
/// part of that label's row.
public enum LabParser {
    public struct Value: Equatable, Sendable {
        public var value: Double
        public var unit: String?
        /// The lab's own reference range, when printed next to the value.
        public var low: Double?
        public var high: Double?
    }

    public struct Reading: Equatable, Sendable {
        public var date: Date?
        /// Results found, by marker code.
        public var values: [String: Value] = [:]

        public subscript(code: String) -> Value? {
            get { values[code] }
            set { values[code] = newValue }
        }

        public var isEmpty: Bool { values.isEmpty }
    }

    // MARK: Labels

    /// Label patterns per marker (case-insensitive regex, run on normalized text), from the catalogue.
    static let labels: [(code: String, patterns: [String])] = LabMarkers.all.map { ($0.code, $0.aliases) }

    /// Extra label words dropped from a row before its number is read.
    static let leftovers: [String] = LabMarkers.all.flatMap(\.leftovers)

    /// Other tests that mention a marker in their name but are not its result.
    static let notAResult = "receptor|antibod|index|uptake|(?<![a-z])ratio(?![a-z])|non[\\s\\-]*hdl|受容体|抗体|指数"

    // MARK: Units

    /// Unit spellings, including common recognition misreads: μ as u, I as l or 1,
    /// L as 1, stray spaces ("uIU/m L", "ng/d L").
    static let fixedUnits: [(pattern: String, unit: String)] = [
        ("(?<![a-z])pmo[li1]\\s*/\\s*[li1](?![a-z])", "pmol/L"),
        ("(?<![a-z])nmo[li1]\\s*/\\s*[li1](?![a-z])", "nmol/L"),
        ("(?<![a-z])ng\\s*/\\s*d\\s*[li1](?![a-z])", "ng/dL"),
        ("(?<![a-z])pg\\s*/\\s*m\\s*[li1](?![a-z])", "pg/mL"),
        ("(?<![a-z])ng\\s*/\\s*m\\s*[li1](?![a-z])", "ng/mL"),
        ("(?<![a-z])mg\\s*/\\s*d\\s*[li1](?![a-z])", "mg/dL"),
        ("(?<![a-zμµ])g\\s*/\\s*d\\s*[li1](?![a-z])", "g/dL"),
        ("(?<![a-z])(?:[μµu]|mc)g\\s*/\\s*d\\s*[li1](?![a-z])", "μg/dL"),
        ("(?<![a-z])(?:[μµu]|mc)g\\s*/\\s*[li1](?![a-z])", "μg/L"),
        ("(?<![a-z])mg\\s*/\\s*[li1](?![a-z])", "mg/L"),
        ("(?<![a-zμµ])g\\s*/\\s*[li1](?![a-z])", "g/L"),
        ("(?<![a-z])mmo[li1]\\s*/\\s*[li1](?![a-z])", "mmol/L"),
        ("(?<![a-z])mmo[li1]\\s*/\\s*mo[li1](?![a-z])", "mmol/mol"),
        ("(?<![a-z])[μµu]mo[li1]\\s*/\\s*[li1](?![a-z])", "μmol/L"),
        ("(?<![a-z])meq\\s*/\\s*[li1](?![a-z])", "mEq/L"),
        ("(?<![a-zμµ])i?u\\s*/\\s*[li1](?![a-z])", "U/L"),
        ("(?<![a-z])ml\\s*/\\s*min\\s*/\\s*1\\.73\\s*m\\s*[2²]?", "mL/min/1.73m²"),
        ("%", "%"),
    ]
    /// mIU/L, mU/L, μIU/mL, uIU/mL ... Prefix, optional I, U, slash, optional m, L.
    static let iuUnit = "(?<![a-z])([μµum])\\s*([il1])?\\s*u\\s*/\\s*(m)?\\s*([l1])(?![a-z])"

    /// Every unit found in `text`, in reading order.
    static func unitMatches(in text: String) -> [(unit: String, range: Range<String.Index>)] {
        var out: [(String, Range<String.Index>)] = []
        for (pattern, unit) in fixedUnits {
            for r in ranges(pattern, in: text) { out.append((unit, r)) }
        }
        if let re = try? NSRegularExpression(pattern: iuUnit, options: [.caseInsensitive]) {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(m.range, in: text),
                      let pre = Range(m.range(at: 1), in: text) else { continue }
                let micro = text[pre].lowercased() != "m"
                let perMilli = m.range(at: 3).location != NSNotFound
                switch (micro, perMilli) {
                case (true, true): out.append(("μIU/mL", whole))
                case (false, false): out.append(("mIU/L", whole))
                case (false, true): out.append(("mIU/mL", whole))
                case (true, false): break // μIU/L is not a real reporting unit; read as no unit
                }
            }
        }
        return out.sorted { $0.1.lowerBound < $1.1.lowerBound }
    }

    // MARK: Parse

    public static func parse(lines raw: [String], now: Date = Date()) -> Reading {
        let lines = raw.map(normalize)
        var r = Reading()
        for (i, line) in lines.enumerated() {
            if matches(notAResult, in: line) { continue }
            let found = labelOccurrences(in: line)
            for (k, occ) in found.enumerated() {
                let isLast = k == found.count - 1
                let end = isLast ? line.endIndex : found[k + 1].range.lowerBound
                let seg = String(line[occ.range.upperBound..<end])
                var v = readValue(seg, code: occ.code)
                // A row split over lines: take the number, unit and range cells that follow.
                if isLast, v == nil || v?.unit == nil || v?.low == nil {
                    let cells = followingCells(lines, after: i)
                    if !cells.isEmpty,
                       let extended = readValue(seg + "  " + cells.joined(separator: "  "), code: occ.code),
                       v == nil || extended.value == v?.value {
                        v = extended
                    }
                }
                if let v { merge(occ.code, v, into: &r) }
            }
        }
        r.date = findDate(lines, now: now)
        return r
    }

    /// Fills `reading` with `v`. A second sighting of the same number (for example in the
    /// raw lines after the grouped rows) can only add a missing unit or range.
    static func merge(_ code: String, _ v: Value, into r: inout Reading) {
        guard var old = r[code] else { r[code] = v; return }
        guard old.value == v.value else { return }
        if old.unit == nil { old.unit = v.unit }
        if old.low == nil { old.low = v.low; old.high = v.high }
        r[code] = old
    }

    /// Label hits in a line, left to right. A repeat of the same marker right after
    /// itself ("Free T4 (free thyroxine)") counts once. Where two spellings start at the
    /// same place, the longer one wins ("Hb A1c" over "Hb").
    static func labelOccurrences(in line: String) -> [(code: String, range: Range<String.Index>)] {
        var hits: [(String, Range<String.Index>)] = []
        for (code, pats) in labels {
            for p in pats { for r in ranges(p, in: line) { hits.append((code, r)) } }
        }
        hits.sort {
            $0.1.lowerBound != $1.1.lowerBound ? $0.1.lowerBound < $1.1.lowerBound : $0.1.upperBound > $1.1.upperBound
        }
        var out: [(String, Range<String.Index>)] = []
        for h in hits {
            if let last = out.last {
                if h.1.lowerBound < last.1.upperBound { continue } // overlapping spelling of the same label
                if last.0 == h.0 { continue }
            }
            out.append(h)
        }
        return out.map { (code: $0.0, range: $0.1) }
    }

    /// Up to four lines after a label line that look like table cells (numbers, units,
    /// flags, ranges) and nothing else.
    static func followingCells(_ lines: [String], after i: Int) -> [String] {
        var cells: [String] = []
        var j = i + 1
        while j < lines.count, cells.count < 4, isCell(lines[j]) {
            cells.append(lines[j]); j += 1
        }
        return cells
    }

    static func isCell(_ line: String) -> Bool {
        var t = line
        let hasUnit = !unitMatches(in: t).isEmpty
        for m in unitMatches(in: t).reversed() { t.replaceSubrange(m.range, with: " ") }
        t = stripFlags(t)
        t = t.replacingOccurrences(of: "[\\d\\s.\\-()\\[\\]<>=,]", with: "", options: .regularExpression)
        guard t.isEmpty else { return false }
        return hasUnit || line.contains { $0.isNumber }
    }

    // MARK: Values

    /// Reads value, unit and range from the text after a label. The unit and range can be
    /// in any order and either can be missing.
    static func readValue(_ text: String, code: String? = nil) -> Value? {
        var t = text
        let unit: String?
        let found = unitMatches(in: t)
        unit = found.first?.unit
        for m in found.reversed() { t.replaceSubrange(m.range, with: " ") }
        // Dates and times in the row are not results.
        for p in ["\\d{4}\\s*[年/.\\-]\\s*\\d{1,2}\\s*[月/.\\-]\\s*\\d{1,2}\\s*日?",
                  "(?<!\\d)\\d{1,2}[/.\\-]\\d{1,2}[/.\\-]\\d{4}(?!\\d)",
                  "(?<!\\d)\\d{1,2}:\\d{2}(?::\\d{2})?"] {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        // Label words left in the row ("Free T4 (T4, free)") and their digits.
        for (_, pats) in labels { for p in pats { t = t.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive]) } }
        for p in leftovers { t = t.replacingOccurrences(of: p, with: " ", options: [.regularExpression, .caseInsensitive]) }
        t = t.replacingOccurrences(of: "\\d+(?:st|nd|rd|th)(?![a-z])", with: " ", options: [.regularExpression, .caseInsensitive])
        // Notes in brackets with no digits: "(free thyroxine)", "(H)".
        t = t.replacingOccurrences(of: "\\([^()\\d]*\\)|\\[[^\\[\\]\\d]*\\]", with: " ", options: .regularExpression)
        t = stripFlags(t)

        let num = "\\d+(?:\\.\\d+)?"
        let pattern = "(?<![\\d.])(\(num))\\s*-\\s*(\(num))(?![\\d.])|(?<![\\d.])(\(num))(?!\\d)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        var candidates: [(value: Double, text: String, at: Int)] = []
        var range: (Double, Double)?
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            func group(_ i: Int) -> Double? { Range(m.range(at: i), in: t).flatMap { Double(t[$0]) } }
            if let lo = group(1), let hi = group(2) {
                if range == nil, lo < hi { range = (lo, hi) }
            } else if let v = group(3), let r = Range(m.range(at: 3), in: t) {
                candidates.append((v, String(t[r]), m.range(at: 3).location))
            }
        }
        // Rows can carry test codes, sample numbers or page numbers. Keep numbers that fit
        // the test; prefer decimals and numbers near the lab's range.
        let fits = candidates.filter { c in
            if c.text.count >= 4, !c.text.contains(".") { return false }   // codes and IDs: 10432
            guard let code, let m = LabMarkers.marker(code) else { return true }
            return m.plausible.contains(c.value)
        }
        func score(_ c: (value: Double, text: String, at: Int)) -> Double {
            var s = 0.0
            if c.text.contains(".") { s += 1 }
            if let (lo, hi) = range, c.value >= lo / 10, c.value <= hi * 10 { s += 2 }
            return s - Double(c.at) / 10_000   // earlier wins ties
        }
        guard let value = fits.max(by: { score($0) < score($1) })?.value else { return nil }
        return Value(value: value, unit: unit, low: range?.0, high: range?.1)
    }

    /// Removes high/low flags: "H", "L", "HH", "High", "*", arrows. They are not values.
    static func stripFlags(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "[*↑↓▲▼△▽⇧⇩†‡高低]", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?<![A-Za-z])(?:HH|LL|H|L)(?![A-Za-z])", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?<![a-z])(?:high|low|crit)(?![a-z])", with: " ", options: [.regularExpression, .caseInsensitive])
        return t
    }

    /// A unit to suggest when the report image did not show one, from the size of the
    /// number (the marker's rule in the catalogue). Only a suggestion: she confirms it
    /// before saving.
    public static func guessUnit(code: String, value: Double) -> String {
        LabMarkers.marker(code)?.guessUnit(value) ?? ""
    }

    // MARK: Dates

    /// Priority of the words printed next to a date. Lower wins.
    enum DateRole: Int { case birth = -1, collected = 0, tested = 1, reported = 2, plain = 3, printed = 4 }

    static let dateKeywords: [(DateRole, String)] = [
        (.birth, "(?<![a-z])d\\.?o\\.?b(?![a-z])|birth|生年月日|誕生日"),
        (.collected, "collected|collection|collect\\s*date|specimen|sample|drawn|採取|採血|検体"),
        (.tested, "date\\s*of\\s*(?:test|exam|examination|service|analysis)|(?:test|exam)\\s*date|results?\\s*date|date\\s*of\\s*results?|検査日|検査年月日|検査実施日"),
        (.reported, "reported|report\\s*date|date\\s*of\\s*report|received|receipt|受付日|受付年月日|報告日|報告年月日"),
        (.printed, "printed|print\\s*date|date\\s*printed|generated|印刷|出力日|発行日|issued"),
    ]

    static func findDate(_ lines: [String], now: Date) -> Date? {
        var found: [(date: Date, role: DateRole)] = []
        var pending: DateRole?
        for line in lines {
            let ns = line as NSString
            var hits: [(role: DateRole, range: NSRange)] = []
            for (role, p) in dateKeywords {
                guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) { hits.append((role, m.range)) }
            }
            hits.sort { $0.range.location < $1.range.location }
            let ds = dates(in: line, now: now)
            for d in ds {
                var role = DateRole.plain
                if let before = hits.last(where: { NSMaxRange($0.range) <= d.range.location }) {
                    role = before.role
                } else if let p = pending {
                    role = p
                } else if let after = hits.first(where: { $0.range.location >= NSMaxRange(d.range) }) {
                    role = after.role
                }
                if role != .birth { found.append((d.date, role)) }
            }
            // "Date collected" at the end of a line: the date is in the next cell or line.
            pending = nil
            if ds.isEmpty, let last = hits.last {
                let tail = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: CharacterSet(charactersIn: " :-\t"))
                if tail.count <= 4 { pending = last.role }
            }
        }
        for role in [DateRole.collected, .tested, .reported] {
            if let best = found.filter({ $0.role == role }).map(\.date).max() { return best }
        }
        let limit = now.addingTimeInterval(86_400)
        for role in [DateRole.plain, .printed] {
            if let best = found.filter({ $0.role == role && $0.date <= limit }).map(\.date).max() { return best }
        }
        return nil
    }

    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    static func month(_ word: String) -> Int? {
        let w = word.lowercased()
        guard w.count >= 3 else { return nil }
        let i = monthNames.firstIndex { $0.hasPrefix(w) } ?? (w == "sept" ? 8 : nil)
        return i.map { $0 + 1 }
    }

    /// Dates in a line, with where they sit. Slash dates are month first (Philippine
    /// reports) unless the first number is above 12; dotted dates are day first.
    static func dates(in line: String, now: Date) -> [(date: Date, range: NSRange)] {
        var out: [(Date, NSRange)] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let maxYear = cal.component(.year, from: now) + 1
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            guard (2000...max(maxYear, 2000)).contains(y), (1...12).contains(m), (1...31).contains(d),
                  let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)),
                  cal.component(.day, from: date) == d else { return nil }
            return date
        }
        func int(_ m: NSTextCheckingResult, _ i: Int) -> Int? { Range(m.range(at: i), in: line).flatMap { Int(line[$0]) } }
        func str(_ m: NSTextCheckingResult, _ i: Int) -> String? { Range(m.range(at: i), in: line).map { String(line[$0]) } }
        func run(_ pattern: String, caseInsensitive: Bool = false, _ body: (NSTextCheckingResult) -> Date?) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return }
            for m in re.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let d = body(m) { out.append((d, m.range)) }
            }
        }
        // 2026年10月31日, 2026/10/31, 2026-10-31, 2026.10.31
        run("(?<!\\d)(\\d{4})\\s*[年/.\\-]\\s*(\\d{1,2})\\s*[月/.\\-]\\s*(\\d{1,2})(?!\\d)\\s*日?") { m in
            guard let y = int(m, 1), let mo = int(m, 2), let d = int(m, 3) else { return nil }
            return make(y, mo, d)
        }
        // 令和8年10月31日, R8.10.31, 平成31年4月1日, 令和元年5月1日
        run("(令和|平成|(?<![A-Za-z])[RH])\\s*(\\d{1,2}|元)\\s*[年./\\-]\\s*(\\d{1,2})\\s*[月./\\-]\\s*(\\d{1,2})(?!\\d)\\s*日?") { m in
            guard let era = str(m, 1), let ys = str(m, 2), let mo = int(m, 3), let d = int(m, 4) else { return nil }
            let n = ys == "元" ? 1 : (Int(ys) ?? 0)
            let base = (era == "令和" || era == "R") ? 2018 : 1988
            return make(base + n, mo, d)
        }
        // 10/31/2026 (month first), 31/10/2026 (first number above 12), 31.10.2026 (day first)
        run("(?<![\\d./\\-])(\\d{1,2})([/.\\-])(\\d{1,2})[/.\\-](\\d{4})(?!\\d)") { m in
            guard let a = int(m, 1), let sep = str(m, 2), let b = int(m, 3), let y = int(m, 4) else { return nil }
            let monthFirst = make(y, a, b), dayFirst = make(y, b, a)
            if a > 12 { return dayFirst }
            if b > 12 { return monthFirst }
            if sep == "." { return dayFirst ?? monthFirst }
            // Both readings possible: month first, unless that lands after today and the other does not.
            if let mf = monthFirst, mf > now.addingTimeInterval(86_400), let df = dayFirst, df <= now.addingTimeInterval(86_400) { return df }
            return monthFirst ?? dayFirst
        }
        // 31 Oct 2026, 31-Oct-2026, 31st October 2026
        run("(?<!\\d)(\\d{1,2})(?:st|nd|rd|th)?[\\s.\\-,]*([A-Za-z]{3,9})\\.?[\\s.\\-,]*(\\d{4})(?!\\d)") { m in
            guard let d = int(m, 1), let w = str(m, 2), let mo = month(w), let y = int(m, 3) else { return nil }
            return make(y, mo, d)
        }
        // Oct 31, 2026 / October 31 2026
        run("(?<![A-Za-z])([A-Za-z]{3,9})\\.?\\s*(\\d{1,2})(?:st|nd|rd|th)?,?\\s*(\\d{4})(?!\\d)") { m in
            guard let w = str(m, 1), let mo = month(w), let d = int(m, 2), let y = int(m, 3) else { return nil }
            return make(y, mo, d)
        }
        return out.sorted { $0.1.location < $1.1.location }.map { (date: $0.0, range: $0.1) }
    }

    // MARK: Helpers

    /// Full-width forms to ASCII (katakana stay as they are), all dash and wave
    /// variants to "-", "1 to 2" to "1-2", comma decimals to points.
    static func normalize(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            var v = u.value
            switch v {
            case 0xFF01...0xFF5E: v -= 0xFEE0
            case 0x3000, 0x00A0, 0x2009, 0x200A, 0x202F: v = 0x20
            default: break
            }
            switch v {
            case 0x7E, 0x2010...0x2015, 0x2212, 0x223C, 0x301C, 0x2053: v = 0x2D
            default: break
            }
            scalars.append(Unicode.Scalar(v) ?? u)
        }
        var t = String(scalars)
        t = t.replacingOccurrences(of: "(\\d),(\\d)", with: "$1.$2", options: .regularExpression)
        t = t.replacingOccurrences(of: "(\\d)\\s*ー\\s*(\\d)", with: "$1-$2", options: .regularExpression)
        t = t.replacingOccurrences(of: "(\\d)\\s*to\\s*(\\d)", with: "$1-$2", options: [.regularExpression, .caseInsensitive])
        return t
    }

    /// Compiled patterns, kept: the catalogue has many labels and each row is tried against all of them.
    private final class RegexCache: @unchecked Sendable {
        private var store: [String: NSRegularExpression] = [:]
        private let lock = NSLock()
        func regex(_ pattern: String) -> NSRegularExpression? {
            lock.lock(); defer { lock.unlock() }
            if let r = store[pattern] { return r }
            guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            store[pattern] = r
            return r
        }
    }
    private static let cache = RegexCache()

    static func ranges(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let re = cache.regex(pattern) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    static func matches(_ pattern: String, in text: String) -> Bool {
        !ranges(pattern, in: text).isEmpty
    }
}

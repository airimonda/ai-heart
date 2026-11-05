import Foundation

// Minimal OOXML workbook writer (M11 spreadsheet export). Inline strings, no shared strings,
// three styles (bold header, date-time, two decimals). Opens in Numbers and Excel.

public enum Cell: Equatable {
    case text(String)
    case number(Double)
    case date(Date)
    case empty
}

public struct Sheet {
    public var name: String
    public var header: [String]
    public var rows: [[Cell]]

    public init(name: String, header: [String], rows: [[Cell]]) {
        self.name = name
        self.header = header
        self.rows = rows
    }
}

public enum XLSXWriter {
    /// Dates are written as the wall-clock time in `timeZone` (spreadsheets have no time zones).
    public static func make(_ sheets: [Sheet], timeZone: TimeZone = .current) -> Data {
        var sheets = sheets
        if sheets.isEmpty { sheets = [Sheet(name: "Sheet1", header: [], rows: [])] }
        var names: [String] = []
        for s in sheets { names.append(uniqueName(sanitizedName(s.name), among: names)) }

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes(count: sheets.count).utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("xl/workbook.xml", Data(workbook(names: names).utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRels(count: sheets.count).utf8))
        zip.add("xl/styles.xml", Data(styles.utf8))
        for (i, s) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(i + 1).xml", Data(sheetXML(s, timeZone: timeZone).utf8))
        }
        return zip.finish()
    }

    // MARK: Names

    /// Excel limits: 1 to 31 characters, none of `[ ] : * ? / \`, no leading or trailing apostrophe.
    public static func sanitizedName(_ raw: String) -> String {
        let bad = Set("[]:*?/\\")
        var s = String(raw.filter { !bad.contains($0) && !($0.unicodeScalars.allSatisfy { $0.value < 0x20 }) })
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "'").union(.whitespaces))
        if s.isEmpty { s = "Sheet" }
        return String(s.prefix(31)).trimmingCharacters(in: CharacterSet(charactersIn: "'").union(.whitespaces))
    }

    static func uniqueName(_ name: String, among used: [String]) -> String {
        let lower = Set(used.map { $0.lowercased() })
        if !lower.contains(name.lowercased()) { return name }
        var n = 2
        while true {
            let suffix = " \(n)"
            let candidate = String(name.prefix(31 - suffix.count)) + suffix
            if !lower.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }

    // MARK: Package parts

    private static let xmlDecl = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private static func contentTypes(count: Int) -> String {
        var s = xmlDecl + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        s += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        s += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        s += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for i in 1...count {
            s += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        s += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        return s + "</Types>"
    }

    private static let rootRels = xmlDecl
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        + "</Relationships>"

    private static func workbook(names: [String]) -> String {
        var s = xmlDecl + "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        s += "<sheets>"
        for (i, n) in names.enumerated() {
            s += "<sheet name=\"\(escape(n))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        return s + "</sheets></workbook>"
    }

    private static func workbookRels(count: Int) -> String {
        var s = xmlDecl + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1...count {
            s += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        s += "<Relationship Id=\"rId\(count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return s + "</Relationships>"
    }

    /// Style ids: 0 general, 1 bold header, 2 date-time, 3 two decimals.
    private static let styles = xmlDecl
        + "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        + "<numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"yyyy\\-mm\\-dd\\ hh:mm\"/></numFmts>"
        + "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
        + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"4\">"
        + "<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"
        + "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>"
        + "<xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "<xf numFmtId=\"2\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        + "</cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"

    // MARK: Sheet

    static func columnLetters(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(UInt8(65 + r))) + s
            n = (n - 1) / 26
        }
        return s
    }

    /// Escapes XML text and drops characters XML 1.0 cannot carry.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for u in s.unicodeScalars {
            switch u {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            case "\t", "\n", "\r": out.unicodeScalars.append(u)
            default:
                let v = u.value
                if v < 0x20 || (0xD800...0xDFFF).contains(v) || v == 0xFFFE || v == 0xFFFF { continue }
                out.unicodeScalars.append(u)
            }
        }
        return out
    }

    static func serial(_ date: Date, timeZone: TimeZone) -> Double {
        let local = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return local / 86400 + 25569   // 1970-01-01 is serial 25569
    }

    private static func sheetXML(_ sheet: Sheet, timeZone: TimeZone) -> String {
        let columns = max(sheet.header.count, sheet.rows.map(\.count).max() ?? 0)
        var widths = [Double](repeating: 8, count: columns)
        func widen(_ col: Int, _ chars: Int) { widths[col] = max(widths[col], Double(min(chars, 60)) + 2) }

        var data = ""
        var rowNo = 0
        if !sheet.header.isEmpty {
            rowNo += 1
            data += "<row r=\"1\">"
            for (c, h) in sheet.header.enumerated() {
                widen(c, h.count)
                data += "<c r=\"\(columnLetters(c))1\" s=\"1\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(h))</t></is></c>"
            }
            data += "</row>"
        }
        for row in sheet.rows {
            rowNo += 1
            var cells = ""
            for (c, cell) in row.enumerated() {
                let ref = "\(columnLetters(c))\(rowNo)"
                switch cell {
                case .empty:
                    break
                case .text(let t):
                    if t.isEmpty { break }
                    widen(c, t.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0)
                    cells += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(t))</t></is></c>"
                case .number(let n):
                    guard n.isFinite else { break }
                    widen(c, 10)
                    let style = n == n.rounded() ? "" : " s=\"3\""
                    cells += "<c r=\"\(ref)\"\(style)><v>\(n)</v></c>"
                case .date(let d):
                    widen(c, 16)
                    cells += "<c r=\"\(ref)\" s=\"2\"><v>\(String(format: "%.8f", serial(d, timeZone: timeZone)))</v></c>"
                }
            }
            data += cells.isEmpty ? "<row r=\"\(rowNo)\"/>" : "<row r=\"\(rowNo)\">\(cells)</row>"
        }

        var s = xmlDecl + "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if columns > 0 { s += "<dimension ref=\"A1:\(columnLetters(columns - 1))\(max(rowNo, 1))\"/>" }
        s += "<sheetViews><sheetView workbookViewId=\"0\">"
        if !sheet.header.isEmpty {
            s += "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/><selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/>"
        }
        s += "</sheetView></sheetViews><sheetFormatPr defaultRowHeight=\"15\"/>"
        if columns > 0 {
            s += "<cols>"
            for c in 0..<columns { s += "<col min=\"\(c + 1)\" max=\"\(c + 1)\" width=\"\(widths[c])\" customWidth=\"1\"/>" }
            s += "</cols>"
        }
        return s + "<sheetData>\(data)</sheetData></worksheet>"
    }
}

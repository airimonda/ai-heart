import Foundation

/// Data for the "For a therapist" report (owner's request, part of M11 Export). Plain
/// counts and averages from her own records; it describes and never diagnoses.
/// Released entries are never included; resting entries contribute only their kept lines.
/// Exception: notes kept from let-go entries (docs/16), resting or released, appear in their own
/// section when she leaves "Notes on hard moments" on. Only the notes, never the entry or its count.
public struct TherapistReportData: Sendable {
    public struct Week: Sendable, Identifiable {
        public let start: AnchoredDay
        public let valence: Double
        public let arousal: Double
        public let entries: Int
        public var id: Int { start.ordinal }
    }

    public struct WrittenEntry: Sendable {
        public let date: Date
        public let word: String?
        public let text: String
    }

    public var from: AnchoredDay
    public var to: AnchoredDay
    public var entryCount: Int
    public var daysWithEntries: Int
    public var weeks: [Week]
    public var topWords: [(String, Int)]
    public var topRegions: [(String, Int)]
    public var topSensations: [(String, Int)]
    public var keptLines: [(Date, String)]
    public var writing: [WrittenEntry]
    /// Notes kept from let-go entries, oldest first.
    public var notes: [(Date, ReleaseNote)] = []
    /// How often each need seemed missing across those notes, most often first.
    public var missingNeeds: [(CoreNeed, Int)] = []
    /// How often each feeling was named across those notes, most often first.
    public var feelings: [(NoteFeeling, Int)] = []
}

/// A plain value copy of an entry, so the report can be built and tested off the store.
public struct ReportEntry: Sendable {
    public var createdAt: Date
    public var tz: TimeZone
    public var status: EntryStatus
    public var word: String?
    public var valence: Double?
    public var arousal: Double?
    public var regions: [String]
    public var sensations: [String]
    public var text: String?
    public var keptLines: [String]
    public var note: ReleaseNote?

    public init(createdAt: Date, tz: TimeZone, status: EntryStatus, word: String?, valence: Double?, arousal: Double?,
                regions: [String], sensations: [String], text: String?, keptLines: [String], note: ReleaseNote? = nil) {
        self.createdAt = createdAt; self.tz = tz; self.status = status; self.word = word
        self.valence = valence; self.arousal = arousal; self.regions = regions; self.sensations = sensations
        self.text = text; self.keptLines = keptLines; self.note = note
    }

    public init(_ e: Entry) {
        self.init(createdAt: e.createdAt, tz: e.timeZone, status: e.status, word: e.word, valence: e.valence, arousal: e.arousal,
                  regions: e.bodyRegions, sensations: e.sensations, text: e.text, keptLines: e.keptLines,
                  note: e.releaseNote)
    }
}

public enum TherapistReport {
    public static func build(entries: [ReportEntry], from: AnchoredDay, to: AnchoredDay, dayStartHour: Int,
                             includeWriting: Bool, includeNotes: Bool = true,
                             weekStart: (AnchoredDay) -> AnchoredDay) -> TherapistReportData {
        // Released entries are gone; they never appear, not even as counts.
        let inRange = entries.filter { e in
            guard e.status != .released else { return false }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.tz, dayStartHour: dayStartHour)
            return d >= from && d <= to
        }.sorted { $0.createdAt < $1.createdAt }

        let kept = inRange.filter { $0.status == .kept }
        var days = Set<AnchoredDay>()
        var byWeek: [AnchoredDay: [(Double, Double)]] = [:]
        var weekCounts: [AnchoredDay: Int] = [:]
        for e in inRange {
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.tz, dayStartHour: dayStartHour)
            days.insert(d)
            let w = weekStart(d)
            weekCounts[w, default: 0] += 1
            if let v = e.valence, let a = e.arousal { byWeek[w, default: []].append((v, a)) }
        }
        let weeks = byWeek.keys.sorted().map { w -> TherapistReportData.Week in
            let pts = byWeek[w]!
            return .init(start: w, valence: pts.map(\.0).reduce(0, +) / Double(pts.count),
                         arousal: pts.map(\.1).reduce(0, +) / Double(pts.count), entries: weekCounts[w] ?? pts.count)
        }

        func top(_ xs: [String], _ n: Int) -> [(String, Int)] {
            var c: [String: Int] = [:]
            for x in xs { c[x, default: 0] += 1 }
            return c.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
        }

        // Resting entries show only what she chose to keep.
        let keptLines = inRange.flatMap { e in e.keptLines.map { (e.createdAt, $0) } }
        let writing: [TherapistReportData.WrittenEntry] = includeWriting
            ? kept.compactMap { e in e.text.map { .init(date: e.createdAt, word: e.word, text: $0) } }
            : []

        var data = TherapistReportData(
            from: from, to: to, entryCount: inRange.count, daysWithEntries: days.count, weeks: weeks,
            topWords: top(kept.compactMap(\.word), 12),
            topRegions: top(kept.flatMap(\.regions), 8),
            topSensations: top(kept.flatMap(\.sensations), 8),
            keptLines: keptLines, writing: writing)

        // Notes from kept and let-go entries in range (owner, 2026-11-04: notes on kept entries too).
        if includeNotes {
            let notes: [(Date, ReleaseNote)] = entries.compactMap { e in
                guard let n = e.note, !n.isEmpty else { return nil }
                let d = DayAnchor.day(for: e.createdAt, timeZone: e.tz, dayStartHour: dayStartHour)
                return d >= from && d <= to ? (e.createdAt, n) : nil
            }.sorted { $0.0 < $1.0 }
            data.notes = notes
            func tally<T: Hashable & RawRepresentable>(_ xs: [T]) -> [(T, Int)] where T.RawValue == String {
                var c: [T: Int] = [:]
                for x in xs { c[x, default: 0] += 1 }
                return c.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }.map { ($0.key, $0.value) }
            }
            data.missingNeeds = tally(notes.flatMap { $0.1.missingNeeds.map(\.need) })
            data.feelings = tally(notes.flatMap { $0.1.feelings })
        }
        return data
    }
}

extension ReleaseNotes {
    /// One note as plain lines for a report. Her words in quotes; list picks as words.
    public static func reportLines(_ n: ReleaseNote) -> [String] {
        var out: [String] = []
        if let h = n.happened { out.append("What happened: \(h)") }
        if let t = n.thought { out.append("Thought: \u{201C}\(t)\u{201D}") }
        if !n.feelings.isEmpty { out.append("Felt: \(n.feelings.map(\.rawValue).joined(separator: ", "))") }
        if let b = n.body { out.append("Body: \u{201C}\(b)\u{201D}") }
        if let u = n.urge { out.append("Did or wanted to: \u{201C}\(u)\u{201D}") }
        if let i = n.intensity {
            out.append("How strong it read: \(i.title.lowercased())" + (n.intensityQuote.map { " (\u{201C}\($0)\u{201D})" } ?? ""))
        }
        func q(_ s: String) -> String { s.isEmpty ? "" : " (\u{201C}\(s)\u{201D})" }
        for need in n.missingNeeds { out.append("Need that seemed missing: \(need.need.title.lowercased())" + q(need.quote)) }
        for need in n.metNeeds { out.append("Need that was met: \(need.need.title.lowercased())" + q(need.quote)) }
        for h in n.helped { out.append("What helped: \u{201C}\(h)\u{201D}") }
        return out
    }
}

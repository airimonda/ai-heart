import Foundation
import SwiftData

// Labs, the weekly body check and the dose log (M7). Describes; never advises on dose
// (CLAUDE.md #3, docs/06). The app never guesses a lab value: it shows how she feels
// beside her labs.

/// The two groups of the weekly check. Keys are the words she taps; the group says which
/// way the check leans. Stored as one map of scores on `BodyCheck.signs`.
public enum BodySigns {
    public static let lower = ["Tired", "Cold", "Foggy", "Low", "Constipated", "Dry skin or hair", "Heavier periods"]
    public static let higher = ["Racing heart", "Hot or sweaty", "Shaky", "Anxious", "Short sleep", "Loose stools", "Lighter periods"]

    /// Scores for the keys of one group.
    public static func scores(_ signs: [String: Int], in group: [String]) -> [String: Int] {
        signs.filter { group.contains($0.key) }
    }
}

public enum TookAsUsual: String, CaseIterable, Sendable {
    case yes, mostly, no

    public var label: String {
        switch self {
        case .yes: "Yes"
        case .mostly: "Mostly"
        case .no: "Not really"
        }
    }
}

/// Weekly body check-in. One per week. Scores: 0 none, 1 some, 2 a lot.
@Model
public final class BodyCheck {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    /// Key of the anchored day the week starts on (Monday).
    public var weekKey: String = ""
    /// What she ticked, by the words in `BodySigns`.
    @Attribute(.allowsCloudEncryption) public var signs: [String: Int] = [:]
    @Attribute(.allowsCloudEncryption) public var tookAsUsualRaw: String?

    public init(week: AnchoredDay) { self.weekKey = week.key }

    public var tookAsUsual: TookAsUsual? {
        get { tookAsUsualRaw.flatMap(TookAsUsual.init(rawValue:)) }
        set { tookAsUsualRaw = newValue?.rawValue }
    }
}

/// One value from a lab report: one marker, one date. Results read from the same report
/// share a `reportId`.
@Model
public final class LabResult {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    public var date: Date = Date()
    /// Catalogue code (`LabMarkers`).
    @Attribute(.allowsCloudEncryption) public var marker: String = ""
    @Attribute(.allowsCloudEncryption) public var value: Double?
    @Attribute(.allowsCloudEncryption) public var unit: String?
    /// The lab's own reference range, as printed on the report.
    @Attribute(.allowsCloudEncryption) public var low: Double?
    @Attribute(.allowsCloudEncryption) public var high: Double?
    @Attribute(.allowsCloudEncryption) public var note: String?
    /// "screenshot" when read from an image, "manual" when typed.
    public var sourceRaw: String = "manual"
    /// Where the lab is (LabRegion raw value); picks the typical range when the report has none.
    public var labRegionRaw: String?
    /// Groups the results of one report.
    public var reportId: UUID?

    public init(date: Date, marker: String) { self.date = date; self.marker = marker }
}

@Model
public final class DoseChange {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    public var date: Date = Date()
    @Attribute(.allowsCloudEncryption) public var fromText: String = ""
    @Attribute(.allowsCloudEncryption) public var toText: String = ""

    public init(date: Date, from: String, to: String) {
        self.date = date; self.fromText = from; self.toText = to
    }
}

/// A dose she took. Manual for now; Apple Health medications are not read yet (docs/09 #1).
@Model
public final class MedicationLog {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    @Attribute(.allowsCloudEncryption) public var medicationRef: String = "daily"
    public var takenAt: Date = Date()
    public var sourceRaw: String = "manual"
    /// What she took it with, if she says.
    @Attribute(.allowsCloudEncryption) public var with: [String] = []

    public init(takenAt: Date) { self.takenAt = takenAt }
}

public enum BodyBalance {
    /// Weeks after a dose change are read with care: symptoms and signals trail it.
    public static let lagWeeks = 6
    public static let nearNeither = 0.15

    public enum Side: Sendable, Equatable { case lower, higher, neither

        public var label: String {
            switch self {
            case .lower: "Lower side"
            case .higher: "Higher side"
            case .neither: "Near neither"
            }
        }
    }

    public struct Week: Sendable, Identifiable {
        public let start: AnchoredDay
        /// -1 (lower side) ... 1 (higher side). Nil when there is nothing to go on.
        public let index: Double?
        public let hasCheck: Bool
        /// Within `lagWeeks` after a dose change.
        public let lagged: Bool
        public var id: Int { start.ordinal }

        public init(start: AnchoredDay, index: Double?, hasCheck: Bool, lagged: Bool) {
            self.start = start; self.index = index; self.hasCheck = hasCheck; self.lagged = lagged
        }

        public var side: Side {
            guard let index else { return .neither }
            return abs(index) < nearNeither ? .neither : (index > 0 ? .higher : .lower)
        }
    }

    /// Symptom part: (higher - lower) scaled to -1...1 by the most a week could score.
    public static func symptomScore(signs: [String: Int]) -> Double {
        let l = BodySigns.scores(signs, in: BodySigns.lower).values.reduce(0, +)
        let h = BodySigns.scores(signs, in: BodySigns.higher).values.reduce(0, +)
        let maxSide = Double(2 * max(BodySigns.lower.count, BodySigns.higher.count))
        return max(-1, min(1, Double(h - l) / maxSide * 2))
    }

    /// Signal part from the week's mean robust z-scores (cycle-adjusted when available).
    /// Higher resting HR and temperature, lower HRV and shorter sleep lean to the higher side.
    public static func signalScore(rhrZ: Double?, hrvZ: Double?, tempZ: Double?, sleepZ: Double?) -> Double? {
        let parts = [rhrZ, hrvZ.map { -$0 }, tempZ, sleepZ.map { -$0 }].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        let m = parts.reduce(0, +) / Double(parts.count)
        return max(-1, min(1, m / 2))
    }

    /// The weekly check counts more than the watch: signals move for many reasons.
    public static func combine(symptoms: Double?, signals: Double?) -> Double? {
        switch (symptoms, signals) {
        case let (s?, g?): return 0.6 * s + 0.4 * g
        case let (s?, nil): return s
        case let (nil, g?): return g
        default: return nil
        }
    }

    public static func isLagged(_ week: AnchoredDay, doseChanges: [AnchoredDay]) -> Bool {
        doseChanges.contains { d in
            let diff = week.ordinal - d.ordinal
            return diff >= -6 && diff < lagWeeks * 7
        }
    }

    /// One calm paragraph. Says where the balance sat and, around a dose change, how it moved.
    public static func describe(_ weeks: [Week], doseChangeWeek: AnchoredDay?) -> String {
        let known = weeks.filter { $0.index != nil }
        guard known.count >= 3 else {
            return "Not yet. A few weekly checks or weeks of watch readings will fill this in."
        }
        let tail = " This is not a lab value. Only a lab test measures that; this shows how you felt between tests."
        if let dc = doseChangeWeek {
            let before = known.filter { $0.start < dc }.compactMap(\.index)
            let after = known.filter { $0.start >= dc }.compactMap(\.index)
            if before.count >= 2, after.count >= 2 {
                let b = before.reduce(0, +) / Double(before.count), a = after.reduce(0, +) / Double(after.count)
                func word(_ v: Double) -> String { abs(v) < nearNeither ? "near neither side" : (v > 0 ? "the higher side" : "the lower side") }
                let moved = word(b) == word(a) ? "How you felt stayed on \(word(a)) around the dose change." :
                    "How you felt moved from \(word(b)) to \(word(a)) around the dose change."
                return moved + " Symptoms trail a change by several weeks, so the weeks right after one are read with care." + tail
            }
        }
        let recent = known.suffix(4).compactMap(\.index)
        let m = recent.reduce(0, +) / Double(recent.count)
        let lead = abs(m) < nearNeither ? "Recent weeks sat near neither side." : "Recent weeks leaned to the \(m > 0 ? "higher" : "lower") side."
        return lead + tail
    }
}

public enum LabCadence {
    /// Her usual gap between blood tests: the median of past gaps, in days. Nil with fewer than two labs.
    public static func usualGapDays(_ dates: [Date]) -> Int? {
        let d = dates.sorted()
        guard d.count >= 2 else { return nil }
        let gaps = zip(d, d.dropFirst()).map { $1.timeIntervalSince($0) / 86400 }.filter { $0 >= 14 }
        guard !gaps.isEmpty else { return nil }
        return Int(Baselines.median(gaps).rounded())
    }

    /// When her next test usually falls, from her own rhythm. Informational only.
    public static func nextTypical(_ dates: [Date]) -> Date? {
        guard let gap = usualGapDays(dates), let last = dates.max() else { return nil }
        return last.addingTimeInterval(Double(gap) * 86400)
    }
}

public enum LabRegion: String, CaseIterable, Sendable {
    case japan, philippines, elsewhere

    public var label: String {
        switch self {
        case .japan: "Japan"
        case .philippines: "Philippines"
        case .elsewhere: "Elsewhere"
        }
    }

    /// Her last lab's region, else the phone's region.
    public static func guess(previous: [String?], localeRegion: String?) -> LabRegion {
        if let r = previous.lazy.compactMap({ $0.flatMap(LabRegion.init(rawValue:)) }).first { return r }
        switch localeRegion { case "JP": return .japan; case "PH": return .philippines; default: return .elsewhere }
    }
}

extension LabResult {
    public var labRegion: LabRegion {
        get { labRegionRaw.flatMap(LabRegion.init(rawValue:)) ?? .elsewhere }
        set { labRegionRaw = newValue.rawValue }
    }

    public var markerName: String { LabMarkers.name(marker) }

    /// The lab's own range when the report printed one.
    public var labRange: (Double, Double)? {
        low.flatMap { lo in high.map { (lo, $0) } }
    }

    /// The lab's own range when the report printed one; otherwise the typical range for
    /// the unit when the catalogue has one, flagged so the UI can say "typical".
    public var shownRange: (low: Double, high: Double, fromLab: Bool)? {
        if let r = labRange { return (r.0, r.1, true) }
        guard let u = unit, let r = LabMarkers.typicalRange(marker, unit: u, region: labRegion) else { return nil }
        return (r.0, r.1, false)
    }
}

/// The results of one report, shown together under its date.
public struct LabReport: Identifiable {
    public let id: String
    public let date: Date
    /// In catalogue order, then by code.
    public let results: [LabResult]

    /// Groups results by report, newest report first. Results without a `reportId` are
    /// grouped by calendar day.
    public static func group(_ results: [LabResult], calendar: Calendar = .current) -> [LabReport] {
        var buckets: [String: [LabResult]] = [:]
        for r in results {
            let key = r.reportId.map { "r:" + $0.uuidString } ?? "d:" + String(Int(calendar.startOfDay(for: r.date).timeIntervalSince1970))
            buckets[key, default: []].append(r)
        }
        let order = Dictionary(uniqueKeysWithValues: LabMarkers.all.enumerated().map { ($1.code, $0) })
        return buckets.map { key, rs in
            LabReport(id: key, date: rs.map(\.date).max() ?? Date(),
                      results: rs.sorted { (order[$0.marker] ?? 999, $0.marker) < (order[$1.marker] ?? 999, $1.marker) })
        }
        .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }
}

/// Morning sleep check-in, for nights without a watch (owner, 2026-11-01).
public enum SleepCheckIn {
    /// Minutes asleep from bedtime to wake time; a wake time before bedtime means the next day.
    public static func minutes(bed: Date, wake: Date) -> Double {
        var w = wake
        while w <= bed { w = w.addingTimeInterval(86400) }
        return min(w.timeIntervalSince(bed) / 60, 16 * 60)
    }

    /// Her usual bed and wake times (minutes after midnight), from past check-ins.
    /// Bedtimes after midnight count as late, not early, so 23:30 and 00:30 average near midnight.
    public static func usual(bedMinutes: [Int], wakeMinutes: [Int]) -> (bed: Int, wake: Int) {
        let bed = bedMinutes.isEmpty ? 23 * 60 : Int(Baselines.median(bedMinutes.map { Double($0 < 12 * 60 ? $0 + 1440 : $0) })) % 1440
        let wake = wakeMinutes.isEmpty ? 7 * 60 : Int(Baselines.median(wakeMinutes.map(Double.init)))
        return (bed, wake)
    }

    /// Bed and wake as dates for the night that ends on `wakeDay`.
    public static func dates(wakeDay: AnchoredDay, bedMinute: Int, wakeMinute: Int, timeZone: TimeZone) -> (bed: Date, wake: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let day = cal.date(from: DateComponents(year: wakeDay.year, month: wakeDay.month, day: wakeDay.day))!
        let wake = day.addingTimeInterval(Double(wakeMinute) * 60)
        var bed = day.addingTimeInterval(Double(bedMinute) * 60)
        if bed >= wake { bed = bed.addingTimeInterval(-86400) }
        return (bed, wake)
    }
}

import Foundation
import SwiftData

// Spreadsheet export (M11, docs/05). Plain tables, units in the headers, one sheet per kind of data.
// Rules: released entries are never exported; resting entries only as their kept lines; no About me,
// quiet topics, seed text or app feedback; sample (demo) rows are left out.

public struct ExportOptions {
    public var from: Date?
    public var to: Date?
    /// Days, Workouts and Hevy sets. Off drops those three sheets.
    public var includeBody: Bool
    /// The words she wrote. Off by default; mood, word and body map still export without it.
    public var includeJournalText: Bool

    public init(from: Date? = nil, to: Date? = nil, includeBody: Bool = true, includeJournalText: Bool = false) {
        self.from = from
        self.to = to
        self.includeBody = includeBody
        self.includeJournalText = includeJournalText
    }
}

public enum SpreadsheetExport {
    public static func sheets(context: ModelContext, options: ExportOptions) throws -> [Sheet] {
        let notDemo = { (id: String) in id != BackupArchive.demoDeviceId }
        func inRange(_ d: Date) -> Bool {
            if let f = options.from, d < f { return false }
            if let t = options.to, d > t { return false }
            return true
        }
        /// A whole anchored day (or week) overlaps the range if any of it falls inside.
        func overlaps(key: String, tz: TimeZone, days: Int = 1) -> Bool {
            guard let day = AnchoredDay(key: key) else { return options.from == nil && options.to == nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            guard let start = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day)),
                  let end = cal.date(byAdding: .day, value: days, to: start) else { return true }
            if let f = options.from, end <= f { return false }
            if let t = options.to, start > t { return false }
            return true
        }

        var out: [Sheet] = []

        // Workouts are fetched first: Hevy sets take their date from them.
        let workouts = try context.fetch(FetchDescriptor<Workout>())
            .filter { notDemo($0.deviceId) }
            .sorted { $0.start < $1.start }
        let demoHevy = Set(try context.fetch(FetchDescriptor<Workout>()).filter { !notDemo($0.deviceId) }.compactMap(\.hevyId))

        if options.includeBody {
            let days = try context.fetch(FetchDescriptor<DaySummary>())
                .filter { notDemo($0.deviceId) && overlaps(key: $0.dayKey, tz: TimeZone(identifier: $0.tz) ?? .current) }
                .sorted { $0.dayKey < $1.dayKey }
            out.append(Sheet(
                name: "Days",
                header: ["Date", "Sleep (h)", "Deep sleep (min)", "REM sleep (min)", "Core sleep (min)", "Resting HR (bpm)",
                         "HRV SDNN (ms)", "Breathing (breaths/min)", "Wrist temp (°C)", "Steps", "Active energy (kcal)",
                         "Exercise (min)", "Menstrual flow (0 none, 1 unspecified, 2 light, 3 medium, 4 heavy)",
                         "Manual HR (bpm)", "Weight (kg)", "Systolic BP (mmHg)", "Diastolic BP (mmHg)", "Rested (1-5)"],
                rows: days.map { d in
                    [.text(d.dayKey), num(d.sleepMin.map { $0 / 60 }), num(d.sleepDeepMin), num(d.sleepRemMin), num(d.sleepCoreMin),
                     num(d.restingHR), num(d.hrvSDNN), num(d.respRate), num(d.wristTempC), num(d.steps), num(d.activeKcal),
                     num(d.exerciseMin), num(d.menstrualFlow.map(Double.init)), num(d.manualHR), num(d.weightKg),
                     num(d.systolic), num(d.diastolic), num(d.rested.map(Double.init))]
                }))
        }

        // Entries: released never; resting only as kept lines.
        let entries = try context.fetch(FetchDescriptor<Entry>())
            .filter { notDemo($0.deviceId) && $0.status != .released && inRange($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
        var entryHeader = ["Date and time", "Time zone", "Status", "Kind", "Word", "Valence", "Arousal", "Sensations", "Body regions", "Kept lines"]
        if options.includeJournalText { entryHeader += ["Caption", "Journal text"] }
        out.append(Sheet(name: "Entries", header: entryHeader, rows: entries.map { e in
            let kept = e.status == .kept
            var row: [Cell] = [
                .date(e.createdAt), .text(e.tz), .text(e.statusRaw), .text(e.kindRaw),
                kept ? txt(e.word) : .empty,
                kept ? num(e.valence) : .empty,
                kept ? num(e.arousal) : .empty,
                kept ? txt(e.sensations.joined(separator: "; ")) : .empty,
                kept ? txt(e.bodyRegions.joined(separator: "; ")) : .empty,
                txt(e.keptLines.joined(separator: "\n")),
            ]
            if options.includeJournalText {
                row += [kept ? txt(e.caption) : .empty, kept ? txt(e.text) : .empty]
            }
            return row
        }))

        if options.includeBody {
            let ranged = workouts.filter { inRange($0.start) }
            out.append(Sheet(
                name: "Workouts",
                header: ["Start", "Source", "Kind", "Title", "Duration (min)", "Active energy (kcal)", "Avg HR (bpm)", "RPE (1-10)", "Focus"],
                rows: ranged.map { w in
                    [.date(w.start), .text(source(of: w)), .text(w.kindRaw), txt(w.title), .number(Double(w.minutes)),
                     num(w.activeKcal), num(w.avgHR), num(w.rpe.map(Double.init)), txt(w.focusRaw)]
                }))

            let byHevy = Dictionary(workouts.compactMap { w in w.hevyId.map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
            let sets = try context.fetch(FetchDescriptor<HevySet>())
                .filter { !demoHevy.contains($0.hevyWorkoutId) }
                .filter { s in
                    if options.from == nil && options.to == nil { return true }
                    guard let w = byHevy[s.hevyWorkoutId] else { return false }
                    return inRange(w.start)
                }
                .sorted { a, b in
                    let da = byHevy[a.hevyWorkoutId]?.start ?? .distantPast, db = byHevy[b.hevyWorkoutId]?.start ?? .distantPast
                    return (da, a.hevyWorkoutId, a.exerciseIndex, a.setIndex) < (db, b.hevyWorkoutId, b.exerciseIndex, b.setIndex)
                }
            out.append(Sheet(
                name: "Hevy sets",
                header: ["Workout start", "Exercise", "Exercise #", "Set #", "Set type", "Weight (kg)", "Reps", "RPE", "Distance (m)", "Duration (s)"],
                rows: sets.map { s in
                    [byHevy[s.hevyWorkoutId].map { .date($0.start) } ?? .empty, .text(s.exerciseName),
                     .number(Double(s.exerciseIndex + 1)), .number(Double(s.setIndex + 1)), .text(s.setType),
                     num(s.weightKg), num(s.reps.map(Double.init)), num(s.rpe), num(s.distanceM), num(s.durationSec)]
                }))
        }

        let labs = try context.fetch(FetchDescriptor<LabResult>())
            .filter { notDemo($0.deviceId) && inRange($0.date) }
            .sorted { ($0.date, $0.marker) < ($1.date, $1.marker) }
        out.append(Sheet(
            name: "Labs",
            header: ["Date", "Marker", "Value", "Unit", "Range low", "Range high", "Lab region", "Source"],
            rows: labs.map { l in
                [.date(l.date), .text(l.markerName), num(l.value), txt(l.unit), num(l.low), num(l.high), txt(l.labRegionRaw), .text(l.sourceRaw)]
            }))

        let doses = try context.fetch(FetchDescriptor<DoseChange>())
            .filter { notDemo($0.deviceId) && inRange($0.date) }
            .sorted { $0.date < $1.date }
        out.append(Sheet(name: "Dose changes", header: ["Date", "From", "To"],
                         rows: doses.map { [.date($0.date), .text($0.fromText), .text($0.toText)] }))

        let log = try context.fetch(FetchDescriptor<MedicationLog>())
            .filter { notDemo($0.deviceId) && inRange($0.takenAt) }
            .sorted { $0.takenAt < $1.takenAt }
        out.append(Sheet(name: "Dose log", header: ["Taken at", "Medication", "Taken with", "Source"],
                         rows: log.map { [.date($0.takenAt), .text($0.medicationRef), txt($0.with.joined(separator: "; ")), .text($0.sourceRaw)] }))

        let checks = try context.fetch(FetchDescriptor<BodyCheck>())
            .filter { notDemo($0.deviceId) && overlaps(key: $0.weekKey, tz: .current, days: 7) }
            .sorted { $0.weekKey < $1.weekKey }
        let symptoms = BodySigns.lower.map { ("Lower side: " + $0, $0) } + BodySigns.higher.map { ("Higher side: " + $0, $0) }
        out.append(Sheet(
            name: "Weekly checks",
            header: ["Week starting"] + symptoms.map { $0.0 + " (0 none, 1 some, 2 a lot)" } + ["Took medication as usual"],
            rows: checks.map { c in
                [.text(c.weekKey)]
                    + symptoms.map { s in c.signs[s.1].map { .number(Double($0)) } ?? .empty }
                    + [txt(c.tookAsUsual?.label)]
            }))

        // Media is display-only (CLAUDE.md #6); it exports as her own data and the column says so.
        let media = try context.fetch(FetchDescriptor<MediaItem>())
            .filter { notDemo($0.deviceId) && inRange($0.startedAt) }
            .sorted { ($0.startedAt, $0.sourceRaw, $0.title) < ($1.startedAt, $1.sourceRaw, $1.title) }
        out.append(Sheet(
            name: "Media",
            header: ["Source", "Title", "Creator", "Started", "Length (min, only where known)"],
            rows: media.map { m in
                [.text(m.source.label + " (display only)"), .text(m.title), txt(m.creator), .date(m.startedAt),
                 num(m.durationSec.map { $0 / 60 })]
            }))

        return out
    }

    // MARK: Helpers

    private static func num(_ v: Double?) -> Cell { v.map { .number($0) } ?? .empty }
    private static func txt(_ v: String?) -> Cell { (v?.isEmpty ?? true) ? .empty : .text(v!) }

    /// Strava rows are display-only (CLAUDE.md #6); the column says so.
    private static func source(of w: Workout) -> String {
        if !w.aiEligible { return "Strava (display only)" }
        var parts: [String] = []
        if w.healthId != nil { parts.append("Apple Health") }
        if w.hevyId != nil { parts.append("Hevy") }
        return parts.isEmpty ? "AiHeart" : parts.joined(separator: " + ")
    }
}

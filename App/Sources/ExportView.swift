import AiHeartCore
import Charts
import SwiftData
import SwiftUI

/// Export (screen 20). Nothing leaves unless she sends it; the staged file is deleted when
/// the share sheet closes. An on-device log keeps date, type and range, never contents.
struct ExportView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query private var summaries: [DaySummary]
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query private var workouts: [Workout]
    @Query(sort: \AboutMe.updatedAt) private var aboutRows: [AboutMe]
    @Query(sort: \LabResult.date) private var labs: [LabResult]
    @Query(sort: \DoseChange.date) private var doses: [DoseChange]
    @Query private var checks: [BodyCheck]
    @Query(sort: \MedicationLog.takenAt, order: .reverse) private var logs: [MedicationLog]
    @Query(sort: \AppFeedback.createdAt) private var appNotes: [AppFeedback]
    @Query private var guessRows: [GuessFeedback]

    @State private var kind = 0
    @State private var range = 2
    @State private var aboutMe = true
    @State private var patterns = true
    @State private var body_ = true
    @State private var includeLabs = true
    @State private var helped = true
    @State private var notes = true
    @State private var writing = false
    @State private var safety = false
    @State private var shareURL: URL?
    @State private var making = false
    @State private var dataFormat = 0
    @State private var passphrase = ""
    @State private var passphrase2 = ""
    @State private var exportError: String?

    private var passphraseOK: Bool { passphrase.count >= 8 && passphrase == passphrase2 }

    static let ranges = [("3 months", 91), ("6 months", 182), ("1 year", 365), ("All time", 36500)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    Text("When you want it. Only where you send it.").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Picker("Kind", selection: $kind) {
                    Text("Therapist").tag(0)
                    Text("Doctor").tag(1)
                    Text("My data").tag(3)
                    Text("Feedback").tag(2)
                }
                .pickerStyle(.segmented)

                if kind == 3 { MyDataOptions(range: $range, format: $dataFormat, writing: $writing, passphrase: $passphrase, passphrase2: $passphrase2) }
                else if kind == 0 { therapistOptions } else if kind == 1 { doctorOptions } else {
                    Text("Your notes about the app (\(appNotes.count)) and how its guesses have fit, as a text file to send to whoever works on AiHeart. No journal content.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }

                Button(making ? "Preparing…" : "Export", action: export)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(making || (kind == 3 && dataFormat == 2 && !passphraseOK))
                if let exportError { Text(exportError).font(.footnote).foregroundStyle(Palette.ink) }
                if kind == 3 && dataFormat == 2 { RestoreBackupSection() }
                PastExports()

                Text("Released entries are never included. They are gone.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-makeMyData") {
                kind = 3; dataFormat = 0; range = 3
                export()
                if let u = shareURL {
                    let dest = URL.documentsDirectory.appendingPathComponent("mydata.pdf")
                    try? FileManager.default.removeItem(at: dest); try? FileManager.default.copyItem(at: u, to: dest)
                    shareURL = nil
                }
                dataFormat = 1; export()
                if let u = shareURL {
                    let dest = URL.documentsDirectory.appendingPathComponent("mydata.xlsx")
                    try? FileManager.default.removeItem(at: dest); try? FileManager.default.copyItem(at: u, to: dest)
                    shareURL = nil
                }
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("-makeReport") else { return }
            writing = true
            export()
            if let u = shareURL {
                let dest = URL.documentsDirectory.appendingPathComponent("report.pdf")
                try? FileManager.default.removeItem(at: dest); try? FileManager.default.copyItem(at: u, to: dest)
                shareURL = nil
            }
        }
        #endif
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { if $0 == nil { shareURL = nil } })) { item in
            ActivityView(url: item.url)
                .onDisappear { try? FileManager.default.removeItem(at: item.url) }
        }
    }

    private var therapistOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A PDF that describes what you logged: mood over time, the words you used, where you felt things, patterns with their uncertainty, and the context around them. It does not diagnose.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 10) {
                Text("Range").font(.headline).foregroundStyle(Palette.ink)
                Picker("Range", selection: $range) {
                    ForEach(Array(Self.ranges.enumerated()), id: \.offset) { i, r in Text(r.0).tag(i) }
                }
                .pickerStyle(.segmented)
            }
            .padding(18).card()
            VStack(spacing: 0) {
                toggle("About me", "Your own words, as written", $aboutMe)
                toggle("Patterns", "What lines up with your mood, with uncertainty", $patterns)
                toggle("Body and cycle", "Sleep, heart, activity, cycle phase", $body_)
                toggle("Labs", "Lab results and dose changes", $includeLabs)
                toggle("What helped", "The lines you kept", $helped)
                toggle("Notes on hard moments", "Notes kept from let-go entries: reactions and needs", $notes)
                toggle("My writing", "Your entries, in full. Off unless you choose it", $writing)
                toggle("My safety plan", "Off unless you choose it", $safety, last: true)
            }
            .card()
        }
    }

    private var doctorOptions: some View {
        Text("The one-page summary: labs, dose changes, how you felt between tests, and doses logged. No journal text.")
            .font(.subheadline).foregroundStyle(Palette.muted)
    }

    private func toggle(_ title: String, _ sub: String, _ on: Binding<Bool>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            RuleToggle(title: title, subtitle: sub, isOn: on)
            if !last { Divider().overlay(Palette.line).padding(.leading, 18) }
        }
    }

    private func export() {
        making = true
        exportError = nil
        defer { making = false }
        let s = settingsRows.first
        let snap = BodySnapshot.cached(summaries, settings: s)
        if kind == 3 { exportMyData(snap: snap, dayStart: s?.dayStartHour ?? 4); return }
        if kind == 2 {
            var lines = ["AiHeart feedback, \(Date.now.formatted(date: .long, time: .omitted))", ""]
            for n in appNotes {
                lines.append("\(n.createdAt.formatted(date: .abbreviated, time: .omitted))\(n.mood.map { " · " + $0 } ?? ""): \(n.text)")
            }
            let lean = GuessLog.leanSummary(guessRows, entries: entries, dayStart: s?.dayStartHour ?? 4)
            lines.append("")
            lines.append("Mood lean: " + (LeanRecord.text(lean) ?? "no answers yet"))
            let words = guessRows.filter { $0.kind == "words" }
            lines.append("Suggested words: picked one of the suggestions \(words.filter { $0.picked != nil }.count) of \(words.count) times.")
            let photo = guessRows.filter { $0.kind == "photoCaption" }
            lines.append("Photo captions: used \(photo.filter { $0.picked != nil }.count) of \(photo.count) times.")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AiHeart feedback.txt")
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
            ExportLog.add("App feedback", range: "all")
            return
        }
        if kind == 1 {
            let model = BodyBalanceModel(snap: snap, checks: checks, doses: doses, labs: labs, dayStart: s?.dayStartHour ?? 4)
            shareURL = DoctorSummary.makePDF(model: model, doses: doses.reversed(), labs: labs.reversed(), logs: logs, checks: checks)
            ExportLog.add("For my doctor", range: "12 weeks")
            return
        }
        let days = Self.ranges[range].1
        let to = snap.today
        let firstEntry = entries.first.map { DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: s?.dayStartHour ?? 4) } ?? to
        let from = max(to.adding(days: -days + 1), firstEntry)
        let data = TherapistReport.build(entries: entries.map(ReportEntry.init), from: from, to: to, dayStartHour: s?.dayStartHour ?? 4,
                                         includeWriting: writing, includeNotes: notes, weekStart: BodyBalanceModel.monday)
        let input = PatternInputBuilder.make(snap: snap, entries: entries.filter { e in
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: s?.dayStartHour ?? 4)
            return d >= from && d <= to
        }, workouts: workouts, dayStart: s?.dayStartHour ?? 4)
        let opts = TherapistPDF.Options(aboutMe: aboutMe ? aboutRows.first?.markdown : nil, patterns: patterns, body: body_,
                                        labs: includeLabs && (s?.usesLabs ?? true), helped: helped,
                                        safety: safety ? s.map { SafetyPlan.sections(from: $0).map { ($0.title, $0.text) } } : nil)
        shareURL = TherapistPDF.make(data: data, input: input, snap: snap, labs: labs, doses: doses, options: opts)
        ExportLog.add("For a therapist", range: Self.ranges[range].0)
    }
}

extension ExportView {
    fileprivate func exportMyData(snap: BodySnapshot, dayStart: Int) {
        let to = snap.today
        let firstEntry = entries.first.map { DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: dayStart) } ?? to
        let firstDay = summaries.compactMap(\.day).min() ?? firstEntry
        let from = max(to.adding(days: -Self.ranges[range].1 + 1), min(firstEntry, firstDay))
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        switch dataFormat {
        case 0:
            shareURL = MyDataPDF.make(summaries: summaries, entries: entries, workouts: workouts, labs: labs, doses: doses, checks: checks,
                                      dayStart: dayStart, demo: DemoData.isOn(context),
                                      options: .init(from: from, to: to, includeWriting: writing, includeLabs: settingsRows.first?.usesLabs ?? true))
            ExportLog.add("My data report", range: Self.ranges[range].0)
        case 1:
            do {
                let opts = ExportOptions(from: from.date(in: .current), to: to.adding(days: 1).date(in: .current), includeBody: true, includeJournalText: writing)
                let data = XLSXWriter.make(try SpreadsheetExport.sheets(context: context, options: opts))
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("AiHeart data \(stamp).xlsx")
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                shareURL = url
                ExportLog.add("Spreadsheet", range: Self.ranges[range].0)
            } catch { exportError = "Could not make the spreadsheet." }
        default:
            do {
                let sealed = try BackupCrypto.seal(try BackupArchive.make(context: context), passphrase: passphrase)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("AiHeart backup \(stamp).aiheart")
                try sealed.write(to: url, options: [.atomic, .completeFileProtection])
                shareURL = url
                passphrase = ""; passphrase2 = ""
                ExportLog.add("Locked backup", range: "everything")
            } catch { exportError = "Could not make the backup." }
        }
    }
}

/// Options for "My data": a report, a spreadsheet, or a locked backup of everything.
struct MyDataOptions: View {
    @Binding var range: Int
    @Binding var format: Int
    @Binding var writing: Bool
    @Binding var passphrase: String
    @Binding var passphrase2: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Format", selection: $format) {
                Text("Report").tag(0)
                Text("Spreadsheet").tag(1)
                Text("Backup").tag(2)
            }
            .pickerStyle(.segmented)
            Text(explainer).font(.subheadline).foregroundStyle(Palette.muted)
            if format < 2 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Range").font(.headline).foregroundStyle(Palette.ink)
                    Picker("Range", selection: $range) {
                        ForEach(Array(ExportView.ranges.enumerated()), id: \.offset) { i, r in Text(r.0).tag(i) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(18).card()
                RuleToggle(title: "Include my writing", subtitle: "Your entries' text. Off unless you choose it", isOn: $writing).card()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("Passphrase (8 or more characters)", text: $passphrase).textContentType(.newPassword)
                    Divider()
                    SecureField("Same passphrase again", text: $passphrase2).textContentType(.newPassword)
                    if !passphrase2.isEmpty && passphrase != passphrase2 {
                        Text("The two don't match yet.").font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                .padding(18).card()
                Text("Nobody can recover this passphrase, including AiHeart. Without it the backup cannot be opened. Keep it somewhere safe, such as your password manager.")
                    .font(.footnote).foregroundStyle(Palette.ink)
            }
        }
    }

    private var explainer: String {
        switch format {
        case 0: "A PDF with charts and tables: month by month, mood, sleep, resting heart rate, workouts, lab results, and what you noticed between tests."
        case 1: "An Excel file with a sheet for each kind of data (days, entries, workouts, labs, doses, weekly checks). Opens in Numbers or Excel."
        default: "One locked file with everything, to move AiHeart to a new phone or restore it after a reinstall. Sample data and released entries are left out."
        }
    }
}

/// Restore from a .aiheart file: pick it, type the passphrase, merge into what is here.
struct RestoreBackupSection: View {
    @Environment(\.modelContext) private var context
    @State private var picking = false
    @State private var fileData: Data?
    @State private var pass = ""
    @State private var result: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restore").font(.headline).foregroundStyle(Palette.ink)
            Text("Adds what is in a backup to this phone. Nothing here is replaced, and anything you let go stays gone.")
                .font(.footnote).foregroundStyle(Palette.muted)
            if fileData == nil {
                Button("Choose a backup file") { picking = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            } else {
                SecureField("Its passphrase", text: $pass)
                HStack {
                    Button("Cancel") { fileData = nil; pass = "" }.foregroundStyle(Palette.muted)
                    Spacer()
                    Button(working ? "Restoring…" : "Restore") { restore() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint)
                        .disabled(pass.isEmpty || working)
                }
                .frame(minHeight: 44)
            }
            if let result { Text(result).font(.footnote).foregroundStyle(Palette.ink) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            fileData = try? Data(contentsOf: url)
            result = fileData == nil ? "Could not read that file." : nil
        }
    }

    private func restore() {
        guard let fileData else { return }
        working = true
        defer { working = false }
        do {
            let plain = try BackupCrypto.open(fileData, passphrase: pass)
            let summary = try BackupArchive.restore(plain, into: context)
            // Tombstones from the backup win over any older copy here (CLAUDE.md #9).
            try? EntryLifecycle.runPurgeJob(in: context)
            let total = summary.added.values.reduce(0, +)
            result = total == 0 ? "Everything in that backup is already here." : "Restored \(total) items. \(summary.skipped) were already here."
            self.fileData = nil; pass = ""
            NSLog("AiHeartUI restore: added=%d skipped=%d", total, summary.skipped)
        } catch BackupError.wrongPassphrase {
            result = "That passphrase doesn't open this backup."
        } catch BackupError.notABackup {
            result = "That file isn't an AiHeart backup."
        } catch {
            result = "Could not restore that backup. Nothing was changed."
        }
    }
}

/// Date, type and range of past exports, on this phone only.
struct PastExports: View {
    @State private var log: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !log.isEmpty {
                Text("Past exports").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                ForEach(log.suffix(5).reversed(), id: \.self) { l in
                    Text(ExportLog.pretty(l)).font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
        .onAppear { log = UserDefaults.standard.stringArray(forKey: "export.log") ?? [] }
    }
}

/// Date, type and range of each export. Never the contents (docs/05).
enum ExportLog {
    static func add(_ type: String, range: String) {
        var log = UserDefaults.standard.stringArray(forKey: "export.log") ?? []
        log.append("\(Date.now.formatted(.iso8601)) · \(type) · \(range)")
        UserDefaults.standard.set(Array(log.suffix(50)), forKey: "export.log")
    }

    static func pretty(_ line: String) -> String {
        let parts = line.components(separatedBy: " · ")
        guard let first = parts.first, let d = try? Date(first, strategy: .iso8601) else { return line }
        return ([d.formatted(date: .abbreviated, time: .shortened)] + parts.dropFirst()).joined(separator: " · ")
    }
}

/// Lays out report blocks onto A4 pages, breaking only between blocks.
@MainActor
enum PDFPager {
    static let page = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40

    static func write(blocks: [AnyView], to url: URL) -> Bool {
        let width = page.width - 2 * margin
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        var y: CGFloat = margin
        var open = false
        func newPage() {
            if open { pdf.endPDFPage() }
            pdf.beginPDFPage(nil); open = true; y = margin
        }
        newPage()
        for block in blocks {
            let r = ImageRenderer(content: block.frame(width: width, alignment: .leading).environment(\.colorScheme, .light))
            r.proposedSize = ProposedViewSize(width: width, height: nil)
            r.render { size, draw in
                if y + size.height > page.height - margin && y > margin { newPage() }
                pdf.saveGState()
                // PDF origin is bottom-left; place the block's top at y.
                pdf.translateBy(x: margin, y: page.height - y - size.height)
                draw(pdf)
                pdf.restoreGState()
                y += size.height + 14
            }
        }
        pdf.endPDFPage()
        pdf.closePDF()
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return true
    }
}

@MainActor
enum TherapistPDF {
    struct Options {
        var aboutMe: String?
        var patterns: Bool
        var body: Bool
        var labs: Bool
        var helped: Bool
        var safety: [(title: String, text: String)]?
    }

    static func make(data: TherapistReportData, input: PatternInput, snap: BodySnapshot, labs: [LabResult], doses: [DoseChange], options: Options) -> URL? {
        let cal = Calendar.current
        let fromDate = data.from.date(in: cal), toDate = data.to.date(in: cal)
        var blocks: [AnyView] = []

        blocks.append(AnyView(VStack(alignment: .leading, spacing: 4) {
            Text("A summary of my records").font(.system(size: 22, weight: .bold))
            Text("\(fromDate.formatted(date: .long, time: .omitted)) to \(toDate.formatted(date: .long, time: .omitted))").font(.system(size: 11))
            Text("\(data.entryCount) entries on \(data.daysWithEntries) days. Prepared by me from my own records in AiHeart. It describes what I logged; it does not diagnose.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }))

        if let md = options.aboutMe {
            let doc = AboutMeDoc.parse(md)
            let filled = doc.sections.filter { !$0.body.isEmpty }
            if !filled.isEmpty {
                blocks.append(heading("About me, in my words"))
                for s in filled { blocks.append(AnyView(section(s.title, s.body))) }
            }
        }

        if !data.weeks.isEmpty {
            blocks.append(heading("Mood over time"))
            blocks.append(AnyView(VStack(alignment: .leading, spacing: 4) {
                Chart {
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(.gray.opacity(0.4))
                    ForEach(data.weeks) { w in
                        LineMark(x: .value("Week", w.start.date(in: cal)), y: .value("Pleasant", w.valence), series: .value("Axis", "pleasant"))
                            .foregroundStyle(Color(red: 0.76, green: 0.27, blue: 0.47))
                        LineMark(x: .value("Week", w.start.date(in: cal)), y: .value("Stirred", w.arousal), series: .value("Axis", "stirred"))
                            .foregroundStyle(Color(red: 0.55, green: 0.48, blue: 0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: -1...1)
                .chartYAxis { AxisMarks(values: [-1, 0, 1]) }
                .frame(height: 150)
                Text("Weekly averages of the mood point I placed. Solid: unpleasant (−1) to pleasant (+1). Dashed: still (−1) to stirred (+1).")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }))
        }

        if !data.topWords.isEmpty {
            blocks.append(AnyView(section("Words I used most", data.topWords.map { "\($0.0) (\($0.1))" }.joined(separator: ", "))))
        }
        if !data.topRegions.isEmpty {
            let r = data.topRegions.map { "\(BodyRegion.label(for: $0.0)) (\($0.1))" }.joined(separator: ", ")
            let s = data.topSensations.map { "\($0.0.lowercased()) (\($0.1))" }.joined(separator: ", ")
            blocks.append(AnyView(section("Where I felt it", r + (s.isEmpty ? "" : ". Felt as: " + s))))
        }

        if options.patterns {
            blocks.append(heading("Patterns"))
            blocks.append(AnyView(section("Sleep and the next day", Patterns.describeSleep(Patterns.sleepScatter(input)))))
            blocks.append(AnyView(section("Lifting days and mood", Patterns.describeLift(Patterns.liftGroups(input)))))
            if snap.cycle != nil {
                blocks.append(AnyView(section("Mood by cycle phase", Patterns.describePhases(Patterns.phaseGroups(input)))))
            }
            let links = Patterns.links(input).map { l -> String in
                guard let iv = l.interval else { return "\(l.title): not enough days yet (\(l.pairs) of \(Patterns.minPairs))" }
                return "\(l.title): \(String(format: "%.2f", iv.estimate)) (95% interval \(String(format: "%.2f", iv.low)) to \(String(format: "%.2f", iv.high)), \(iv.n) days)\(iv.excludesZero ? ", clearer than chance" : ", unclear")"
            }
            blocks.append(AnyView(section("Signals and the next day's mood (rank correlation)", links.joined(separator: "\n"))))
        }

        if options.body {
            var lines: [String] = []
            var monthStart = cal.date(from: cal.dateComponents([.year, .month], from: fromDate)) ?? fromDate
            while monthStart <= toDate {
                let next = cal.date(byAdding: .month, value: 1, to: monthStart)!
                let days = snap.all.filter { s in
                    guard let d = s.day?.date(in: cal) else { return false }
                    return d >= monthStart && d < next
                }
                func avg(_ k: KeyPath<DaySummary, Double?>) -> Double? {
                    let v = days.compactMap { $0[keyPath: k] }; return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
                }
                var parts: [String] = []
                if let s = avg(\.sleepMin) { parts.append("sleep \(BodyFormat.duration(s))") }
                if let s = avg(\.restingHR) { parts.append("resting HR \(Int(s.rounded()))") }
                if let s = avg(\.hrvSDNN) { parts.append("HRV \(Int(s.rounded())) ms") }
                if let s = avg(\.steps) { parts.append("\(Int(s.rounded()).formatted()) steps") }
                if !parts.isEmpty { lines.append("\(monthStart.formatted(.dateTime.month(.abbreviated).year())): " + parts.joined(separator: ", ")) }
                monthStart = next
            }
            if !lines.isEmpty { blocks.append(AnyView(section("Body, monthly averages", lines.joined(separator: "\n")))) }
            if let c = snap.cycle {
                blocks.append(AnyView(section("Cycle", "Cycle length about \(c.expectedLength) days from \(c.completedCycles) recorded cycles. Phases are estimates.")))
            }
        }

        if options.labs, !(labs.isEmpty && doses.isEmpty) {
            var lines: [String] = []
            for report in LabReport.group(labs) {
                let parts = report.results.compactMap { l in
                    l.value.map { "\(l.markerName) \($0)\(l.unit.map { " " + $0 } ?? "")" }
                }
                lines.append("\(report.date.formatted(date: .abbreviated, time: .omitted)): " + parts.joined(separator: ", "))
            }
            for d in doses { lines.append("\(d.date.formatted(date: .abbreviated, time: .omitted)): dose changed from \(d.fromText) to \(d.toText)") }
            blocks.append(AnyView(section("Labs and dose changes", lines.joined(separator: "\n") + "\nThese are listed so they can be read side by side with mood and energy.")))
        }

        if options.helped, !data.keptLines.isEmpty {
            blocks.append(AnyView(section("What helped, in lines I kept", data.keptLines.map { "\($0.0.formatted(date: .abbreviated, time: .omitted)): \($0.1)" }.joined(separator: "\n"))))
        }

        if !data.notes.isEmpty {
            blocks.append(heading("Notes on hard moments"))
            var summary: [String] = ["\(data.notes.count) note\(data.notes.count == 1 ? "" : "s") on hard moments, from entries I kept or let go (let-go entries themselves are gone). Feelings and needs are picked from fixed lists (CBT five-part model; needs from self-determination theory and schema therapy); quotes are my words. Written on my phone by rules and a small on-device model; they can be wrong."]
            if !data.missingNeeds.isEmpty {
                summary.append("Needs that seemed missing most often: " + data.missingNeeds.prefix(5).map { "\($0.0.title.lowercased()) (\($0.1))" }.joined(separator: ", "))
            }
            if !data.feelings.isEmpty {
                summary.append("Feelings named most often: " + data.feelings.prefix(6).map { "\($0.0.rawValue) (\($0.1))" }.joined(separator: ", "))
            }
            blocks.append(AnyView(Text(summary.joined(separator: "\n")).font(.system(size: 10))))
            for (date, n) in data.notes {
                blocks.append(AnyView(VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10, weight: .semibold))
                    Text(ReleaseNotes.reportLines(n).joined(separator: "\n")).font(.system(size: 10))
                }))
            }
        }

        if !data.writing.isEmpty {
            blocks.append(heading("My writing"))
            for w in data.writing {
                // One block per paragraph, so long entries break cleanly across pages.
                let paras = w.text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                blocks.append(AnyView(Text("\(w.date.formatted(date: .abbreviated, time: .shortened))\(w.word.map { " · " + $0 } ?? "")")
                    .font(.system(size: 10, weight: .semibold))))
                for p in paras { blocks.append(AnyView(Text(p).font(.system(size: 10, design: .serif)))) }
            }
        }

        if let safety = options.safety, !safety.isEmpty {
            blocks.append(heading("My safety plan"))
            for part in safety { blocks.append(AnyView(section(part.title, part.text))) }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("My records \(Date.now.formatted(.iso8601.year().month().day())).pdf")
        return PDFPager.write(blocks: blocks, to: url) ? url : nil
    }

    static func heading(_ s: String) -> AnyView {
        AnyView(Text(s).font(.system(size: 15, weight: .bold)).padding(.top, 6))
    }

    static func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(body).font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
    }
}

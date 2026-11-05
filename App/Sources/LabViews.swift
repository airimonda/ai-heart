import AiHeartCore
import Charts
import SwiftData
import SwiftUI

/// Builds the weekly balance from checks, body signals and dose changes.
struct BodyBalanceModel {
    let weeks: [BodyBalance.Week]
    let doseWeeks: [AnchoredDay]
    let labWeeks: [(week: AnchoredDay, lab: LabResult)]
    let thisWeek: AnchoredDay
    let snap: BodySnapshot

    static func monday(_ d: AnchoredDay) -> AnchoredDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.component(.weekday, from: Date(timeIntervalSince1970: Double(d.ordinal) * 86400 + 43200))
        return d.adding(days: -((wd + 5) % 7))
    }

    init(snap: BodySnapshot, checks: [BodyCheck], doses: [DoseChange], labs: [LabResult], dayStart: Int, count: Int = 12) {
        self.snap = snap
        let thisWeek = Self.monday(snap.today)
        self.thisWeek = thisWeek
        let byWeek = Dictionary(checks.map { ($0.weekKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
        let doseDays = doses.map { DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart) }
        doseWeeks = doseDays.map(Self.monday)
        labWeeks = labs.map { (Self.monday(DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart)), $0) }
        weeks = (0..<count).map { i in
            let start = thisWeek.adding(days: -7 * (count - 1 - i))
            let days = (0..<7).map { start.adding(days: $0) }.filter { $0 <= snap.today }
            func meanZ(_ s: Signal) -> Double? {
                let zs = days.compactMap { snap.z(s, on: $0) }
                return zs.isEmpty ? nil : zs.reduce(0, +) / Double(zs.count)
            }
            let check = byWeek[start.key]
            let symptoms = check.map { BodyBalance.symptomScore(signs: $0.signs) }
            let signals = BodyBalance.signalScore(rhrZ: meanZ(.restingHR), hrvZ: meanZ(.hrv), tempZ: meanZ(.wristTemp), sleepZ: meanZ(.sleep))
            return BodyBalance.Week(start: start, index: BodyBalance.combine(symptoms: symptoms, signals: signals),
                                       hasCheck: check != nil, lagged: BodyBalance.isLagged(start, doseChanges: doseDays))
        }
    }

    struct Pull: Identifiable {
        let label: String
        let higher: Bool
        let strength: Int
        var id: String { label }
    }

    /// What is pulling this week: signals at least one robust SD from her usual, and
    /// what she checked. Mixed signals are normal and shown as they are.
    func pulls(check: BodyCheck?) -> [Pull] {
        let days = (0..<7).map { thisWeek.adding(days: $0) }.filter { $0 <= snap.today }
        func meanZ(_ s: Signal) -> Double? {
            let zs = days.compactMap { snap.z(s, on: $0) }
            return zs.isEmpty ? nil : zs.reduce(0, +) / Double(zs.count)
        }
        var out: [Pull] = []
        func add(_ z: Double?, up: String, down: String, upIsHigher: Bool) {
            guard let z, abs(z) >= 1 else { return }
            out.append(Pull(label: z > 0 ? up : down, higher: (z > 0) == upIsHigher, strength: abs(z) >= 2 ? 2 : 1))
        }
        add(meanZ(.restingHR), up: "Resting HR above your usual", down: "Resting HR below your usual", upIsHigher: true)
        add(meanZ(.sleep), up: "Sleep longer than usual", down: "Sleep shorter than usual", upIsHigher: false)
        add(meanZ(.hrv), up: "HRV above your usual", down: "HRV below your usual", upIsHigher: false)
        add(meanZ(.wristTemp), up: "Wrist temperature above your usual", down: "Wrist temperature below your usual", upIsHigher: true)
        if let check {
            for (k, v) in BodySigns.scores(check.signs, in: BodySigns.higher).sorted(by: { $0.value > $1.value }) where v > 0 { out.append(Pull(label: k, higher: true, strength: v)) }
            for (k, v) in BodySigns.scores(check.signs, in: BodySigns.lower).sorted(by: { $0.value > $1.value }) where v > 0 { out.append(Pull(label: k, higher: false, strength: v)) }
        }
        return out
    }
}

extension BodyBalance.Side {
    var color: Color {
        switch self {
        case .lower: Palette.pink
        case .higher: Palette.lilacFertile
        case .neither: Palette.segment
        }
    }
}

/// Labs: results, the weekly body check-in and the dose log.
struct LabsView: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query private var checks: [BodyCheck]
    @Query(sort: \DoseChange.date, order: .reverse) private var doses: [DoseChange]
    @Query(sort: \LabResult.date, order: .reverse) private var labs: [LabResult]
    @Query(sort: \MedicationLog.takenAt, order: .reverse) private var logs: [MedicationLog]
    @State private var sheet: Sheet?
    @State private var shareURL: URL?
    @State private var weeksShown = 12

    enum Sheet: String, Identifiable { case lab, dose, timing, check; var id: String { rawValue } }

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        let model = BodyBalanceModel(snap: snap, checks: checks, doses: Array(doses), labs: Array(labs),
                                 dayStart: settingsRows.first?.dayStartHour ?? 4, count: weeksShown)
        let thisCheck = checks.first { $0.weekKey == model.thisWeek.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if DemoData.isOn(context) { Text("Sample data").font(.subheadline).foregroundStyle(Palette.muted) }

                LatestLabCard(labs: Array(labs)) { sheet = .lab }

                LabHistoryCard(labs: Array(labs), doses: Array(doses))

                BetweenTestsCard(checks: checks, labs: Array(labs), doses: Array(doses),
                                 dayStart: settingsRows.first?.dayStartHour ?? 4, today: snap.today)

                if thisCheck == nil {
                    Button { sheet = .check } label: {
                        RuleRow(title: "Weekly body check-in", subtitle: "About a minute. Skip anything.", trailing: "Not done", chevron: true)
                    }
                    .buttonStyle(.plain)
                    .card()
                }

                PullCard(pulls: model.pulls(check: thisCheck), onCheck: thisCheck == nil ? nil : { sheet = .check })

                RecordsCard(doses: Array(doses.prefix(3)), reports: Array(LabReport.group(Array(labs)).prefix(3)), logs: logs, sheet: $sheet)

                Button {
                    shareURL = DoctorSummary.makePDF(model: model, doses: Array(doses), labs: Array(labs), logs: logs, checks: checks)
                } label: {
                    Text("Share a summary with my doctor")
                        .font(.headline)
                        .foregroundStyle(Palette.onTint)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay(Capsule().stroke(Palette.action, lineWidth: 1.5))
                }

                Text("Dose changes are for your doctor. This only shows what is happening. If you have chest pain, fainting, or a very fast or irregular heartbeat, contact a doctor or emergency services.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollDown") ? UnitPoint(x: 0.5, y: 0.3) : .top)
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-year") { weeksShown = 52 } }
        #endif
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Labs")
        #if DEBUG
        .onAppear {
            guard ProcessInfo.processInfo.arguments.contains("-makeSummary"),
                  let url = DoctorSummary.makePDF(model: model, doses: Array(doses), labs: Array(labs), logs: logs, checks: checks) else { return }
            let dest = URL.documentsDirectory.appendingPathComponent("summary.pdf")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        #endif
        .sheet(item: $sheet) { s in
            switch s {
            case .check: WeeklyCheckView(week: model.thisWeek)
            case .lab: AddLabView()
            case .dose: AddDoseChangeView(last: doses.first?.toText ?? "")
            case .timing: LogDoseView()
            }
        }
        .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { if $0 == nil { shareURL = nil } })) { item in
            ActivityView(url: item.url)
                .onDisappear { try? FileManager.default.removeItem(at: item.url) } // export staging is purged
        }
    }
}

struct ShareItem: Identifiable { let url: URL; var id: URL { url } }

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

/// Between tests (owner, 2026-11-01): what she ticked in her weekly check, grouped by the
/// stretches between lab tests, in her own words. Not a lab value.
struct BetweenTestsCard: View {
    let checks: [BodyCheck]
    let labs: [LabResult]
    let doses: [DoseChange]
    let dayStart: Int
    let today: AnchoredDay

    private var periods: [BetweenTests.Period] {
        let cs = checks.compactMap { c in AnchoredDay(key: c.weekKey).map { BetweenTests.Check(week: $0, symptoms: c.signs) } }
        let labDays = Set(labs.map { DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart) }).sorted()
        let ds = doses.map { (day: DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart), text: "\($0.fromText) to \($0.toText)") }
        return BetweenTests.periods(checks: cs, labDays: labDays, doses: ds, today: today)
    }

    private func date(_ d: AnchoredDay) -> String { d.date(in: .current).formatted(.dateTime.day().month(.abbreviated).year()) }

    private func title(_ p: BetweenTests.Period) -> String {
        let w = p.weeks(today: today)
        let span = w == 1 ? "1 week" : "\(w) weeks"
        switch (p.startLab, p.endLab) {
        case (let s?, nil): return "Since your \(date(s)) lab (\(span))"
        case (let s?, let e?): return "\(date(s)) → \(date(e)) labs (\(span))"
        case (nil, let e?): return "Before your \(date(e)) lab"
        case (nil, nil): return "Your weekly checks (\(span))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Between lab tests: how you felt").font(.headline).foregroundStyle(Palette.ink)
                Text("What you ticked in your weekly check, between lab tests. Not a lab value.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            if periods.isEmpty {
                Text("Nothing yet. The weekly body check-in fills this in.").font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                SymptomWeekGrid(checks: checks, labs: labs, doses: doses, dayStart: dayStart, today: today)
                Divider().overlay(Palette.line)
            }
            ForEach(Array(periods.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Divider().overlay(Palette.line) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(p)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    ForEach(p.counts.prefix(4), id: \.symptom) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(c.symptom).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(c.weeks) of \(p.checked) \(p.checked == 1 ? "week" : "weeks")").foregroundStyle(Palette.muted).monospacedDigit()
                            }
                            .font(.subheadline)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.segment)
                                    Capsule().fill(Palette.pink).frame(width: g.size.width * CGFloat(c.weeks) / CGFloat(max(1, p.checked)))
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        }
                    }
                    if let q = BetweenTests.quietLine(p) {
                        Text(q).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(p.doses.enumerated()), id: \.offset) { _, d in
                        Label("Dose changed \(d.day.date(in: .current).formatted(.dateTime.day().month(.abbreviated))): \(d.text)", systemImage: "pills")
                            .font(.footnote).foregroundStyle(Palette.ink)
                    }
                    if p.checked > 0 {
                        Text("Weekly checks done: \(p.checked)").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Rows are symptoms, columns are weeks. A filled square: ticked that week (darker: "a lot").
/// Faint dot: checked, not ticked. Blank: no check that week. Lab and dose weeks are marked on top.
struct SymptomWeekGrid: View {
    let checks: [BodyCheck]
    let labs: [LabResult]
    let doses: [DoseChange]
    let dayStart: Int
    let today: AnchoredDay
    var weeksShown = 16

    private var weeks: [AnchoredDay] {
        let now = BodyBalanceModel.monday(today)
        return (0..<weeksShown).map { now.adding(days: -7 * (weeksShown - 1 - $0)) }
    }

    private var byWeek: [String: [String: Int]] {
        var out: [String: [String: Int]] = [:]
        for c in checks { out[c.weekKey] = c.signs }
        return out
    }

    private var rows: [String] {
        var tally: [String: Int] = [:]
        for w in weeks { for (k, v) in byWeek[w.key] ?? [:] where v > 0 { tally[k, default: 0] += 1 } }
        return tally.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(6).map(\.key)
    }

    private func weekOf(_ d: Date) -> String { BodyBalanceModel.monday(DayAnchor.day(for: d, timeZone: .current, dayStartHour: dayStart)).key }

    var body: some View {
        let labWeeks = Set(labs.map { weekOf($0.date) })
        let doseWeeks = Set(doses.map { weekOf($0.date) })
        let data = byWeek
        let cols = weeks
        VStack(alignment: .leading, spacing: 6) {
            Text("Last \(weeksShown) weeks").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            if rows.isEmpty {
                Text("Nothing ticked in these weeks.").font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                GeometryReader { g in
                    let labelW: CGFloat = 96
                    let cell = max(8, min(16, (g.size.width - labelW) / CGFloat(cols.count) - 2))
                    VStack(alignment: .leading, spacing: 3) {
                        // Marks row: lab and dose weeks.
                        HStack(spacing: 2) {
                            Color.clear.frame(width: labelW, height: 14)
                            ForEach(cols, id: \.key) { w in
                                ZStack {
                                    if labWeeks.contains(w.key) {
                                        Image(systemName: "drop.fill").font(.system(size: 9)).foregroundStyle(Palette.action)
                                    } else if doseWeeks.contains(w.key) {
                                        Image(systemName: "pills.fill").font(.system(size: 9)).foregroundStyle(Palette.ink)
                                    }
                                }
                                .frame(width: cell, height: 14)
                            }
                        }
                        ForEach(rows, id: \.self) { r in
                            HStack(spacing: 2) {
                                Text(r).font(.caption).foregroundStyle(Palette.ink).lineLimit(1).frame(width: labelW, alignment: .leading)
                                ForEach(cols, id: \.key) { w in
                                    let v = data[w.key]?[r]
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(v == nil ? Color.clear : v! >= 2 ? Palette.action : v! == 1 ? Palette.pink : Palette.segment)
                                        .frame(width: cell, height: cell)
                                        .overlay {
                                            if data[w.key] == nil { Circle().fill(Palette.line).frame(width: 3, height: 3) }
                                        }
                                }
                            }
                        }
                        HStack(spacing: 2) {
                            Color.clear.frame(width: labelW, height: 12)
                            ForEach(Array(cols.enumerated()), id: \.offset) { i, w in
                                let d = w.date(in: .current)
                                let first = i == 0 || Calendar.current.component(.month, from: d) != Calendar.current.component(.month, from: cols[i - 1].date(in: .current))
                                Text(first ? d.formatted(.dateTime.month(.abbreviated)) : "")
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted).fixedSize()
                                    .frame(width: cell, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(height: CGFloat(rows.count) * 19 + 36)
                .accessibilityElement()
                .accessibilityLabel("Weeks you ticked each symptom, last \(weeksShown) weeks")
                HStack(spacing: 12) {
                    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Palette.action).frame(width: 10, height: 10); Text("a lot") }
                    HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Palette.pink).frame(width: 10, height: 10); Text("some") }
                    HStack(spacing: 4) { Image(systemName: "drop.fill").foregroundStyle(Palette.action); Text("lab") }
                    HStack(spacing: 4) { Image(systemName: "pills.fill"); Text("dose change") }
                }
                .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct PullCard: View {
    let pulls: [BodyBalanceModel.Pull]
    var onCheck: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What is pulling it this week").font(.headline).foregroundStyle(Palette.ink)
                Text("Mixed signals are normal").font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(.bottom, 8)
            if pulls.isEmpty {
                Text("Nothing stands out this week.").font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 10)
            }
            ForEach(Array(pulls.enumerated()), id: \.offset) { i, p in
                if i > 0 { Divider().overlay(Palette.line) }
                HStack {
                    Text(p.label).foregroundStyle(Palette.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { k in
                            Circle().fill(k < p.strength ? (p.higher ? Palette.lilacFertile : Palette.pink) : Palette.segment).frame(width: 10, height: 10)
                        }
                    }
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.label), \(p.higher ? "higher" : "lower") side, \(p.strength == 2 ? "a lot" : "some")")
            }
            if let onCheck {
                Button("Edit this week's check", action: onCheck)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.onTint)
                    .frame(minHeight: 44)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct RecordsCard: View {
    let doses: [DoseChange]
    let reports: [LabReport]
    let logs: [MedicationLog]
    @Binding var sheet: LabsView.Sheet?
    @State private var editingReport: LabReport?
    @State private var logDay: LogDay?
    @Environment(\.modelContext) private var context

    struct LogDay: Identifiable { let date: Date; var id: Date { date } }

    private var todayLog: MedicationLog? {
        logs.filter { Calendar.current.isDateInToday($0.takenAt) }.max { $0.takenAt < $1.takenAt }
    }

    private func dayDate(_ back: Int) -> Date { Calendar.current.date(byAdding: .day, value: -back, to: .now)! }

    private enum Row { case lab(LabReport), dose(DoseChange)
        var date: Date { switch self { case .lab(let l): l.date; case .dose(let d): d.date } }
    }

    private var rows: [Row] {
        (reports.map(Row.lab) + doses.map(Row.dose)).sorted { $0.date > $1.date }.prefix(4).map { $0 }
    }

    private var last14: [Bool] {
        let cal = Calendar.current
        let days = Set(logs.map { cal.startOfDay(for: $0.takenAt) })
        return (0..<14).reversed().map { days.contains(cal.startOfDay(for: cal.date(byAdding: .day, value: -$0, to: .now)!)) }
    }

    private var timingText: String? {
        let recent = logs.filter { $0.takenAt > Date().addingTimeInterval(-28 * 86400) }
        guard recent.count >= 3 else { return nil }
        let cal = Calendar.current
        let mins = recent.map { Double(cal.component(.hour, from: $0.takenAt) * 60 + cal.component(.minute, from: $0.takenAt)) }.sorted()
        let median = mins[mins.count / 2]
        let spread = mins[min(mins.count - 1, mins.count * 3 / 4)] - mins[mins.count / 4]
        let time = String(format: "%02d:%02d", Int(median) / 60, Int(median) % 60)
        let gaps = last14.filter { !$0 }.count
        let gapText = gaps == 0 ? "no gaps" : gaps == 1 ? "one gap" : "\(gaps) gaps"
        return "Usual time \(time). \(spread <= 45 ? "Usually steady" : "Times vary"), \(gapText)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                if i > 0 { Divider().overlay(Palette.line) }
                Button { if case .lab(let rep) = r { editingReport = rep } } label: {
                HStack(alignment: .top, spacing: 16) {
                    Text(r.date.formatted(.dateTime.day().month(.abbreviated))).font(.footnote).foregroundStyle(Palette.muted).frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        switch r {
                        case .lab(let rep):
                            Text("Lab results").font(.headline).foregroundStyle(Palette.ink)
                            Text(LabText.line(rep)).font(.subheadline).foregroundStyle(Palette.muted).lineLimit(3)
                        case .dose(let d):
                            Text("Dose change").font(.headline).foregroundStyle(Palette.ink)
                            Text("\(d.fromText) to \(d.toText)").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    if case .lab = r {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint({ if case .lab = r { return "Edit this result" } else { return "" } }())
            }
            if !rows.isEmpty { Divider().overlay(Palette.line) }
            VStack(alignment: .leading, spacing: 10) {
                Text("Your daily dose").font(.headline).foregroundStyle(Palette.ink)
                if let t = todayLog {
                    HStack {
                        Label("Taken today at \(t.takenAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button("Undo") { context.delete(t); try? context.save() }
                            .font(.subheadline).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button {
                            context.insert(MedicationLog(takenAt: .now)); try? context.save()
                        } label: {
                            Text("I took it today").font(.headline).foregroundStyle(Palette.onAction)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Palette.action, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button("Other time") { logDay = LogDay(date: .now) }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                    }
                }
                Text("Last 14 days. Tap an empty day to log it.").font(.footnote).foregroundStyle(Palette.muted)
                HStack(spacing: 0) {
                    ForEach(Array(last14.enumerated()), id: \.offset) { i, took in
                        let back = 13 - i
                        let d = dayDate(back)
                        Button {
                            if !took { logDay = LogDay(date: d) }
                        } label: {
                            VStack(spacing: 4) {
                                Circle().fill(took ? Palette.dataMark : Color.clear)
                                    .overlay(Circle().stroke(Palette.pink, lineWidth: took ? 0 : 1.2))
                                    .frame(width: 14, height: 14)
                                Text(back == 0 ? "T" : String(d.formatted(.dateTime.weekday(.narrow))))
                                    .font(.system(size: 10, weight: back == 0 ? .bold : .regular))
                                    .foregroundStyle(back == 0 ? Palette.ink : Palette.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide).day().month())), \(took ? "taken" : "not logged")")
                    }
                }
                HStack { Text("2 weeks ago"); Spacer(); Text("Today") }.font(.caption2).foregroundStyle(Palette.muted)
                if let timingText { Text(timingText).font(.footnote).foregroundStyle(Palette.muted) }
            }
            .padding(.vertical, 12)
            Divider().overlay(Palette.line)
            HStack(spacing: 10) {
                addButton("+ Lab results") { sheet = .lab }
                addButton("+ Dose change") { sheet = .dose }
                addButton("+ Dose log") { logDay = LogDay(date: .now) }
            }
        }
        .padding(18)
        .card()
        .sheet(item: $editingReport) { AddLabView(editing: $0) }
        .sheet(item: $logDay) { d in
            LogDoseView(initial: Calendar.current.isDateInToday(d.date) ? .now : usualTime(on: d.date))
        }
    }

    /// Her usual dose time on that day, so a back-filled day needs no time fiddling.
    private func usualTime(on day: Date) -> Date {
        let cal = Calendar.current
        let mins = logs.map { cal.component(.hour, from: $0.takenAt) * 60 + cal.component(.minute, from: $0.takenAt) }.sorted()
        let m = mins.isEmpty ? 7 * 60 : mins[mins.count / 2]
        return cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) ?? day
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.onTint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
        }
    }
}

/// Weekly body check (screen 16). Tap once for some, twice for a lot, a third time to clear.
struct WeeklyCheckView: View {
    let week: AnchoredDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var checks: [BodyCheck]
    @State private var signs: [String: Int] = [:]
    @State private var took: TookAsUsual?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly body check-in").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                        Text("About a minute. Skip anything. Tap once for some, twice for a lot.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    group("Lower than usual", BodySigns.lower, $signs)
                    group("Higher than usual", BodySigns.higher, $signs)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Took it as usual this week?").font(.headline).foregroundStyle(Palette.ink)
                        Picker("Took it as usual", selection: $took) {
                            ForEach(TookAsUsual.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(18)
                    .card()
                    Button("Save", action: save).buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            if let c = checks.first(where: { $0.weekKey == week.key }) {
                signs = c.signs; took = c.tookAsUsual
            }
        }
    }

    private func group(_ title: String, _ items: [String], _ scores: Binding<[String: Int]>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            FlowLayout(spacing: 10) {
                ForEach(items, id: \.self) { item in
                    let v = scores.wrappedValue[item] ?? 0
                    Button {
                        scores.wrappedValue[item] = (v + 1) % 3
                    } label: {
                        Text(item)
                            .foregroundStyle(v == 2 ? Palette.onAction : Palette.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(v == 2 ? Palette.action : (v == 1 ? Palette.tint1 : Palette.card), in: Capsule())
                            .overlay(Capsule().stroke(v == 1 ? Palette.action : Palette.line, lineWidth: v == 1 ? 1.2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(v == 0 ? "none" : v == 1 ? "some" : "a lot")
                    .accessibilityHint("Tap to change")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func save() {
        let c = checks.first(where: { $0.weekKey == week.key }) ?? {
            let n = BodyCheck(week: week)
            context.insert(n)
            return n
        }()
        c.signs = signs.filter { $0.value > 0 }
        c.tookAsUsual = took
        c.updatedAt = .now
        try? context.save()
        dismiss()
    }
}

struct AddDoseChangeView: View {
    let last: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Section {
                    TextField("From, e.g. 75 µg", text: $from)
                    TextField("To, e.g. 88 µg", text: $to)
                } footer: {
                    Text("A record of what your doctor changed. AiHeart never suggests a dose.")
                }
            }
            .navigationTitle("Dose change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(DoseChange(date: date, from: from, to: to)); try? context.save(); dismiss()
                    }
                    .disabled(to.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { from = last }
    }
}

/// Log a dose: when, and what it was taken with.
struct LogDoseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var initial: Date = Date()
    @State private var at = Date()
    @State private var with: Set<String> = []
    static let options = ["Food", "Coffee", "Water", "Other medicine", "New brand"]

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Taken at", selection: $at)
                Section("Taken with, if any") {
                    FlowLayout(spacing: 8) {
                        ForEach(Self.options, id: \.self) { o in
                            Chip(title: o, selected: with.contains(o)) { if with.contains(o) { with.remove(o) } else { with.insert(o) } }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Log a dose")
            .onAppear { at = initial }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let l = MedicationLog(takenAt: at)
                        l.with = Array(with).sorted()
                        context.insert(l); try? context.save(); dismiss()
                    }
                }
            }
        }
    }
}

/// Small card on Insights · Today.
struct LabsCard: View {
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query private var checks: [BodyCheck]
    @Query private var doses: [DoseChange]
    @Query private var labs: [LabResult]

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        let model = BodyBalanceModel(snap: snap, checks: checks, doses: doses, labs: labs, dayStart: settingsRows.first?.dayStartHour ?? 4)
        let done = checks.contains { $0.weekKey == model.thisWeek.key }
        let latest = LabReport.group(labs).first
        NavigationLink { LabsView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "drop")
                    .foregroundStyle(Palette.onTint)
                    .frame(width: 44, height: 44)
                    .background(Palette.tint1, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Labs").font(.headline).foregroundStyle(Palette.ink)
                    Text(latest.map { "Latest results · \($0.date.formatted(.dateTime.day().month(.abbreviated).year()))" } ?? "No lab results yet")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Text("Weekly check \(done ? "done" : "not done")").font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Her latest report: every marker it had, with the lab's own range, and when her
/// next test usually falls, from her own rhythm.
struct LatestLabCard: View {
    let labs: [LabResult]
    let add: () -> Void

    var body: some View {
        let latest = LabReport.group(labs).first
        VStack(alignment: .leading, spacing: 10) {
            Text("Latest lab results").font(.headline).foregroundStyle(Palette.ink)
            if let report = latest {
                Text(report.date.formatted(date: .long, time: .omitted)).font(.subheadline).foregroundStyle(Palette.muted)
                FlowLayout(spacing: 18) {
                    ForEach(report.results, id: \.syncId) { r in
                        value(r.markerName, r.value, r.unit, r.shownRange)
                    }
                }
                let dates = Array(Set(labs.map(\.date)))
                if let next = LabCadence.nextTypical(dates), let gap = LabCadence.usualGapDays(dates) {
                    Text("Your tests usually come about every \(gap >= 60 ? "\(Int((Double(gap) / 30.4).rounded())) months" : "\(gap) days"), so the next would fall around \(next.formatted(.dateTime.month(.wide).year())).")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            } else {
                Text("Lab values come from blood or other tests. Add them by hand or from a screenshot of the report.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 20) {
                Button(action: add) {
                    Label(latest == nil ? "Add lab results" : "Add new results", systemImage: "plus")
                }
                if latest != nil {
                    NavigationLink { LabListView() } label: { Text("All results") }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.onTint)
            .frame(minHeight: 44)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func value(_ name: String, _ v: Double?, _ unit: String?, _ range: (low: Double, high: Double, fromLab: Bool)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline).foregroundStyle(Palette.muted)
            Text(v.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "–")
                .font(.title2.bold()).foregroundStyle(Palette.ink)
            if let unit { Text(unit).font(.caption).foregroundStyle(Palette.muted) }
            if let r = range {
                Text("\(r.fromLab ? "lab range" : "typical") \(r.low.formatted())–\(r.high.formatted())").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

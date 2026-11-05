import AiHeartCore
import SwiftData
import SwiftUI
import UIKit

/// Today's log on Now (owner, 2026-11-01): dose, heart rate, weight, blood
/// pressure and warning signs, in one place, all day. Each row is one tap; numbers open a
/// small sheet. Values go to today's DaySummary and Apple Health; doses to MedicationLog.
struct DailyLogCard: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \MedicationLog.takenAt, order: .reverse) private var logs: [MedicationLog]
    @State private var editing: Field?
    @State private var urgent: [UrgentSigns.Finding] = []
    @State private var showSigns = false
    @State private var showSleep = false
    @State private var confirmUndo = false
    @State private var showWeekly = false
    @Query private var checks: [BodyCheck]
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Field: String, Identifiable { case hr, weight, bp; var id: String { rawValue } }

    private var dayStart: Int { settingsRows.first?.dayStartHour ?? 4 }
    private var today: AnchoredDay { DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart) }
    private var row: DaySummary? { summaries.first { $0.dayKey == today.key && $0.deviceId != DemoData.tag } }
    private var doseToday: MedicationLog? {
        logs.first { DayAnchor.day(for: $0.takenAt, timeZone: .current, dayStartHour: dayStart) == today }
    }
    private var showsDose: Bool { settingsRows.first?.usesLabs ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today's log").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text(doneCount).font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(.bottom, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 10) {
                tile("Sleep", icon: "bed.double", value: sleepValue, done: row?.sleepMin != nil && row?.sleepSourceRaw != "inBed") {
                    if row?.sleepSourceRaw != "asleep" { showSleep = true }
                }
                if showsDose {
                    tile("Dose", icon: "pills", value: doseToday.map { $0.takenAt.formatted(date: .omitted, time: .shortened) } ?? "Took it",
                         done: doseToday != nil, primary: doseToday == nil) {
                        if doseToday != nil { confirmUndo = true } else {
                            context.insert(MedicationLog(takenAt: .now)); try? context.save()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
                tile("Heart rate", icon: "heart", value: row?.manualHR.map { "\(Int($0.rounded())) bpm" }, done: row?.manualHR != nil) { editing = .hr }
                tile("Weight", icon: "scalemass", value: row?.weightKg.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" },
                     done: row?.weightKg != nil) { editing = .weight }
                tile("Blood pressure", icon: "waveform.path.ecg",
                     value: row.flatMap { r in r.systolic.flatMap { s in r.diastolic.map { "\(Int(s))/\(Int($0))" } } },
                     done: row?.systolic != nil) { editing = .bp }
                tile("Worrying?", icon: "exclamationmark.bubble",
                     value: (row?.warningSigns ?? []).isEmpty ? nil : "\((row?.warningSigns ?? []).count) noted",
                     done: !(row?.warningSigns ?? []).isEmpty) { showSigns = true }
            }
            // The weekly body check-in, only while this week's is not done.
            if showsDose && !checks.contains(where: { $0.weekKey == BodyBalanceModel.monday(today).key }) {
                Button { showWeekly = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.clipboard").foregroundStyle(Palette.onTint)
                        Text("Weekly body check-in").foregroundStyle(Palette.ink)
                        Text("· about a minute").foregroundStyle(Palette.muted)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(item: $editing) { f in
            VitalEntrySheet(field: f, initial: initial(f)) { values in save(f, values) }
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showSleep) {
            NavigationStack {
                ScrollView { SleepCheckInCard(asSheet: true) { showSleep = false }.padding(20) }
                    .background(Palette.surface.ignoresSafeArea())
                    .navigationTitle("Last night").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showSleep = false } } }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showWeekly) { WeeklyCheckView(week: BodyBalanceModel.monday(today)) }
        .sheet(isPresented: $showSigns) {
            WarningSignsSheet(selected: Set((row?.warningSigns ?? []).compactMap(UrgentSigns.Sign.init(rawValue:)))) { signs in
                let s = todayRow()
                s.warningSigns = signs.map(\.rawValue).sorted()
                s.updatedAt = .now
                try? context.save()
                check()
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: Binding(get: { !urgent.isEmpty }, set: { if !$0 { urgent = [] } })) { UrgentSheet(findings: urgent) }
        .alert("Undo today's dose?", isPresented: $confirmUndo) {
            Button("Undo", role: .destructive) { if let d = doseToday { context.delete(d); try? context.save() } }
            Button("Keep", role: .cancel) {}
        }
    }

    private var sleepValue: String? {
        guard let m = row?.sleepMin else { return nil }
        return BodyFormat.duration(m) + (row?.rested.map { " · \($0)/5" } ?? "")
    }

    /// One square-ish tile: icon, name, today's value or "Add". Filled when done.
    private func tile(_ title: String, icon name: String, value: String?, done: Bool, primary: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : name)
                    .font(.title3)
                    .foregroundStyle(done ? Palette.onAction : Palette.onTint)
                Spacer(minLength: 0)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(done ? Palette.onAction.opacity(0.85) : Palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(value ?? "Add").font(.subheadline.weight(.semibold))
                    .foregroundStyle(done ? Palette.onAction : (value == nil || primary ? Palette.onTint : Palette.ink))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(done ? Palette.action : Palette.tint1.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(done ? (value ?? "done") : "not logged")")
        .accessibilityHint(done ? "Change it" : "Log it")
    }

    private var doneCount: String {
        var n = 0, total = 5
        if row?.sleepMin != nil { n += 1 }
        if showsDose { total += 1; if doseToday != nil { n += 1 } }
        if row?.manualHR != nil { n += 1 }
        if row?.weightKg != nil { n += 1 }
        if row?.systolic != nil { n += 1 }
        if !(row?.warningSigns ?? []).isEmpty { n += 1 }
        return n == 0 ? "All optional" : "\(n) of \(total)"
    }

    // MARK: Rows

    /// Sleep: from the watch when there is one, else her morning answer. Tap to add or fix.
    private var sleepRow: some View {
        let r = row
        let value: String? = r?.sleepMin.map { m in
            var s = BodyFormat.duration(m)
            if let x = r?.rested { s += " · rested \(x)/5" }
            return s
        }
        let fromWatch = r?.sleepSourceRaw == "asleep"
        return Button { if !fromWatch { showSleep = true } } label: {
            HStack(spacing: 12) {
                icon("bed.double", done: value != nil && r?.sleepSourceRaw != "inBed")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep").foregroundStyle(Palette.ink)
                    if r?.sleepSourceRaw == "inBed" {
                        Text("From your sleep schedule. Tap to check it.").font(.footnote).foregroundStyle(Palette.muted)
                    } else if fromWatch {
                        Text("From your watch").font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                Text(value ?? "Add").foregroundStyle(value == nil ? Palette.onTint : Palette.ink)
                    .font(value == nil ? .subheadline.weight(.semibold) : .body.monospacedDigit())
                if !fromWatch { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted) }
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sleep, \(value ?? "not logged")")
    }

    private var doseRow: some View {
        HStack(spacing: 12) {
            icon("pills", done: doseToday != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's dose").foregroundStyle(Palette.ink)
                if let d = doseToday {
                    Text("Taken at \(d.takenAt.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            if let d = doseToday {
                Button("Undo") { context.delete(d); try? context.save() }
                    .font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44)
            } else {
                Button {
                    context.insert(MedicationLog(takenAt: .now)); try? context.save()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("Took it").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onAction)
                        .padding(.horizontal, 16).frame(minHeight: 36)
                        .background(Palette.action, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 6)
    }

    private func valueRow(_ title: String, icon name: String, value: String?, field: Field) -> some View {
        Button { editing = field } label: {
            HStack(spacing: 12) {
                icon(name, done: value != nil)
                Text(title).foregroundStyle(Palette.ink)
                Spacer()
                Text(value ?? "Add").foregroundStyle(value == nil ? Palette.onTint : Palette.ink)
                    .font(value == nil ? .subheadline.weight(.semibold) : .body.monospacedDigit())
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value ?? "not logged")")
        .accessibilityHint(value == nil ? "Add today's value" : "Change today's value")
    }

    private var signsRow: some View {
        let signs = (row?.warningSigns ?? []).compactMap(UrgentSigns.Sign.init(rawValue:))
        return Button { showSigns = true } label: {
            HStack(spacing: 12) {
                icon("exclamationmark.bubble", done: !signs.isEmpty)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anything worrying?").foregroundStyle(Palette.ink)
                    if !signs.isEmpty {
                        Text(signs.map(\.label).joined(separator: ", ")).font(.footnote).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ name: String, done: Bool) -> some View {
        Image(systemName: done ? "checkmark" : name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done ? Palette.onAction : Palette.onTint)
            .frame(width: 34, height: 34)
            .background(done ? Palette.action : Palette.tint1, in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: Saving

    private func initial(_ f: Field) -> [Double?] {
        switch f {
        case .hr: [row?.manualHR]
        case .weight: [row?.weightKg ?? summaries.filter { $0.weightKg != nil }.max { $0.dayKey < $1.dayKey }?.weightKg]
        case .bp: [row?.systolic, row?.diastolic]
        }
    }

    private func todayRow() -> DaySummary {
        if let row { return row }
        let n = DaySummary(day: today, timeZone: .current)
        n.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        context.insert(n)
        return n
    }

    private func save(_ f: Field, _ v: [Double?]) {
        let s = todayRow()
        switch f {
        case .hr:
            s.manualHR = UrgentSigns.plausible(hr: v.first ?? nil)
            if s.manualHR != nil, s.restingHR == nil { s.restingHR = s.manualHR }
            Task { await HealthService.shared.saveVitals(heartRate: s.manualHR, weightKg: nil, bp: nil) }
        case .weight:
            s.weightKg = (v.first ?? nil).flatMap { (20...300).contains($0) ? $0 : nil }
            Task { await HealthService.shared.saveVitals(heartRate: nil, weightKg: s.weightKg, bp: nil) }
        case .bp:
            let bp = UrgentSigns.plausible(systolic: v.first ?? nil, diastolic: v.count > 1 ? v[1] : nil)
            s.systolic = bp?.0; s.diastolic = bp?.1
            Task { await HealthService.shared.saveVitals(heartRate: nil, weightKg: nil, bp: bp) }
        }
        s.updatedAt = .now
        try? context.save()
        check()
    }

    private func check() {
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let found = UrgentWatch.pending(entries: entries.filter { $0.deviceId != DemoData.tag }, summary: row, today: today, dayStart: dayStart)
        if !found.isEmpty { NSLog("AiHeartUI urgent signs shown: %d", found.count); urgent = found }
    }
}

/// One number (or two for blood pressure), big and easy to type.
struct VitalEntrySheet: View {
    let field: DailyLogCard.Field
    let initial: [Double?]
    let onSave: ([Double?]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var a = ""
    @State private var b = ""
    @FocusState private var focus: Int?

    private var title: String {
        switch field { case .hr: "Heart rate"; case .weight: "Weight"; case .bp: "Blood pressure" }
    }
    private var unit: String {
        switch field { case .hr: "bpm, sitting still"; case .weight: "kg"; case .bp: "mmHg" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(field == .bp ? "120" : field == .hr ? "70" : "55", text: $a)
                        .keyboardType(field == .weight ? .decimalPad : .numberPad)
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: field == .bp ? 110 : 160)
                        .focused($focus, equals: 0)
                    if field == .bp {
                        Text("/").font(.system(size: 36)).foregroundStyle(Palette.muted)
                        TextField("80", text: $b)
                            .keyboardType(.numberPad)
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .frame(width: 90)
                            .focused($focus, equals: 1)
                    }
                }
                Text(unit).font(.subheadline).foregroundStyle(Palette.muted)
                Text("Saved here and to Apple Health.").font(.caption).foregroundStyle(Palette.muted)
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave([num(a), num(b)]); dismiss() }.disabled(num(a) == nil || (field == .bp && num(b) == nil))
                }
            }
            .onAppear {
                func f(_ v: Double?) -> String { v.map { $0.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)) } ?? "" }
                a = f(initial.first ?? nil); b = initial.count > 1 ? f(initial[1]) : ""
                focus = 0
            }
            .onChange(of: a) { _, v in if field == .bp, v.count >= 3 { focus = 1 } }
        }
    }

    private func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
}

/// Warning signs, as chips. Saving runs the urgent-sign check.
struct WarningSignsSheet: View {
    @State var selected: Set<UrgentSigns.Sign>
    let onSave: (Set<UrgentSigns.Sign>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tick anything happening now.").font(.subheadline).foregroundStyle(Palette.muted)
                FlowChips(items: UrgentSigns.Sign.allCases.map { ($0.rawValue, $0.label) }, selected: Set(selected.map(\.rawValue))) { raw in
                    guard let s = UrgentSigns.Sign(rawValue: raw) else { return }
                    if selected.contains(s) { selected.remove(s) } else { selected.insert(s) }
                }
                Spacer()
            }
            .padding(20)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Anything worrying?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(selected); dismiss() } }
            }
        }
    }
}

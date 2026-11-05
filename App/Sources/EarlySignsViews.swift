import AiHeartCore
import SwiftData
import SwiftUI

// Her own early signs (docs/18). She writes the list with her clinician. The app watches only for
// the two things it can see, her sleep and her energy taps, each against her own usual, and says
// what it saw in plain words. It never names a state and never advises.

/// The editor for her signs list, in My rules.
struct EarlySignsEditorView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @State private var draft = ""
    @FocusState private var adding: Bool

    var body: some View {
        Group {
            if let s = settingsRows.first {
                content(s)
            } else {
                Text("Nothing here yet.").foregroundStyle(Palette.muted)
            }
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("My signs").navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ s: AppSettings) {
        s.updatedAt = .now
        try? context.save()
    }

    private func content(_ s: AppSettings) -> some View {
        List {
            Section {
                Text("Write the signs you and your therapist know, in your words. AiHeart watches only for sleep and your energy taps; the rest is for you to check.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .listRowBackground(Color.clear)
            }
            Section {
                RuleToggle(title: "Watch my sleep and energy",
                           subtitle: "If your sleep or energy taps drift from your own usual, one quiet card on Now, at most once a week.",
                           isOn: Binding(get: { s.watchSigns }, set: { s.watchSigns = $0; save(s) }))
            }
            .listRowBackground(Palette.card)

            Section("Your signs") {
                if s.warningSigns.isEmpty, !s.steadySigns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Split my older notes into a list") {
                        s.warningSigns = EarlyWarning.splitOlderNotes(s.steadySigns)
                        save(s)
                    }
                    .foregroundStyle(Palette.onTint)
                    .accessibilityHint("Turns what you wrote in Notes from a steady day into one sign per line. The notes stay as they are.")
                }
                ForEach(Array(s.warningSigns.enumerated()), id: \.offset) { i, _ in
                    TextField("A sign", text: Binding(
                        get: { i < s.warningSigns.count ? s.warningSigns[i] : "" },
                        set: { if i < s.warningSigns.count { s.warningSigns[i] = $0 } }), axis: .vertical)
                        .font(.journal(.body)).foregroundStyle(Palette.ink)
                        .onSubmit { tidy(s) }
                        .accessibilityLabel("Sign \(i + 1)")
                }
                .onDelete { offsets in
                    s.warningSigns.remove(atOffsets: offsets)
                    save(s)
                }
                .onMove { from, to in
                    s.warningSigns.move(fromOffsets: from, toOffset: to)
                    save(s)
                }
                HStack {
                    TextField("Add a sign", text: $draft, axis: .vertical)
                        .font(.journal(.body)).foregroundStyle(Palette.ink)
                        .focused($adding)
                        .submitLabel(.done)
                        .onSubmit { add(s) }
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Add") { add(s) }.foregroundStyle(Palette.onTint)
                    }
                }
            }
            .listRowBackground(Palette.card)
        }
        .scrollContentBackground(.hidden)
        .toolbar { if !s.warningSigns.isEmpty { EditButton() } }
        .onDisappear { tidy(s) }
    }

    private func add(_ s: AppSettings) {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        s.warningSigns.append(t)
        draft = ""
        save(s)
    }

    /// Trims and drops empty lines, then saves.
    private func tidy(_ s: AppSettings) {
        let cleaned = s.warningSigns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if cleaned != s.warningSigns { s.warningSigns = cleaned }
        save(s)
    }
}

/// A calm card on Now when sleep or energy has moved from her own usual. At most once per stretch.
struct EarlySignsCard: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query private var summaries: [DaySummary]
    @Query private var entries: [Entry]
    @State private var notices: [EarlyWarning.Notice] = []
    @State private var ticked = Set<Int>()   // for herself only, never stored
    @State private var showSafety = false
    @State private var showTry = false

    private var settings: AppSettings? { settingsRows.first }
    private var dayStart: Int { settings?.dayStartHour ?? 4 }
    private var today: AnchoredDay { DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart) }

    var body: some View {
        Group {
            if !notices.isEmpty, let s = settings, s.watchSigns, !s.pauseEverything {
                card(s)
            }
        }
        .task(id: summaries.count + entries.count) { refresh() }
        .sheet(isPresented: $showSafety) { SafetyPageView(readOnly: true, keptNote: false) }
        .sheet(isPresented: $showTry) { HardMomentsView() }
    }

    private func card(_ s: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some of your signs").font(.headline).foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notices, id: \.kind) { n in
                    Text(n.text).font(.subheadline).foregroundStyle(Palette.ink)
                }
            }
            if !s.warningSigns.isEmpty {
                Divider().overlay(Palette.line)
                Text("Your own list, to check for yourself").font(.footnote).foregroundStyle(Palette.muted)
                ForEach(Array(s.warningSigns.enumerated()), id: \.offset) { i, sign in
                    Button {
                        if ticked.contains(i) { ticked.remove(i) } else { ticked.insert(i) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: ticked.contains(i) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(ticked.contains(i) ? Palette.onTint : Palette.muted)
                            Text(sign).font(.journal(.subheadline)).foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(ticked.contains(i) ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                Button("My safety plan") { showSafety = true }
                    .buttonStyle(.bordered).tint(Palette.action)
                Button("Something to try") { showTry = true }
                    .buttonStyle(.bordered).tint(Palette.action)
                Spacer(minLength: 0)
            }
            .controlSize(.large)
            Button("Not now") { dismiss(s) }
                .font(.footnote).foregroundStyle(Palette.muted)
                .frame(minHeight: 44)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .contain)
    }

    private func dismiss(_ s: AppSettings) {
        s.signsNoticedDay = today.ordinal
        s.updatedAt = .now
        try? context.save()
        notices = []
    }

    /// Looks once per change in the data. A card already showing stays until she closes it; a new one
    /// is allowed only when the quiet stretch has passed, and counts from the day it first shows.
    private func refresh() {
        guard let s = settings, s.watchSigns, !s.pauseEverything else { notices = []; return }
        guard notices.isEmpty else { return }
        let t = today
        guard EarlyWarning.isDue(watch: s.watchSigns, paused: s.pauseEverything, lastNoticedDay: s.signsNoticedDay, today: t) else { return }
        // Only the last ~6 weeks matter, so years of history stay quick.
        let from = t.ordinal - (EarlyWarning.baselineDays + EarlyWarning.recentDays + 2)
        let recentRows = summaries.filter { r in
            r.deviceId != DemoData.tag && (r.day.map { $0.ordinal >= from } ?? false)
        }
        let since = Date(timeIntervalSinceNow: -Double(EarlyWarning.baselineDays + EarlyWarning.recentDays + 4) * 86_400)
        let recentEntries = entries.filter { $0.deviceId != DemoData.tag && $0.createdAt >= since }
        let found = EarlyWarning.notices(nights: NightSample.from(recentRows),
                                         energy: EarlyWarning.energyPoints(recentEntries, dayStart: dayStart), today: t)
        guard !found.isEmpty else { return }
        notices = found
        s.signsNoticedDay = t.ordinal
        s.updatedAt = .now
        try? context.save()
    }
}

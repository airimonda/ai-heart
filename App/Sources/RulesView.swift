import AiHeartCore
import SwiftData
import SwiftUI

/// My rules (screen 06). Rows for later milestones (How it decides, Mood outlook,
/// Connections, Export, Sync, Listen) are added when those features exist.
struct RulesView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query private var quiet: [QuietTopic]

    var body: some View {
        if let s = settingsRows.first {
            content(s)
        } else {
            Color.clear.onAppear { _ = AiHeartStore.settings(in: context) }
        }
    }

    private func content(_ s: AppSettings) -> some View {
        @Bindable var s = s
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My rules")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                    Text("The app follows these. Change them any time.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                NavigationLink { AboutMeView() } label: {
                    RuleRow(title: "About me", subtitle: "What you want AiHeart to know, in your words.", chevron: true)
                }
                .buttonStyle(.plain)
                .card()

                NavigationLink { DecidesView(s: s) } label: {
                    RuleRow(title: "How it decides", subtitle: "Keep good entries. For hard ones, keep only what helped.",
                            trailing: s.decideAuto ? "On" : "Off", chevron: true)
                }
                .buttonStyle(.plain)
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Look-backs").font(.headline).foregroundStyle(Palette.ink)
                    Picker("Look-backs", selection: $s.paceRaw) {
                        Text("Weekly").tag(LookBackPace.weekly.rawValue)
                        Text("Monthly").tag(LookBackPace.monthly.rawValue)
                        Text("On request").tag(LookBackPace.onRequest.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(18)
                .card()

                ReminderCard(s: s)

                VStack(spacing: 0) {
                    RuleToggle(title: "Ask how the app is working", subtitle: "A small card on Sundays. No notification.", isOn: $s.askForAppFeedback)
                }
                .card()

                VStack(spacing: 0) {
                    // Nothing resurfaces by itself (CLAUDE.md #5). Shown so she can see the rule.
                    RuleRow(title: "Resurface old entries", subtitle: "Off: it never brings up the past.", trailing: "Off")
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Mood lean on Now", subtitle: "From your own body and entries. A lean, not a rule.", isOn: $s.outlookOn)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Pause everything", subtitle: "No analysis or prompts. Capture still works.", isOn: $s.pauseEverything)
                }
                .card()

                VStack(spacing: 0) {
                    LanguageModelRow()
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { ListenSettingsView() } label: {
                        RuleRow(title: "Listen", subtitle: "Talk or type when words won't come. It mostly listens.", trailing: nil, chevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { QuietTopicsView() } label: {
                        RuleRow(title: "Quiet topics", subtitle: "The model will not raise these.", trailing: "\(quiet.count)", chevron: true)
                    }
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { SafetyPageView(readOnly: false) } label: {
                        RuleRow(title: "My safety plan", subtitle: "Six short steps, written by you.", trailing: "Open", chevron: true)
                    }
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    QuietCheckRow(s: s)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { SteadyNotesView() } label: {
                        RuleRow(title: "Notes from a steady day", subtitle: "What you want to hear when it is hard. Shown first.", trailing: nil, chevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { EarlySignsEditorView() } label: { RuleRow(title: "My signs", subtitle: "Your own early signs, and a quiet check on sleep and energy.", trailing: nil, chevron: true) }
                }
                .buttonStyle(.plain)
                .card()

                VStack(spacing: 0) {
                    HealthRow()
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Track my cycle", subtitle: "Phase, cycle day and cycle-aware usual ranges, from Apple Health.", isOn: $s.usesCycle)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Labs", subtitle: "Weekly body check, labs, dose changes and a summary for your doctor.", isOn: $s.usesLabs)
                }
                .card()

                VStack(spacing: 0) {
                    NavigationLink { SourcesView() } label: {
                        RuleRow(title: "Sources", subtitle: "Spotify, Netflix, YouTube. Weekly totals, display only.", trailing: nil, chevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    HevyRow()
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    NavigationLink { WorkoutRatingSettingsView(s: s) } label: {
                        RuleRow(title: "Workout rating", subtitle: "One quiet nudge after a workout, if you want it.",
                                trailing: s.askToRateWorkouts ? "On" : "Off", chevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .card()

                VStack(spacing: 0) {
                    RuleToggle(title: "Lock with Face ID", subtitle: "Asks each time you come back to the app.", isOn: $s.faceIDLock)
                }
                .card()

                NavigationLink { ExportView() } label: {
                    RuleRow(title: "Export my data", subtitle: "A report for a therapist or a page for my doctor", chevron: true)
                }
                .buttonStyle(.plain)
                .card()

                SampleDataCard()

                Text("Your journal stays on this device. Sync between your own devices comes later.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: s.faceIDLock) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.pauseEverything) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.decideAuto) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.paceRaw) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.usesCycle) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.usesLabs) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.outlookOn) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.askForAppFeedback) { s.updatedAt = .now; try? context.save() }
        .onChange(of: s.askToRateWorkouts) { _, on in
            s.updatedAt = .now
            try? context.save()
            if on { Task { await WorkoutService.shared.requestNotificationPermission() } }
        }
    }
}

struct RuleToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .tint(Palette.action)
        .padding(18)
    }
}

struct RuleRow: View {
    let title: String
    let subtitle: String
    var trailing: String?
    var chevron = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(Palette.muted) }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
            }
        }
        .padding(18)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Quiet topics. Not designed yet (README): a plain list until the owner decides.
struct QuietTopicsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \QuietTopic.term) private var topics: [QuietTopic]
    @State private var newTerm = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Add a topic", text: $newTerm)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Journal search skips these. The language model, when it arrives, will never raise or search them.")
            }
            Section {
                ForEach(topics) { Text($0.term) }
                    .onDelete { idx in
                        idx.map { topics[$0] }.forEach(context.delete)
                        try? context.save()
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Quiet topics")
    }

    private func add() {
        let t = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !topics.contains(where: { $0.term.caseInsensitiveCompare(t) == .orderedSame }) else { return }
        context.insert(QuietTopic(term: t))
        try? context.save()
        newTerm = ""
    }
}

/// Crisis lines for Japan and the Philippines (owner, 2026-11-01). Tap to call. Shown on
/// the safety page; no advice, just numbers.
struct CrisisLines: View {
    @Environment(\.openURL) private var openURL
    static let lines: [(country: String, name: String, number: String, note: String)] = [
        ("Japan", "Emergency", "119", "Ambulance"),
        ("Japan", "TELL Lifeline", "03-5774-0992", "In English"),
        ("Japan", "Yorisoi Hotline", "0120-279-338", "Free, 24 hours"),
        ("Philippines", "Emergency", "911", ""),
        ("Philippines", "NCMH Crisis Hotline", "1553", "24 hours"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("If you want to talk to someone now").font(.headline).foregroundStyle(Palette.ink).padding(.bottom, 6)
            ForEach(Array(Self.lines.enumerated()), id: \.offset) { i, l in
                if i > 0 { Divider().overlay(Palette.line) }
                Button {
                    let digits = l.number.filter(\.isNumber)
                    if let url = URL(string: "tel://\(digits)") { openURL(url) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).foregroundStyle(Palette.ink)
                            Text([l.country, l.note].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(l.number).font(.body.monospacedDigit()).foregroundStyle(Palette.onTint)
                        Image(systemName: "phone.fill").foregroundStyle(Palette.onTint)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(l.name), \(l.country), \(l.number)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct HealthRow: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @State private var showing = false
    private var health = HealthService.shared

    var body: some View {
        Button { showing = true } label: {
            RuleRow(title: "Apple Health",
                    subtitle: health.asked ? "Reads sleep, heart, breathing, temperature, activity, workouts and period days. Read only." : "Not connected. Reads only; nothing leaves your phone.",
                    trailing: health.syncing ? "Reading" : (health.asked ? "On" : "Connect"),
                    chevron: true)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            NavigationStack {
                List {
                    Section {
                        if !health.asked {
                            Button("Connect Apple Health") { Task { await health.requestAccess(); await health.sync(context: context) } }
                        }
                        LabeledContent("Days read", value: "\(summaries.count)")
                        if let first = summaries.compactMap(\.day).min() {
                            LabeledContent("Back to", value: first.date(in: .current).formatted(date: .abbreviated, time: .omitted))
                        }
                        if let last = health.lastSync {
                            LabeledContent("Last read", value: last.formatted(date: .omitted, time: .shortened))
                        }
                        if health.syncing { HStack { ProgressView(); Text("Reading your history…") } }
                        if let e = health.lastError { Text(e).foregroundStyle(Palette.muted) }
                    } footer: {
                        Text("The first read goes back as far as Health allows. After that AiHeart reads the last two weeks each time it opens. To let it read everything, choose Turn On All when asked, or in Settings, Health, Data Access & Devices, AiHeart.")
                    }
                    Section {
                        Button("Read all history again") { Task { await health.rereadAll(context: context) } }
                            .disabled(health.syncing || !health.asked)
                    }
                }
                .navigationTitle("Apple Health")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
            }
        }
    }
}

/// Synthetic sample data for demos. Removable in one tap.
struct SampleDataCard: View {
    @Environment(\.modelContext) private var context
    @State private var on = false
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sample data").font(.headline).foregroundStyle(Palette.ink)
            Text(on ? "Sample entries and body readings are showing. Apple Health reading is paused until you remove them."
                    : "Fill the app with made-up entries and 60 days of body readings, to try it out. Your own entries are not touched.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            if on {
                Button("Remove sample data") { confirmRemove = true }
                    .font(.headline)
                    .foregroundStyle(Palette.onTint)
                    .frame(minHeight: 44)
            } else {
                Button("Fill with sample data") {
                    DemoData.fill(context)
                    on = true
                }
                .font(.headline)
                .foregroundStyle(Palette.onTint)
                .frame(minHeight: 44)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear { on = DemoData.isOn(context) }
        .confirmationDialog("Remove sample data?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                DemoData.remove(context)
                on = false
                Task { await HealthService.shared.sync(context: context) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only the sample entries and readings are removed.")
        }
    }
}

struct HevyRow: View {
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var key = ""
    private var service = WorkoutService.shared

    var body: some View {
        Button { editing = true } label: {
            RuleRow(title: "Hevy",
                    subtitle: service.hevyError ?? (service.hevyConnected ? "Sets, reps and weights for your lifts. Read only." : "Add your Hevy API key for sets and weights."),
                    trailing: service.hevyConnected ? "On" : "Add", chevron: true)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("API key", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Needs Hevy Pro. Create a key at hevy.com/settings?developer. It is kept in this device's Keychain and only sent to Hevy, to read your workouts.")
                    }
                    if service.hevyConnected {
                        Section {
                            Button("Disconnect Hevy", role: .destructive) {
                                service.setHevyKey(nil)
                                editing = false
                            }
                        }
                    }
                }
                .navigationTitle("Hevy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            service.setHevyKey(key)
                            key = ""
                            editing = false
                            Task { await service.sync(context: context) }
                        }
                        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

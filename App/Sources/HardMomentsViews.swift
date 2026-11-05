import SwiftUI
import SwiftData
import AiHeartCore

// Hard moments (docs/15). Fixed, evidence-labeled things to try. The model plays no part here.
// She chooses every step, can stop at any point, and is never asked for details.
// Four plain choices, at most three offers, one literal step per screen.

/// Entry: "What is it like right now?" Four plain choices; the app never guesses.
struct HardMomentsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reaching = false

    var body: some View { bodyContent.keyboardHideButton() }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What is it like right now?").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("Pick the closest. You can change it.").font(.subheadline).foregroundStyle(Palette.muted)
                    ForEach(HardState.allCases) { s in
                        NavigationLink { HardStateView(state: s) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: s.icon).foregroundStyle(Palette.onTint)
                                    .frame(width: 44, height: 44).background(Palette.tint1, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.headline).foregroundStyle(Palette.ink)
                                    Text(s.detail).font(.subheadline).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                            }
                            .padding(16).frame(minHeight: 72).contentShape(Rectangle()).card()
                        }
                        .buttonStyle(.plain)
                    }
                    Text("These are fixed exercises from research, not the AI. Each one says how strong the evidence is.")
                        .font(.caption).foregroundStyle(Palette.muted).padding(.top, 4)
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Something to try").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { reaching = true } label: { Image(systemName: "phone") }.accessibilityLabel("Who I can reach")
                }
            }
            .sheet(isPresented: $reaching) { ListenReachSheet() }
        }
    }
}

/// Her own note first, then at most three offers. Nothing is hidden: "More" shows the rest.
struct HardStateView: View {
    let state: HardState
    @Query private var settingsRows: [AppSettings]
    @Query private var tries: [TechniqueTry]
    @State private var before: Double = 5
    @State private var rated = false
    @State private var showMore = false

    var body: some View {
        let offers = HardMoments.offers(for: state, tries: tries)
        let mine = HardMoments.results(tries, state: state)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = settingsRows.first {
                    let note = s.steadyNote(for: state).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From you, on a steady day").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                            Text(note).font(.journal(.body)).foregroundStyle(Palette.ink)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    let signs = s.steadySigns.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !signs.isEmpty, state == .fast || state == .heavy {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Early signs you wrote down").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                            Text(signs).font(.journal(.body)).foregroundStyle(Palette.ink)
                            Text("If several fit, your safety page says who to tell.").font(.footnote).foregroundStyle(Palette.muted)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("How strong is it?").font(.headline).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(rated ? "\(Int(before)) of 10" : "Optional").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Slider(value: $before, in: 0...10, step: 1, onEditingChanged: { _ in rated = true }).opacity(rated ? 1 : 0.45)
                        .tint(Palette.action)
                        .accessibilityLabel("How strong, 0 to 10")
                    Text("0 is not at all, 10 is the most. Only for you, to see what helps.").font(.caption).foregroundStyle(Palette.muted)
                }
                .padding(16).card()

                ForEach(offers.shown) { t in card(t, mine[t.id]) }
                Button(showMore ? "Fewer" : "More") { showMore.toggle() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                if showMore { ForEach(offers.more) { t in card(t, mine[t.id]) } }
            }
            .padding(24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle(state.title).navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ t: Technique, _ r: HardMoments.Result?) -> some View {
        NavigationLink { TechniqueRunView(technique: t, state: state, before: rated ? Int(before) : nil) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.title).font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(t.minutes) min").font(.footnote).foregroundStyle(Palette.muted)
                }
                Text(t.summary).font(.subheadline).foregroundStyle(Palette.muted)
                HStack(spacing: 8) {
                    Text(t.strength.label).font(.caption.weight(.semibold)).foregroundStyle(Palette.onTint)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Palette.tint1, in: Capsule())
                    if let r {
                        Text(r.meanDrop >= 0.5 ? "Eased it by \(String(format: "%.1f", r.meanDrop)) for you, \(r.tries) tries"
                                               : "Did not ease it much for you, \(r.tries) tries")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).card()
        }
        .buttonStyle(.plain)
    }
}

/// One step per screen. Stop is always there. Writing stays on the screen unless she keeps it.
struct TechniqueRunView: View {
    let technique: Technique
    let state: HardState
    let before: Int?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var answers: [String] = []
    @State private var finished = false
    @State private var after: Double = 5
    @State private var afterRated = false
    @State private var showWhy = false
    @State private var remaining: Int?
    @State private var kept = false
    private let demoAnswer: String

    init(technique: Technique, state: HardState, before: Int?, startStep: Int = 0, startFinished: Bool = false, demoAnswer: String = "") {
        self.technique = technique
        self.state = state
        self.before = before
        self.demoAnswer = demoAnswer
        _step = State(initialValue: min(startStep, technique.steps.count - 1))
        _finished = State(initialValue: startFinished)
    }

    private var last: Bool { step == technique.steps.count - 1 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if finished { endView } else { stepView }
            }
            .padding(24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle(technique.title).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if answers.isEmpty {
                answers = Array(repeating: "", count: technique.steps.count)
                if !demoAnswer.isEmpty, answers.indices.contains(step) { answers[step] = demoAnswer }
            }
        }
        .task(id: "\(step)-\(finished)") {
            // Timed step (breathing): a quiet countdown on the last step. No sound, no vibration.
            guard !finished, last, let total = technique.stepSeconds else { remaining = nil; return }
            remaining = total
            while let r = remaining, r > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining = r - 1
            }
        }
    }

    @ViewBuilder private var stepView: some View {
        Text("Step \(step + 1) of \(technique.steps.count)").font(.footnote).foregroundStyle(Palette.muted)
        Text(technique.steps[step]).font(.title3).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        if technique.writes, answers.indices.contains(step) {
            TextEditor(text: $answers[step])
                .font(.journal(.body)).frame(minHeight: 120).padding(8).scrollContentBackground(.hidden).card()
                .accessibilityLabel("Your answer")
        }
        if let r = remaining {
            Text(r > 0 ? String(format: "%d:%02d", r / 60, r % 60) : "Time is up. Stop when you are ready.")
                .font(.title.monospacedDigit()).foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
                .accessibilityLabel(r > 0 ? "\(r / 60) minutes \(r % 60) seconds left" : "Time is up")
        }
        HStack(spacing: 12) {
            if step > 0 { Button("Back") { step -= 1 }.buttonStyle(SecondaryCapsule()) }
            Button(last ? "Done" : "Next") { if last { finished = true } else { step += 1 } }.buttonStyle(SecondaryCapsule())
        }
        Button("Stop here") { finished = true }
            .font(.subheadline).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, minHeight: 44)
        DisclosureGroup("Why this is here", isExpanded: $showWhy) {
            VStack(alignment: .leading, spacing: 6) {
                Text(technique.strength.label).font(.caption.weight(.semibold)).foregroundStyle(Palette.onTint)
                Text(technique.evidence).font(.footnote).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
        .font(.subheadline).tint(Palette.muted).padding(16).card()
    }

    @ViewBuilder private var endView: some View {
        Text("That is done.").font(.title2.bold()).foregroundStyle(Palette.ink)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("How strong is it now?").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text(afterRated ? "\(Int(after)) of 10" : "Optional").font(.subheadline).foregroundStyle(Palette.muted)
            }
            Slider(value: $after, in: 0...10, step: 1, onEditingChanged: { _ in afterRated = true }).opacity(afterRated ? 1 : 0.45)
                .tint(Palette.action).accessibilityLabel("How strong now, 0 to 10")
            if before == nil {
                Text("You skipped the first rating, so this one is only for you to see.").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(16).card()
        let written = answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if technique.writes, !written.isEmpty, !kept {
            Button("Keep what I wrote as an entry") {
                let d = CaptureDraft(); d.text = written.joined(separator: "\n\n"); _ = d.save(in: context)
                kept = true
            }
            .buttonStyle(SecondaryCapsule())
            Text("If you do not keep it, it is gone when you close this.").font(.caption).foregroundStyle(Palette.muted)
        }
        Button("Close") { save(); dismiss() }.buttonStyle(SecondaryCapsule())
    }

    private func save() {
        context.insert(TechniqueTry(techniqueId: technique.id, state: state, before: before, after: afterRated ? Int(after) : nil))
        try? context.save()
    }
}

/// My rules > Notes from a steady day. Written by her when she is well, read when she is not.
struct SteadyNotesView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Write these on a steady day. They show first when you open Something to try. Nothing here is ever written by the AI.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if let s = settingsRows.first {
                    ForEach(HardState.allCases) { st in
                        field("When it is \(st.title.lowercased())", st.detail + " What do you want to hear, or do?",
                              Binding(get: { s.steadyNote(for: st) }, set: { s.setSteadyNote($0, for: st); try? context.save() }))
                    }
                    field("Early signs I know in myself", "Sleep, spending, talking, pulling away, anything you have noticed before.",
                          Binding(get: { s.steadySigns }, set: { s.steadySigns = $0; s.updatedAt = .now; try? context.save() }))
                }
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Notes from a steady day").navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ hint: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(hint).font(.footnote).foregroundStyle(Palette.muted)
            TextEditor(text: text).font(.journal(.body)).frame(minHeight: 90).scrollContentBackground(.hidden)
                .padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
        }
        .padding(16).card()
    }
}

#if DEBUG
/// Simulator screenshots only: `-hardDemo pick|fast|loop|run|write|end|notes`. Synthetic text.
struct HardMomentsDemo: View {
    static var requested: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-hardDemo"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    let screen: String
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @State private var ready = false

    var body: some View {
        Group {
            if !ready { Color.clear }
            else {
                switch screen {
                case "pick": HardMomentsView()
                case "fast": NavigationStack { HardStateView(state: .fast) }
                case "loop": NavigationStack { HardStateView(state: .loop) }
                case "run": NavigationStack { TechniqueRunView(technique: HardMoments.technique("sigh")!, state: .fast, before: 7, startStep: 4) }
                case "write": NavigationStack { TechniqueRunView(technique: HardMoments.technique("reframe")!, state: .heavy, before: 6, startStep: 1,
                                                                 demoAnswer: "[sample] I sent the report late once this month.") }
                case "end": NavigationStack { TechniqueRunView(technique: HardMoments.technique("sigh")!, state: .fast, before: 7, startFinished: true) }
                default: NavigationStack { SteadyNotesView() }
                }
            }
        }
        .tint(Palette.action)
        .task {
            let s = settingsRows.first ?? { let n = AppSettings(); context.insert(n); return n }()
            if s.steadyFast.isEmpty {
                s.steadyFast = "[sample] Slow down. Sleep first. Text someone on my page if this lasts."
                s.steadyHeavy = "[sample] This has passed before. Shower, eat something, step outside."
                s.steadyLoop = "[sample] It is a thought, not a fact. Do not google it."
                s.steadyFlooded = "[sample] I am here, in my room, today. Feet on the floor."
                s.steadySigns = "[sample] Short sleep, skipping meals, pulling away."
            }
            let old = (try? context.fetch(FetchDescriptor<TechniqueTry>())) ?? []
            if !old.contains(where: { $0.deviceId == BackupArchive.demoDeviceId }) {
                for (b, a) in [(8, 4), (7, 4), (7, 5)] {
                    context.insert(TechniqueTry(techniqueId: "tense", state: .fast, before: b, after: a, deviceId: BackupArchive.demoDeviceId))
                }
            }
            try? context.save()
            ready = true
        }
    }
}
#endif

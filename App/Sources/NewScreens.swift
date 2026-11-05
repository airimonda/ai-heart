import AiHeartCore
import LocalAuthentication
import SwiftData
import SwiftUI

// MARK: Letting go (design: Burning.dc.html)

/// The let-go animation: the paper's lower edge chars, unkept lines fade, embers rise.
/// Optional, brief, cancellable with Done; a still card under Reduce Motion (docs/10).
struct BurningView: View {
    let entry: Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burnt = false
    @State private var rise = false

    private var lines: [String] {
        let all = KeepOrRelease.sentences(entry.text ?? "")
        return all.isEmpty ? entry.keptLines : all
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Letting go").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                Text("The rest is burning. Only a short summary stays.").font(.subheadline).foregroundStyle(Palette.muted)
            }
            .padding(.top, 24)
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(RadialGradient(colors: [Palette.flame.opacity(0.65), Palette.flame.opacity(0)], center: .bottom, startRadius: 0, endRadius: 170))
                    .frame(width: 330, height: 150)
                    .offset(y: 34)
                    .opacity(burnt || reduceMotion ? 1 : 0.4)
                paper
                embers
            }
            Spacer(minLength: 0)
            Text("A short summary stays\(entry.keepNumbers ? " · numbers kept" : "")\n\(restText)")
                .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Palette.surface.ignoresSafeArea())
        .onAppear {
            guard !reduceMotion else { burnt = true; return }
            withAnimation(.easeInOut(duration: 2.2).delay(0.3)) { burnt = true }
            withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) { rise = true }
        }
        .accessibilityElement(children: .contain)
    }

    private var restText: String {
        if entry.status == .released { return "Gone now" }
        let d = max(1, Calendar.current.dateComponents([.day], from: .now, to: entry.restUntil ?? .now).day ?? 1)
        return "Resting for \(d) day\(d == 1 ? "" : "s"), then gone"
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { i, line in
                let kept = entry.keptLines.contains(line)
                Text(line)
                    .font(.journal(.body)).italic(kept)
                    .foregroundStyle(kept ? Palette.ink : Palette.muted)
                    .padding(kept ? 8 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(kept ? Palette.tint1 : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .opacity(kept ? 1 : (burnt ? (i.isMultiple(of: 2) ? 0.35 : 0.18) : 1))
                    .accessibilityLabel(kept ? "Kept: \(line)" : "Letting go")
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 70)
        .frame(width: 290)
        .background(Palette.card)
        .clipShape(TornEdge(depth: burnt ? 1 : 0))
        .shadow(color: Color(red: 0.47, green: 0.24, blue: 0.35).opacity(0.15), radius: 12, y: 8)
    }

    private var embers: some View {
        ZStack {
            ForEach(Array([(-90.0, 5.0, 0.8), (-40, 4, 0.6), (50, 6, 0.7), (100, 4, 0.5), (0, 3, 0.6), (-60, 3, 0.4)].enumerated()), id: \.offset) { i, e in
                Circle().fill(Palette.flame)
                    .frame(width: e.1, height: e.1)
                    .opacity(reduceMotion ? e.2 : (rise ? 0 : e.2))
                    .offset(x: e.0, y: reduceMotion ? -40 : (rise ? -160 - Double(i) * 12 : -10))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Paper with a burnt, torn bottom edge. depth 0 is a straight edge, 1 the full burn.
struct TornEdge: Shape {
    var depth: CGFloat
    var animatableData: CGFloat { get { depth } set { depth = newValue } }

    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(1, 0.74), (0.93, 0.80), (0.86, 0.75), (0.77, 0.84), (0.67, 0.77), (0.57, 0.86),
                                         (0.46, 0.78), (0.35, 0.85), (0.24, 0.76), (0.13, 0.83), (0, 0.76)]
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.width, y: 0))
        for (x, y) in pts {
            let yy = 1 - (1 - y) * depth
            p.addLine(to: CGPoint(x: r.width * x, y: r.height * yy))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: Locked (design: Locked.dc.html)

struct LockedView: View {
    let unlock: (_ biometrics: Bool) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 20).fill(Palette.card).frame(height: 56)
                RoundedRectangle(cornerRadius: 28).fill(Palette.card).frame(height: 230)
                RoundedRectangle(cornerRadius: 20).fill(Palette.card).frame(height: 120)
                RoundedRectangle(cornerRadius: 20).fill(Palette.card).frame(height: 160)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 56)
            .blur(radius: 14).opacity(0.55)
            Palette.surface.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer().frame(height: 200)
                Image(systemName: "lock")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Palette.action)
                    .frame(width: 84, height: 84)
                    .background(Palette.card, in: Circle())
                    .overlay(Circle().stroke(Palette.line))
                    .shadow(color: Palette.action.opacity(0.15), radius: 15, y: 8)
                    .accessibilityHidden(true)
                Text("AiHeart is locked").font(.title.bold()).foregroundStyle(Palette.ink).padding(.top, 22)
                Text("Your journal stays private.").font(.subheadline).foregroundStyle(Palette.muted).padding(.top, 6)
                Spacer()
                VStack(spacing: 6) {
                    Button { unlock(true) } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Use passcode") { unlock(false) }
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.muted).frame(minHeight: 44)
                }
                .padding(.horizontal, 24).padding(.bottom, 60)
            }
        }
        .background(Palette.surface.ignoresSafeArea())
    }
}

// MARK: First run (design: FirstRun.dc.html)

struct FirstRunView: View {
    let done: () -> Void
    @Environment(\.modelContext) private var context
    private var llm = LLMService.shared
    private var health = HealthService.shared

    static let doneKey = "firstRun.done"

    init(done: @escaping () -> Void) { self.done = done }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(Palette.action).padding(.top, 8)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Getting ready").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    Text(CloudSettings.isOn ? "A small language model runs on this iPhone. Photos and media never leave it." : "A small language model runs on this iPhone, so nothing you write or photograph leaves it.")
                        .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                }
                modelCard
                VStack(spacing: 0) {
                    step("Private storage", "Locked to this device", state: .done)
                    Divider().overlay(Palette.line).padding(.leading, 52)
                    step("Language model", modelLine, state: llm.state == .ready || llm.isDownloaded ? .done : (isWorking ? .working : .todo))
                    Divider().overlay(Palette.line).padding(.leading, 52)
                    Button {
                        NSLog("AiHeartUI first run: Health")
                        Task {
                            await health.requestAccess()
                            await health.sync(context: context)
                        }
                    } label: {
                        step("Health", health.asked ? "Connected. Reads only." : "Tap to connect. Reads only.", state: health.asked ? .done : (health.syncing ? .working : .todo))
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Palette.line).padding(.leading, 52)
                    step("Body baselines", "Learned from your own data over a few weeks", state: .todo)
                }
                .card()
                Button("Continue") {
                    NSLog("AiHeartUI first run: Continue")
                    UserDefaults.standard.set(true, forKey: Self.doneKey)
                    done()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.vertical, 40)
        }
        .background(Palette.surface.ignoresSafeArea())
    }

    private var isWorking: Bool {
        if case .downloading = llm.state { return true }
        return llm.state == .loading
    }

    private var modelLine: String {
        switch llm.state {
        case .ready: "On this phone"
        case .downloading(let f): "Downloading, \(Int(f * 100))%"
        case .loading: "Loading"
        case .unsupported: "Built-in rules here; the model runs on iPhone"
        case .failed: "Not loaded; you can try again in My rules"
        case .notDownloaded: llm.isDownloaded ? "On this phone" : "Not downloaded yet"
        }
    }

    @ViewBuilder private var modelCard: some View {
        if case .downloading(let f) = llm.state {
            VStack(alignment: .leading, spacing: 8) {
                Text("Language model").font(.headline).foregroundStyle(Palette.ink)
                Text("One time. You can use AiHeart while it finishes.").font(.caption).foregroundStyle(Palette.muted)
                ProgressView(value: f).tint(Palette.pink)
                Text("\(String(format: "%.1f", f * 3.5)) GB of 3.5 GB").font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        } else if !llm.isDownloaded, llm.state != .unsupported {
            VStack(alignment: .leading, spacing: 8) {
                Text("Language model").font(.headline).foregroundStyle(Palette.ink)
                Text("About 3.5 GB, once, on Wi-Fi. AiHeart works without it, with simpler suggestions.").font(.caption).foregroundStyle(Palette.muted)
                Button("Download now") { Task { await llm.prepare() } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    enum StepState { case done, working, todo }

    private func step(_ title: String, _ sub: String, state: StepState) -> some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Palette.onAction)
                        .frame(width: 24, height: 24).background(Palette.action, in: Circle())
                case .working:
                    ProgressView().frame(width: 24, height: 24)
                case .todo:
                    Circle().stroke(Palette.line, lineWidth: 2).frame(width: 24, height: 24)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(state == .todo ? Palette.muted : Palette.ink)
                Text(sub).font(.footnote).foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? "done" : state == .working ? "in progress" : "not yet")
    }
}

// MARK: Workout rating (design: WorkoutRating.dc.html)

struct WorkoutRatingSettingsView: View {
    @Bindable var s: AppSettings
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("One quiet nudge after a workout, if you want it.").font(.subheadline).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    RuleToggle(title: "Ask me after workouts", subtitle: "When a workout is detected, one notification asks how it felt.", isOn: $s.askToRateWorkouts)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    segmented("Wait after it ends", [("5 min", 5), ("10 min", 10), ("30 min", 30)], $s.rateWaitMinutes)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    segmented("Only workouts longer than", [("Any", 0), ("10 min", 10), ("20 min", 20)], $s.rateMinMinutes)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Skip when Hevy already has effort", subtitle: "So you are not asked twice.", isOn: $s.rateSkipIfHevyEffort)
                }
                .card()
                VStack(spacing: 0) {
                    fixed("Quiet delivery", "No sound, no badge. One per workout. If you ignore it, it goes away.")
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    fixed("Not during Pause", "Follows Pause everything, and your Focus and sleep settings.")
                }
                .card()
                Text("Light, Solid and Hard are quick answers right from the notification. Open it for a full 1 to 10 slider.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Workout rating")
        .onChange(of: s.askToRateWorkouts) { _, on in
            save()
            if on { Task { await WorkoutService.shared.requestNotificationPermission() } }
        }
        .onChange(of: s.rateWaitMinutes) { save() }
        .onChange(of: s.rateMinMinutes) { save() }
        .onChange(of: s.rateSkipIfHevyEffort) { save() }
    }

    private func save() { s.updatedAt = .now; try? context.save() }

    private func segmented(_ title: String, _ options: [(String, Int)], _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Picker(title, selection: value) {
                ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
    }

    private func fixed(_ title: String, _ sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(sub).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "checkmark").foregroundStyle(Palette.muted).accessibilityLabel("Always on")
        }
        .padding(18)
    }
}

import AiHeartCore
import SwiftData
import SwiftUI

/// Insights · Today (screen 21). Cycle (M4), workouts (M5), patterns (M6), outlook (M10)
/// and media (M18) arrive with their milestones.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @State private var mode = 0
    @State private var openOutlook = false
    @State private var openMedia = false

    private var dayStart: Int { settingsRows.first?.dayStartHour ?? 4 }
    private var paused: Bool { settingsRows.first?.pauseEverything ?? false }

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (DemoData.isOn(context) ? " · sample data" : ""))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)

                    Picker("View", selection: $mode) {
                        Text("Today").tag(0)
                        Text("Patterns").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if paused {
                        CalmNote(title: "Paused.", text: "No analysis while everything is paused. Capture still works.")
                    } else if mode == 1 {
                        PatternsView()
                    } else if !snap.hasData && HealthService.shared.syncing {
                        InsightsSkeleton(message: "Catching up with Apple Health")
                    } else if !snap.hasData {
                        ConnectHealthCard()
                    } else {
                        TodayBody(snap: snap)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Insights")
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-patterns") { mode = 1 }
                if ProcessInfo.processInfo.arguments.contains("-outlook") { openOutlook = true }
                if ProcessInfo.processInfo.arguments.contains("-media") { openMedia = true }
            }
            .navigationDestination(isPresented: $openOutlook) { OutlookView() }
            .navigationDestination(isPresented: $openMedia) { MediaView() }
            #endif
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollDown") ? .center : ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : .top)
            #endif
            .refreshable { await HealthService.shared.sync(context: context, dayStartHour: dayStart) }
        }
    }
}

struct CalmNote: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.journal(.title2)).foregroundStyle(Palette.ink)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
    }
}

struct ConnectHealthCard: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    private var health = HealthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health").font(.headline).foregroundStyle(Palette.ink)
            Text(health.asked
                 ? "No readings yet. If you turned access off, you can change it in Settings, Health, Data Access."
                 : "AiHeart reads sleep, heart, breathing, temperature and activity to show your body against your own usual. It only reads. Nothing leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            if !health.available {
                Text("Apple Health is not available on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            } else {
                Button(health.asked ? "Check again" : "Connect Apple Health") {
                    Task {
                        if !health.asked { await health.requestAccess() }
                        await health.sync(context: context, dayStartHour: settingsRows.first?.dayStartHour ?? 4)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .card()
    }
}

struct TodayBody: View {
    let snap: BodySnapshot
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your body today").font(.title2.bold()).foregroundStyle(Palette.ink)
                Spacer()
                NavigationLink {
                    YourBodyView()
                } label: {
                    HStack(spacing: 4) { Text("Details"); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                        .font(.headline)
                        .foregroundStyle(Palette.onTint)
                        .frame(minHeight: 44)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach([Signal.sleep, .restingHR, .hrv, .wristTemp], id: \.self) { s in
                    VitalCard(signal: s, snap: snap)
                }
            }

            OutlookLinkCard()

            MediaCard()

            ActivityCard(snap: snap)

            if snap.usesLabs {
                LabsCard()
            }

            if let today = snap.cycle?.current {
                Text("Your cycle").font(.title2.bold()).foregroundStyle(Palette.ink).padding(.top, 6)
                CycleCard(snap: snap, today: today)
            }

            Text(snap.cycle.map { $0.completedCycles >= Baselines.minCyclesForAdjustment } == true
                 ? "Your usual is your own, not a population norm. Resting HR, HRV, temperature and breathing are compared with the same phase of your recent cycles."
                 : "Your usual is the middle of your own last 28 days, not a population norm. Cycle-aware usuals start once three cycles are recorded.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 4)
        }
    }
}

struct VitalCard: View {
    let signal: Signal
    let snap: BodySnapshot

    var body: some View {
        let day = snap.today
        VStack(alignment: .leading, spacing: 8) {
            Text(signal.title).font(.subheadline).foregroundStyle(Palette.muted)
            Text(snap.formatted(signal, on: day) ?? "No reading")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Sparkline(points: snap.series(signal, endingAt: day), band: snap.baseline(signal, on: day))
                .frame(height: 30)
            Text(snap.phrase(signal, on: day))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(signal.title), \(snap.formatted(signal, on: day) ?? "no reading"), \(snap.phrase(signal, on: day))")
    }
}

struct ActivityCard: View {
    let snap: BodySnapshot
    @Query(sort: \Workout.start, order: .reverse) private var workouts: [Workout]

    private var recent: [Workout] {
        let since = Date().addingTimeInterval(-7 * 86400)
        return Array(workouts.filter { $0.start >= since }.prefix(5))
    }

    var body: some View {
        let day = snap.today
        let s = snap.summary(day)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                stat("Steps", s?.steps.map { Int($0.rounded()).formatted() } ?? "–",
                     snap.baseline(.steps, on: day).map { "usual \(Int($0.median.rounded()).formatted())" })
                stat("Burned", s?.activeKcal.map { "\(Int($0.rounded()))" } ?? "–",
                     s?.totalKcal.map { "active · \(Int($0.rounded()).formatted()) total" })
                stat("Exercise", s?.exerciseMin.map { "\(Int($0.rounded())) min" } ?? "–", weekExercise)
            }
            Text("Active calories, 7 days").font(.footnote).foregroundStyle(Palette.muted)
            MiniBars(points: snap.series(.activeKcal, endingAt: day))
                .frame(height: 40)
            if !recent.isEmpty {
                Divider().overlay(Palette.line)
                WorkoutList(workouts: recent)
            }
            Text("Workouts come from Apple Health and Hevy. Tap one to rate it.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .padding(16)
        .card()
    }

    private var weekExercise: String? {
        let total = snap.series(.exercise, endingAt: snap.today).reduce(0) { $0 + $1.value }
        return total > 0 ? "\(Int(total.rounded())) this week" : nil
    }

    private func stat(_ title: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted)
            Text(value).font(.title3.bold()).foregroundStyle(Palette.ink).minimumScaleFactor(0.7).lineLimit(1)
            if let sub { Text(sub).font(.caption).foregroundStyle(Palette.muted).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Your body (screen 05). Cycle and medication rows arrive with M4 and M7.
struct YourBodyView: View {
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @State private var days = 7

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Range", selection: $days) {
                    Text("Week").tag(7)
                    Text("4 weeks").tag(28)
                }
                .pickerStyle(.segmented)

                Text("Body today").font(.subheadline).foregroundStyle(Palette.muted).padding(.leading, 6)
                VStack(spacing: 0) {
                    ForEach(Array([Signal.sleep, .restingHR, .hrv, .wristTemp, .breathing, .steps].enumerated()), id: \.offset) { i, s in
                        if i > 0 { Divider().overlay(Palette.line).padding(.leading, 18) }
                        BodyRow(signal: s, snap: snap, days: days)
                    }
                }
                .card()

                Text("The lilac band is your usual range: the middle of your last 28 days, give or take. Gaps are days with no reading; they are left empty, not guessed.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Your body")
    }
}

struct BodyRow: View {
    let signal: Signal
    let snap: BodySnapshot
    var days = 7
    var day: AnchoredDay?

    var body: some View {
        let d = day ?? snap.today
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title).font(.headline).foregroundStyle(Palette.ink)
                Text(snap.phrase(signal, on: d)).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Group {
                if signal == .sleep || signal == .steps {
                    MiniBars(points: snap.series(signal, endingAt: d, days: days), days: days)
                } else {
                    Sparkline(points: snap.series(signal, endingAt: d, days: days), band: snap.baseline(signal, on: d), days: days)
                }
            }
            .frame(width: 84, height: 30)
            Text(snap.formatted(signal, on: d) ?? "–")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(signal.title), \(snap.formatted(signal, on: d) ?? "no reading"), \(snap.phrase(signal, on: d))")
    }
}

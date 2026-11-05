import AiHeartCore
import Charts
import SwiftData
import SwiftUI

/// Insights · Patterns (screen 04). Pre-specified questions only, each with n, an interval
/// and a minimum-sample gate. A clear end: "That is everything for now."
struct PatternsView: View {
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query private var entries: [Entry]
    @Query private var workouts: [Workout]

    /// Everything the tab shows, computed once per data change, off the main thread.
    struct Results: Sendable {
        let weeksWithData: Int
        let hasCycle: Bool
        let phases: [Patterns.Group]
        let sleep: Patterns.Scatter
        let lifts: [Patterns.Group]
        let weeks: [Patterns.Week]
        let links: [Patterns.Link]
    }

    @State private var results: Results?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = results {
                Text("\(r.weeksWithData) week\(r.weeksWithData == 1 ? "" : "s") of entries")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)

                MoodMapCard()

                if r.hasCycle {
                    PatternCard(title: "Mood by cycle phase", subtitle: "Average on the pleasant side, with uncertainty",
                                text: Patterns.describePhases(r.phases)) {
                        GroupBars(groups: r.phases)
                    }
                }

                PatternCard(title: "Sleep and the next day", subtitle: "Each dot is a night", text: Patterns.describeSleep(r.sleep)) {
                    if r.sleep.interval != nil { SleepScatter(scatter: r.sleep) }
                }

                PatternCard(title: "Activity and mood", subtitle: "Walks, jogs, lifting, aerobics, dance, yoga. Average on the pleasant side, with uncertainty",
                            text: Patterns.describeActivity(r.lifts)) {
                    GroupBars(groups: r.lifts)
                }

                PatternCard(title: "Training and recovery", subtitle: "Weekly load (bars) and HRV (line), 8 weeks",
                            text: Patterns.describeWeeks(r.weeks)) {
                    TrainingWeeks(weeks: r.weeks)
                }

                PatternCard(title: "What lines up with your mood",
                            subtitle: "How each signal moves with the next day's mood (sleep: the same day), with uncertainty",
                            text: "Dark means the link is clearer than chance. Pale means unclear. Most are pale early on, which is normal. A link is not a cause.") {
                    ForestPlot(links: r.links)
                }

                Text("That is everything for now.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) { ProgressView(); Text("Working out your patterns…") }
                    .font(.subheadline).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .task(id: "\(summaries.count)-\(entries.count)-\(workouts.count)") {
            let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
            let input = makeInput(snap)
            let hasCycle = snap.cycle != nil
            results = await Task.detached(priority: .userInitiated) {
                Results(weeksWithData: Set(input.mood.keys.map { $0.ordinal / 7 }).count, hasCycle: hasCycle,
                        phases: hasCycle ? Patterns.phaseGroups(input) : [], sleep: Patterns.sleepScatter(input),
                        lifts: Patterns.activityGroups(input), weeks: Patterns.weeks(input), links: Patterns.links(input))
            }.value
        }
    }

    private func makeInput(_ snap: BodySnapshot) -> PatternInput {
        PatternInputBuilder.make(snap: snap, entries: entries, workouts: workouts, dayStart: settingsRows.first?.dayStartHour ?? 4)
    }
}

enum PatternInputBuilder {
    static func make(snap: BodySnapshot, entries: [Entry], workouts: [Workout], dayStart: Int) -> PatternInput {
        // Her own taps only: points the model guessed from her writing never train patterns.
        let mood = TrainingMood.perDay(entries, dayStart: dayStart).mapValues(\.valence)
        var signals: [Signal: [AnchoredDay: Double]] = [:]
        for s in snap.all {
            guard let d = s.day else { continue }
            for sig in [Signal.sleep, .restingHR, .hrv, .wristTemp, .steps] {
                if let v = s.value(sig) { signals[sig, default: [:]][d] = v }
            }
        }
        var load: [AnchoredDay: Double] = [:]
        var lifts = Set<AnchoredDay>()
        var activity: [AnchoredDay: Set<ActivityGroup>] = [:]
        // Strava is display-only and never enters statistics (CLAUDE.md #6).
        for w in workouts where w.aiEligible {
            let d = DayAnchor.day(for: w.start, timeZone: .current, dayStartHour: dayStart)
            load[d, default: 0] += Double(w.minutes) * Double(w.rpe ?? 5)
            if w.kind == .strength { lifts.insert(d) }
            activity[d, default: []].insert(ActivityGroup.of(w.kind))
        }
        // Walking without a logged workout still counts (no watch yet).
        for s in snap.all {
            guard let d = s.day, activity[d] == nil, ActivityGroup.movedEnough(steps: s.steps, exerciseMin: s.exerciseMin) else { continue }
            activity[d] = [.walk]
        }
        let cycle = snap.cycle
        var input = PatternInput(mood: mood, signals: signals, load: load,
                                 liftDays: lifts, phase: { cycle?.phase($0) }, today: snap.today)
        input.activityDays = activity
        return input
    }
}

struct PatternCard<Chart: View>: View {
    let title: String
    let subtitle: String
    let text: String
    @ViewBuilder let chart: () -> Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(subtitle).font(.footnote).foregroundStyle(Palette.muted)
            }
            chart()
            Text(text).font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Bars from the bottom of the pad to the mean, whiskers for the 95% interval, n below.
struct GroupBars: View {
    let groups: [Patterns.Group]

    var body: some View {
        let ready = groups.filter { $0.interval != nil }
        if !ready.isEmpty {
            let lowest = ready.min { $0.interval!.estimate < $1.interval!.estimate }?.id
            Chart {
                ForEach(ready) { g in
                    let iv = g.interval!
                    BarMark(x: .value("Group", g.label), yStart: .value("Base", -1), yEnd: .value("Mean", iv.estimate), width: .ratio(0.55))
                        .foregroundStyle(g.id == lowest && ready.count > 2 ? Palette.pink : Palette.tint2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    RuleMark(x: .value("Group", g.label), yStart: .value("Low", iv.low), yEnd: .value("High", iv.high))
                        .foregroundStyle(Palette.dataMark)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYScale(domain: -1...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel {
                        if let label = v.as(String.self), let g = groups.first(where: { $0.label == label }) {
                            VStack(spacing: 0) {
                                Text(label).font(.caption).foregroundStyle(Palette.ink)
                                Text("n=\(g.n)").font(.caption2).foregroundStyle(Palette.muted)
                            }
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityElement()
            .accessibilityLabel(ready.map { "\($0.label): average \(String(format: "%.2f", $0.interval!.estimate)), n \($0.n)" }.joined(separator: ". "))
        }
    }
}

struct SleepScatter: View {
    let scatter: Patterns.Scatter

    var body: some View {
        let xs = scatter.points.map(\.hours)
        let lo = (xs.min() ?? 4).rounded(.down), hi = (xs.max() ?? 9).rounded(.up)
        Chart {
            if let fit = scatter.fit {
                ForEach(Array(stride(from: lo, through: hi, by: 0.25)), id: \.self) { x in
                    let b = fit.band(x)
                    AreaMark(x: .value("Sleep", x), yStart: .value("Low", b.0), yEnd: .value("High", b.1))
                        .foregroundStyle(Palette.lilacBand.opacity(0.8))
                }
                ForEach([lo, hi], id: \.self) { x in
                    LineMark(x: .value("Sleep", x), y: .value("Fit", fit.y(x)))
                        .foregroundStyle(Palette.dataMark)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            ForEach(Array(scatter.points.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Sleep", p.hours), y: .value("Mood", p.mood))
                    .foregroundStyle(Palette.tint2)
                    .symbolSize(40)
                    .symbol { Circle().strokeBorder(Palette.pink, lineWidth: 1.2).background(Circle().fill(Palette.tint1)).frame(width: 9, height: 9) }
            }
        }
        .chartXScale(domain: lo...hi)
        .chartYScale(domain: -1...1)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: 190)
        .overlay(alignment: .topLeading) {
            Text("more pleasant ↑").font(.caption).foregroundStyle(Palette.muted)
        }
        .safeAreaInset(edge: .bottom, spacing: 4) {
            HStack {
                Text("\(Int(lo)) h"); Spacer(); Text("\(Int(hi)) h sleep")
            }
            .font(.caption)
            .foregroundStyle(Palette.muted)
        }
        .accessibilityElement()
        .accessibilityLabel("Scatter of \(scatter.points.count) nights, sleep against the next day's mood")
    }
}

struct TrainingWeeks: View {
    let weeks: [Patterns.Week]

    var body: some View {
        let maxLoad = max(weeks.map(\.load).max() ?? 1, 1)
        let hrvs = weeks.compactMap(\.hrv)
        let hLo = (hrvs.min() ?? 0) - 3, hHi = (hrvs.max() ?? 1) + 3
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", Double(w.index)), y: .value("Load", w.load / maxLoad), width: .fixed(22))
                    .foregroundStyle(Palette.tint2)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            ForEach(weeks.filter { $0.hrv != nil }) { w in
                LineMark(x: .value("Week", Double(w.index)), y: .value("HRV", ((w.hrv ?? 0) - hLo) / max(hHi - hLo, 1)))
                    .foregroundStyle(Palette.dataMark)
                    .interpolationMethod(.catmullRom)
            }
            if let last = weeks.last, let h = last.hrv {
                PointMark(x: .value("Week", Double(last.index)), y: .value("HRV", (h - hLo) / max(hHi - hLo, 1)))
                    .foregroundStyle(Palette.dataMark)
            }
        }
        .chartXScale(domain: -0.6...(Double(weeks.count) - 0.4))
        .chartYScale(domain: 0...1.05)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: 130)
        .safeAreaInset(edge: .bottom, spacing: 4) {
            HStack { Text("8 wk ago"); Spacer(); Text("now") }
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement()
        .accessibilityLabel("Weekly training load and average HRV for eight weeks")
    }
}

/// Forest plot: rho and 95% interval per question. Dark when the interval excludes zero.
struct ForestPlot: View {
    let links: [Patterns.Link]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(links) { l in
                HStack(spacing: 10) {
                    Text(l.title).font(.subheadline).foregroundStyle(Palette.ink).frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        let w = geo.size.width
                        let x = { (v: Double) in (v + 1) / 2 * w }
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.line).frame(width: 1).offset(x: w / 2)
                            if let iv = l.interval {
                                let color = iv.excludesZero ? Palette.dataMark : Palette.tint2
                                Capsule().fill(color).frame(width: max(2, x(iv.high) - x(iv.low)), height: 3).offset(x: x(iv.low))
                                Circle().fill(iv.excludesZero ? Palette.dataMark : Palette.pink).frame(width: 12, height: 12).offset(x: x(iv.estimate) - 6)
                            } else {
                                Text("n=\(l.pairs) of \(Patterns.minPairs)").font(.caption2).foregroundStyle(Palette.muted)
                                    .offset(x: w / 2 + 6)
                            }
                        }
                        .frame(height: geo.size.height)
                    }
                    .frame(height: 22)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(l))
            }
            HStack {
                Spacer().frame(width: 110)
                Text("lower"); Spacer(); Text("no link"); Spacer(); Text("higher")
            }
            .font(.caption)
            .foregroundStyle(Palette.muted)
        }
    }

    private func label(_ l: Patterns.Link) -> String {
        guard let iv = l.interval else { return "\(l.title): not enough days yet, \(l.pairs) of \(Patterns.minPairs)" }
        return "\(l.title): \(String(format: "%.2f", iv.estimate)), from \(String(format: "%.2f", iv.low)) to \(String(format: "%.2f", iv.high)), \(iv.excludesZero ? "clearer than chance" : "unclear"), n \(iv.n)"
    }
}

import AiHeartCore
import Charts
import SwiftData
import SwiftUI

extension CyclePhase {
    var color: Color {
        switch self {
        case .period: Palette.phasePeriod
        case .follicular: Palette.phaseFollicular
        case .fertile: Palette.lilacFertile
        case .luteal: Palette.phaseLuteal
        }
    }
}

/// The cycle ring: phases as arcs, today as a ringed marker.
struct CycleRing: View {
    let today: CycleToday
    var lineWidth: CGFloat = 14
    var showMarker = true

    private var segments: [(CyclePhase, Int, Int)] {
        let n = today.expectedLength
        return [
            (.period, 1, today.periodDays),
            (.follicular, today.periodDays + 1, today.fertileStart - 1),
            (.fertile, today.fertileStart, today.fertileEnd),
            (.luteal, today.fertileEnd + 1, n),
        ].filter { $0.2 >= $0.1 }
    }

    var body: some View {
        GeometryReader { geo in
            let n = Double(today.expectedLength)
            let side = min(geo.size.width, geo.size.height)
            let r = (side - lineWidth) / 2
            let gap = 0.006
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: Double(seg.1 - 1) / n + gap, to: Double(seg.2) / n - gap)
                        .stroke(seg.0.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: r * 2, height: r * 2)
                }
                if showMarker {
                    let angle = (Double(today.day) - 0.5) / n * 2 * .pi - .pi / 2
                    Circle()
                        .fill(Palette.card)
                        .overlay(Circle().stroke(Palette.action, lineWidth: max(2, lineWidth * 0.25)))
                        .frame(width: lineWidth * 1.3, height: lineWidth * 1.3)
                        .offset(x: cos(angle) * r, y: sin(angle) * r)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Cycle day \(today.day) of about \(today.expectedLength), \(today.phase.rawValue), estimated")
    }
}

struct PhaseLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(CyclePhase.allCases, id: \.self) { p in
                HStack(spacing: 6) {
                    Circle().fill(p.color).frame(width: 10, height: 10)
                    Text(p.label)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.muted)
        .accessibilityElement(children: .combine)
    }
}

func nextPeriodText(_ c: CycleToday) -> String {
    c.nextPeriodIn <= 0 ? "Next period could start any day." :
        c.nextPeriodIn == 1 ? "Next period in about a day." : "Next period in about \(c.nextPeriodIn) days."
}

/// The cycle card on Insights · Today.
struct CycleCard: View {
    let snap: BodySnapshot
    let today: CycleToday

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    CycleRing(today: today, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text("Day \(today.day)").font(.title3.bold()).foregroundStyle(Palette.ink)
                        Text(today.phase.label).font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(today.phase.label) phase").font(.headline).foregroundStyle(Palette.ink)
                    Text("Day \(today.day) of about \(today.expectedLength). \(nextPeriodText(today))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                    NavigationLink { YourCycleView() } label: {
                        HStack(spacing: 4) { Text("See my cycle"); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                            .font(.headline)
                            .foregroundStyle(Palette.onTint)
                            .frame(minHeight: 44)
                    }
                }
            }
            PhaseLegend()
        }
        .padding(16)
        .card()
    }
}

/// Your cycle (screen 11).
struct YourCycleView: View {
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Environment(\.modelContext) private var context

    var body: some View {
        let snap = BodySnapshot.cached(summaries, settings: settingsRows.first)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if DemoData.isOn(context) {
                    Text("Sample data").font(.subheadline).foregroundStyle(Palette.muted)
                }
                if let cycle = snap.cycle, let today = cycle.current {
                    ringCard(cycle, today)
                    MoodAcrossCycle(cycle: cycle, entries: entries, dayStart: settingsRows.first?.dayStartHour ?? 4, today: today)
                    SignalAcrossCycle(title: "Resting heart rate", signal: .restingHR, snap: snap, cycle: cycle, today: today,
                                      note: "Resting heart rate often runs a little higher, and HRV lower, after ovulation. Once you have three cycles, your usual range is matched to the phase.")
                    SignalAcrossCycle(title: "Wrist temperature", signal: .wristTemp, snap: snap, cycle: cycle, today: today,
                                      note: "Temperature steps up after ovulation. When the step is clear, it is how AiHeart estimates where you are in your cycle.")
                } else {
                    CalmNote(title: "Not yet.", text: "Your cycle appears once Apple Health has period days. Log them in the Health app or a cycle app that writes to Health.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Your cycle")
    }

    private func ringCard(_ cycle: CycleAnalysis, _ today: CycleToday) -> some View {
        VStack(spacing: 14) {
            ZStack {
                CycleRing(today: today, lineWidth: 22)
                VStack(spacing: 2) {
                    Text("Day \(today.day)").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    Text(today.phase.label).font(.title3).foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 220, height: 220)
            PhaseLegend()
            Text("\(nextPeriodText(today)) Cycle length about \(cycle.expectedLength) days\(cycle.completedCycles > 0 ? ", from \(cycle.completedCycles) cycle\(cycle.completedCycles == 1 ? "" : "s")" : ", until your own cycles fill in").")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Text(today.method == .temp ? "Estimated from your wrist temperature." : "Estimated by calendar: no clear temperature step this cycle.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Phase shading behind a cycle-day chart, using today's cycle layout.
struct PhaseBands: ChartContent {
    let today: CycleToday

    var body: some ChartContent {
        let n = today.expectedLength
        let spans: [(CyclePhase, Int, Int)] = [
            (.period, 1, today.periodDays),
            (.follicular, today.periodDays + 1, today.fertileStart - 1),
            (.fertile, today.fertileStart, today.fertileEnd),
            (.luteal, today.fertileEnd + 1, n),
        ]
        ForEach(Array(spans.enumerated()), id: \.offset) { _, s in
            if s.2 >= s.1 {
                RectangleMark(xStart: .value("From", Double(s.1) - 0.5), xEnd: .value("To", Double(s.2) + 0.5))
                    .foregroundStyle(s.0.color.opacity(0.45))
            }
        }
        RuleMark(x: .value("Today", today.day))
            .foregroundStyle(Palette.dataMark.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }
}

/// Mean of a signal by cycle day across her cycles.
struct SignalAcrossCycle: View {
    let title: String
    let signal: Signal
    let snap: BodySnapshot
    let cycle: CycleAnalysis
    let today: CycleToday
    let note: String

    private var points: [(day: Int, value: Double)] {
        var bins: [Int: [Double]] = [:]
        for s in snap.all {
            guard let d = s.day, let v = s.value(signal), let n = cycle.cycleDay(d), n <= today.expectedLength else { continue }
            bins[n, default: []].append(v)
        }
        return bins.keys.sorted().map { ($0, bins[$0]!.reduce(0, +) / Double(bins[$0]!.count)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text("Average by cycle day, \(cycle.cycles.count) cycle\(cycle.cycles.count == 1 ? "" : "s")")
                .font(.footnote).foregroundStyle(Palette.muted)
            Chart {
                PhaseBands(today: today)
                ForEach(points, id: \.day) { p in
                    LineMark(x: .value("Day", p.day), y: .value(title, p.value))
                        .foregroundStyle(Palette.dataMark)
                        .interpolationMethod(.catmullRom)
                }
                if let t = points.first(where: { $0.day == today.day }) {
                    PointMark(x: .value("Day", t.day), y: .value(title, t.value))
                        .foregroundStyle(Palette.dataMark)
                }
            }
            .chartXScale(domain: 0.5...(Double(today.expectedLength) + 0.5))
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: [1, 7, 14, 21, 28]) }
            .chartYAxis(.hidden)
            .frame(height: 130)
            Text(note).font(.subheadline).foregroundStyle(Palette.muted)
        }
        .padding(18)
        .card()
    }
}

/// Mood (pleasant side) by cycle day, learned only from her own entries. Gated.
struct MoodAcrossCycle: View {
    let cycle: CycleAnalysis
    let entries: [Entry]
    let dayStart: Int
    let today: CycleToday

    static let minEntries = 20
    static let minCycles = 2

    private struct Bin { let mid: Double; let mean: Double; let sd: Double; let n: Int }

    private var data: (bins: [Bin], n: Int, cycles: Int) {
        var pairs: [(Int, Double)] = []
        var cyclesSeen = Set<Int>()
        for e in entries where e.status != .released {
            guard let v = e.valence else { continue }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart)
            guard let n = cycle.cycleDay(d), n <= today.expectedLength,
                  let c = cycle.cycle(containing: d) else { continue }
            pairs.append((n, v))
            cyclesSeen.insert(c.start.ordinal)
        }
        // Four-day bins keep each point from resting on one or two entries.
        var bins: [Bin] = []
        for start in stride(from: 1, through: today.expectedLength, by: 4) {
            let vs = pairs.filter { $0.0 >= start && $0.0 < start + 4 }.map(\.1)
            guard vs.count >= 2 else { continue }
            let mean = vs.reduce(0, +) / Double(vs.count)
            let sd = sqrt(vs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(vs.count - 1))
            bins.append(Bin(mid: Double(start) + 1.5, mean: mean, sd: sd, n: vs.count))
        }
        return (bins, pairs.count, cyclesSeen.count)
    }

    var body: some View {
        let d = data
        VStack(alignment: .leading, spacing: 10) {
            Text("Mood across your cycle").font(.headline).foregroundStyle(Palette.ink)
            if d.n < Self.minEntries || d.cycles < Self.minCycles {
                Text("Not yet. This needs at least \(Self.minEntries) entries over \(Self.minCycles) cycles; there are \(d.n) over \(d.cycles).")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                Text("How pleasant it felt, by cycle day, from \(d.n) entries over \(d.cycles) cycles. The band is the spread.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Chart {
                    PhaseBands(today: today)
                    ForEach(d.bins, id: \.mid) { b in
                        AreaMark(x: .value("Day", b.mid), yStart: .value("Low", b.mean - b.sd), yEnd: .value("High", b.mean + b.sd))
                            .foregroundStyle(Palette.pink.opacity(0.25))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Day", b.mid), y: .value("Pleasant", b.mean))
                            .foregroundStyle(Palette.dataMark)
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartXScale(domain: 0.5...(Double(today.expectedLength) + 0.5))
                .chartYScale(domain: -1...1)
                .chartXAxis { AxisMarks(values: [1, 7, 14, 21, 28]) }
                .chartYAxis(.hidden)
                .frame(height: 140)
                Text("Learned only from your entries. Some people notice changes across the cycle and many do not.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            }
        }
        .padding(18)
        .card()
    }
}

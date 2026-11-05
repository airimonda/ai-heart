import AiHeartCore
import Charts
import SwiftUI

/// Read-only view of the day summaries, with her own baselines.
struct BodySnapshot {
    let byKey: [String: DaySummary]
    let all: [DaySummary]
    let today: AnchoredDay
    /// Nil when she has turned cycle tracking off or there is no flow data.
    let cycle: CycleAnalysis?
    /// Fast window lookups, so years of history stay quick.
    let index: SignalIndex

    init(_ summaries: [DaySummary], dayStartHour: Int, usesCycle: Bool = true) {
        all = summaries
        var map: [String: DaySummary] = [:]
        for s in summaries where map[s.dayKey] == nil { map[s.dayKey] = s }
        byKey = map
        today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStartHour)
        if usesCycle {
            var flow = Set<AnchoredDay>()
            var temps: [AnchoredDay: Double] = [:]
            for s in summaries {
                guard let d = s.day else { continue }
                if (s.menstrualFlow ?? 0) > 0 { flow.insert(d) }
                if let t = s.wristTempC { temps[d] = t }
            }
            cycle = flow.isEmpty ? nil : CycleEngine.analyze(flowDays: flow, wristTemps: temps, today: today)
        } else {
            cycle = nil
        }
        index = SignalIndex(summaries, cycle: cycle)
    }

    /// One shared snapshot, rebuilt only when the data, the settings or the day change.
    /// Building it over years of Health data is the expensive part, and views read it
    /// many times per refresh.
    @MainActor private static var cache: (key: String, snap: BodySnapshot)?

    @MainActor static func cached(_ summaries: [DaySummary], settings: AppSettings?) -> BodySnapshot {
        var latest = Date.distantPast
        for s in summaries where s.updatedAt > latest { latest = s.updatedAt }
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: settings?.dayStartHour ?? 4)
        let key = "\(summaries.count)|\(latest.timeIntervalSince1970)|\(settings?.usesCycle ?? true)|\(settings?.usesLabs ?? true)|\(settings?.dayStartHour ?? 4)|\(today.key)"
        if let c = cache, c.key == key { return c.snap }
        let t0 = Date()
        let snap = HangWatch.mark("body snapshot") { BodySnapshot(summaries, settings: settings) }
        NSLog("AiHeartPerf snapshot %d days in %.2f s", summaries.count, Date().timeIntervalSince(t0))
        cache = (key, snap)
        return snap
    }

    init(_ summaries: [DaySummary], settings: AppSettings?) {
        self.init(summaries, dayStartHour: settings?.dayStartHour ?? 4, usesCycle: settings?.usesCycle ?? true)
        usesLabs = settings?.usesLabs ?? true
    }

    var usesLabs = true

    /// True when the usual range for this signal and day is matched to the cycle phase.
    func adjusted(_ signal: Signal, on day: AnchoredDay) -> Bool {
        cycle != nil && index.cycleBaseline(signal, on: day) != nil
    }

    func cycleLabel(_ day: AnchoredDay) -> String? {
        guard let cycle, let n = cycle.cycleDay(day), let p = cycle.phase(day) else { return nil }
        return "Day \(n) · \(p.rawValue)"
    }

    var hasData: Bool { !all.isEmpty }

    func summary(_ day: AnchoredDay) -> DaySummary? { byKey[day.key] }

    func value(_ signal: Signal, on day: AnchoredDay) -> Double? { index.value(signal, on: day) }

    /// Phase-matched once there are enough cycles; otherwise her global 28-day usual.
    func baseline(_ signal: Signal, on day: AnchoredDay) -> Baseline? {
        if cycle != nil, let b = index.cycleBaseline(signal, on: day) { return b }
        return index.globalBaseline(signal, on: day)
    }

    func reading(_ signal: Signal, on day: AnchoredDay) -> Reading? {
        guard let v = value(signal, on: day), let b = baseline(signal, on: day) else { return nil }
        return b.reading(v)
    }

    func z(_ signal: Signal, on day: AnchoredDay) -> Double? {
        guard let v = value(signal, on: day), let b = baseline(signal, on: day) else { return nil }
        return b.z(v)
    }

    /// The last `days` days ending at `day`, with gaps left as gaps (no imputation).
    func series(_ signal: Signal, endingAt day: AnchoredDay, days: Int = 7) -> [(offset: Int, value: Double)] {
        index.series(signal, endingAt: day, days: days)
    }

    var bodyToday: BodyToday {
        BodyToday(sleepZ: z(.sleep, on: today), restingHRZ: z(.restingHR, on: today), hrvZ: z(.hrv, on: today))
    }

    /// Short text for a signal's state, honest about how much data there is.
    func phrase(_ signal: Signal, on day: AnchoredDay) -> String {
        if value(signal, on: day) == nil { return "No reading" }
        if let r = reading(signal, on: day) {
            if adjusted(signal, on: day), let p = cycle?.phase(day) {
                let phase = p == .luteal ? "a luteal day" : "this part of your cycle"
                return r == .within ? "Usual for \(phase)" : "\(r.phrase(for: signal).replacingOccurrences(of: " your usual", with: "")), for \(phase)"
            }
            return r.phrase(for: signal)
        }
        let n = index.daysWithData(signal, before: day)
        return "Learning your usual · \(n) of \(Baselines.minDays) days"
    }

    func formatted(_ signal: Signal, on day: AnchoredDay) -> String? {
        guard let v = value(signal, on: day) else { return nil }
        if signal == .wristTemp {
            guard let b = baseline(.wristTemp, on: day) else { return String(format: "%.1f°", v) }
            return String(format: "%+.1f°", v - b.median)
        }
        return BodyFormat.value(signal, v)
    }
}

enum BodyFormat {
    static func value(_ signal: Signal, _ v: Double) -> String {
        switch signal {
        case .sleep: return duration(v)
        case .restingHR: return "\(Int(v.rounded())) bpm"
        case .hrv: return "\(Int(v.rounded())) ms"
        case .wristTemp: return String(format: "%.1f°", v)
        case .breathing: return String(format: "%.0f / min", v)
        case .steps: return Int(v.rounded()).formatted()
        case .activeKcal: return "\(Int(v.rounded())) kcal"
        case .exercise: return "\(Int(v.rounded())) min"
        }
    }

    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

/// Seven-day line with her usual range as a lilac band and today's point marked.
struct Sparkline: View {
    let points: [(offset: Int, value: Double)]
    var band: Baseline?
    var days = 7

    var body: some View {
        Chart {
            if let band {
                RectangleMark(xStart: .value("Start", 0), xEnd: .value("End", days - 1),
                              yStart: .value("Low", band.low), yEnd: .value("High", band.high))
                    .foregroundStyle(Palette.lilacBand)
            }
            ForEach(points, id: \.offset) { p in
                LineMark(x: .value("Day", p.offset), y: .value("Value", p.value))
                    .foregroundStyle(Palette.dataMark)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let last = points.last, last.offset == days - 1 {
                PointMark(x: .value("Day", last.offset), y: .value("Value", last.value))
                    .foregroundStyle(Palette.dataMark)
                    .symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...(days - 1))
        .chartYScale(domain: yDomain)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        var vals = points.map(\.value)
        if let band { vals += [band.low, band.high] }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 0.01)
        return (lo - pad)...(hi + pad)
    }
}

/// Small bars, last bar in the data color.
struct MiniBars: View {
    let points: [(offset: Int, value: Double)]
    var days = 7
    var barWidth: CGFloat { days > 10 ? 2 : 14 }

    var body: some View {
        Chart {
            ForEach(points, id: \.offset) { p in
                BarMark(x: .value("Day", Double(p.offset)), y: .value("Value", p.value), width: .fixed(barWidth))
                    .foregroundStyle(p.offset == days - 1 ? Palette.dataMark : Palette.tint2)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: -0.5...(Double(days) - 0.5))
        .chartYScale(domain: 0...(max(points.map(\.value).max() ?? 1, 1)))
        .accessibilityHidden(true)
    }
}

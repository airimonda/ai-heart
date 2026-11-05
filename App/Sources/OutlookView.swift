import AiHeartCore
import Charts
import SwiftData
import SwiftUI

/// Mood outlook (M10, design: EarlySigns). A lean from her own days, never a prediction.
/// Chart owner choice 2026-11-01: recent days as a line, the next three dotted with a band.
struct OutlookView: View {
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query private var entries: [Entry]
    @Query private var workouts: [Workout]
    @Query private var doses: [DoseChange]

    @State private var result: OutlookBuilder.Result?
    @State private var inputs: [OutlookBuilder.DayInput] = []
    @State private var loading = true
    @State private var read: String?
    @State private var readFromModel = false
    @State private var question = ""
    @State private var answer: String?
    @State private var answering = false

    private var settings: AppSettings? { settingsRows.first }
    private var dayStart: Int { settings?.dayStartHour ?? 4 }
    private var options: OutlookBuilder.Options {
        .init(useCycle: settings?.usesCycle ?? true, useDoses: settings?.usesLabs ?? true, useTraining: settings?.usesTraining ?? true)
    }
    private var demo: Bool { DemoData.isOn(context) }
    private var refreshKey: String {
        "\(entries.count)|\(summaries.count)|\(workouts.count)|\(doses.count)|\(options.useCycle)\(options.useDoses)\(options.useTraining)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((demo ? "Sample data · " : "") + "\(inputs.filter { $0.valence != nil }.count) days with a mood point")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Text("Mood outlook").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                }
                if loading {
                    InsightsSkeleton(message: "Working out your outlook")
                } else if let r = result {
                    readCard(r)
                    nextDaysCard(r)
                    driversCard(r)
                    recordCard(r)
                    togglesCard
                    askSection(r)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not yet").font(.headline).foregroundStyle(Palette.ink)
                        Text("The outlook needs about \(OutlookBuilder.daysUntilReady(inputs)) more days with a mood point. Any entry with a feeling counts.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    togglesCard
                }
                Text("An outlook is a lean based on your own past, never a prediction. If it starts to shape how you feel, switch it off.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : .top)
        #endif
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: refreshKey) { await compute() }
    }

    // MARK: Cards

    private func readCard(_ r: OutlookBuilder.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("AiHeart's read").font(.headline).foregroundStyle(Palette.ink)
                Text("on your phone").font(.caption2.weight(.semibold)).foregroundStyle(Palette.onTint)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Palette.tint1, in: Capsule())
            }
            Text(read ?? OutlookBuilder.fallbackRead(r)).font(.body).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("A lean from \(r.daysWithMood) days of your own data, not a rule. "
                 + (readFromModel ? "Written by the on-device model from numbers your phone worked out." : "Worked out on your phone."))
                .font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private struct ChartPoint: Identifiable {
        let id: Int
        let offset: Int
        let value: Double
        let low: Double?
        let high: Double?
        let outlook: Bool
    }

    private func chartPoints(_ r: OutlookBuilder.Result) -> [ChartPoint] {
        let today = r.points[0].day
        var out: [ChartPoint] = []
        for d in inputs where d.day >= today.adding(days: -7) && d.day < today {
            if let v = d.valence { out.append(ChartPoint(id: out.count, offset: today.ordinal - d.day.ordinal, value: v, low: nil, high: nil, outlook: false)) }
        }
        // Join the line to the outlook at the last real day.
        for (h, p) in r.points.enumerated() {
            out.append(ChartPoint(id: out.count, offset: -h, value: p.valence, low: p.low, high: p.high, outlook: true))
        }
        return out
    }

    private func nextDaysCard(_ r: OutlookBuilder.Result) -> some View {
        let pts = chartPoints(r)
        let lastReal = pts.filter { !$0.outlook }.min { $0.offset < $1.offset }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Next three days").font(.headline).foregroundStyle(Palette.ink)
            Chart {
                ForEach(pts.filter(\.outlook)) { p in
                    AreaMark(x: .value("Day", Double(-p.offset)), yStart: .value("Low", p.low ?? p.value), yEnd: .value("High", p.high ?? p.value))
                        .foregroundStyle(Palette.pink.opacity(0.28))
                        .interpolationMethod(.monotone)
                }
                ForEach(pts.filter { !$0.outlook }) { p in
                    LineMark(x: .value("Day", Double(-p.offset)), y: .value("Mood", p.value), series: .value("Kind", "Logged"))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Day", Double(-p.offset)), y: .value("Mood", p.value))
                        .foregroundStyle(Palette.ink.opacity(0.7)).symbolSize(18)
                }
                ForEach((lastReal.map { [ChartPoint(id: -1, offset: $0.offset, value: $0.value, low: nil, high: nil, outlook: true)] } ?? [])
                        + pts.filter(\.outlook)) { p in
                    LineMark(x: .value("Day", Double(-p.offset)), y: .value("Mood", p.value), series: .value("Kind", "Outlook"))
                        .foregroundStyle(Palette.action)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Usual", r.usualValence))
                    .foregroundStyle(Palette.line).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                RuleMark(x: .value("Today", -0.5)).foregroundStyle(Palette.line)
            }
            .chartYScale(domain: -1...1)
            .chartXScale(domain: -7...2.3)
            .chartYAxis {
                AxisMarks(position: .leading, values: [-0.8, 0, 0.8]) { v in
                    AxisValueLabel { Text(v.as(Double.self).map { $0 > 0 ? "Pleasant" : $0 < 0 ? "Lower" : "Middle" } ?? "") }
                }
            }
            .chartXAxis {
                AxisMarks(values: [-7, 0, 2]) { v in
                    AxisValueLabel { Text(dayLabel(v.as(Double.self) ?? 0, today: r.points[0].day)) }
                }
            }
            .frame(height: 170)
            .accessibilityLabel("Recent mood as a line, and the next three days as a dotted line with a band")

            ForEach(Array(r.points.enumerated()), id: \.offset) { i, p in
                HStack(alignment: .firstTextBaseline) {
                    Text(i == 0 ? "Today" : p.day.date(in: .current).formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).frame(width: 96, alignment: .leading)
                    Text(p.valenceWord + (p.arousalWord.map { ", " + $0 } ?? "")).font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer()
                }
            }
            Text("The band shows how unsure it is. A wider band means less certain.").font(.caption).foregroundStyle(Palette.muted)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func dayLabel(_ x: Double, today: AnchoredDay) -> String {
        let n = Int(x.rounded())
        if n == 0 { return "Today" }
        let d = today.adding(days: n).date(in: .current)
        return n > 0 ? d.formatted(.dateTime.weekday(.abbreviated)) : d.formatted(.dateTime.day().month(.abbreviated))
    }

    private func driversCard(_ r: OutlookBuilder.Result) -> some View {
        let maxSize = max(r.drivers.map(\.size).max() ?? 0.01, 0.01)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What it is looking at").font(.headline).foregroundStyle(Palette.ink)
                Text("Each bar pulls today's outlook one way").font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            ForEach(Array(r.drivers.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider().padding(.leading, 16) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(d.feature.label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(d.direction).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    GeometryReader { g in
                        let half = g.size.width / 2
                        let w = half * min(1, d.size / maxSize) * 0.9
                        let right = d.direction == "toward pleasant" || d.direction == "toward stirred"
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.segment)
                            Capsule().fill(Palette.pink).frame(width: w).offset(x: right ? half : half - w)
                            Rectangle().fill(Palette.line).frame(width: 1).offset(x: half)
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func recordCard(_ r: OutlookBuilder.Result) -> some View {
        let rec = r.record
        return VStack(alignment: .leading, spacing: 8) {
            Text("Does it work for you?").font(.headline).foregroundStyle(Palette.ink)
            Text("Expected against what you logged, \(rec.n) days").font(.caption).foregroundStyle(Palette.muted)
            if !rec.points.isEmpty {
                Chart {
                    LineMark(x: .value("Expected", -1.0), y: .value("Happened", -1.0), series: .value("k", "diag"))
                        .foregroundStyle(Palette.action).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    LineMark(x: .value("Expected", 1.0), y: .value("Happened", 1.0), series: .value("k", "diag"))
                        .foregroundStyle(Palette.action).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    ForEach(Array(rec.points.enumerated()), id: \.offset) { _, p in
                        PointMark(x: .value("Expected", p.expected), y: .value("Happened", p.actual))
                            .foregroundStyle(Palette.pink.opacity(0.85)).symbolSize(40)
                    }
                }
                .chartXScale(domain: -1...1).chartYScale(domain: -1...1)
                .chartXAxis { AxisMarks(values: [0]) { _ in AxisValueLabel("expected") } }
                .chartYAxis { AxisMarks(position: .leading, values: [0]) { _ in AxisValueLabel("what happened") } }
                .frame(height: 170)
                .accessibilityLabel("Expected mood against logged mood")
            }
            Group {
                if rec.beatsBaselines {
                    Text("Close on \(rec.close) of \(rec.n) days. It beats both simple guesses (same as yesterday, and your 7-day average).")
                } else if rec.n == 0 {
                    Text("No track record yet. It will tell you when it has one.")
                } else {
                    Text("Close on \(rec.close) of \(rec.n) days. Better than guessing \u{201C}same as yesterday\u{201D}? ") + Text("Not yet").bold()
                        + Text(rec.daysNeeded > 0 ? ". It needs about \(max(1, rec.daysNeeded / 7)) more weeks, and it will tell you when it does." : ". Treat it as a loose lean for now.")
                }
            }
            .font(.footnote).foregroundStyle(Palette.ink)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
    }

    @ViewBuilder private var togglesCard: some View {
        if let s = settings {
            @Bindable var s = s
            VStack(spacing: 0) {
                RuleToggle(title: "Show the outlook", subtitle: "On the Now screen", isOn: $s.outlookOn)
                Divider().padding(.leading, 16)
                RuleToggle(title: "Use my cycle", subtitle: "Phase and day", isOn: $s.usesCycle)
                Divider().padding(.leading, 16)
                RuleToggle(title: "Use dose changes", subtitle: "So they are not mistaken for mood", isOn: $s.usesLabs)
                Divider().padding(.leading, 16)
                RuleToggle(title: "Use training", subtitle: "Load and recovery", isOn: $s.usesTraining)
            }
            .card()
            .onChange(of: "\(s.outlookOn)\(s.usesCycle)\(s.usesLabs)\(s.usesTraining)") { s.updatedAt = .now; try? context.save() }
        }
    }

    private func askSection(_ r: OutlookBuilder.Result) -> some View {
        let todayWord = r.points[0].arousalWord ?? r.points[0].valenceWord
        let chips = ["Why \(todayWord.replacingOccurrences(of: "a bit ", with: "").replacingOccurrences(of: "leans ", with: ""))?",
                     "What changed it before?", "What if I sleep more?"]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ask about it").font(.subheadline).foregroundStyle(Palette.muted)
            FlowLayout(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    Chip(title: c) { Task { await ask(c, r) } }
                }
            }
            HStack {
                TextField("Ask in your own words", text: $question)
                    .submitLabel(.send)
                    .onSubmit { let q = question; Task { await ask(q, r) } }
                if !question.isEmpty {
                    Button { let q = question; Task { await ask(q, r) } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .foregroundStyle(Palette.action).accessibilityLabel("Ask")
                }
            }
            .padding(.horizontal, 18).frame(minHeight: 48)
            .background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.line))
            if answering {
                ProgressView().frame(maxWidth: .infinity)
            } else if let answer {
                Text(answer).font(.body).foregroundStyle(Palette.ink)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
    }

    // MARK: Work

    private func compute() async {
        loading = result == nil
        let dayInputs = makeInputs()
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart)
        let opts = options
        let r = await Task.detached(priority: .userInitiated) { OutlookBuilder.build(dayInputs, today: today, options: opts) }.value
        inputs = dayInputs
        result = r
        loading = false
        read = nil; readFromModel = false
        if let r { await writeRead(r) }
    }

    private func makeInputs() -> [OutlookBuilder.DayInput] {
        let snap = BodySnapshot.cached(summaries, settings: settings)
        // Her own taps only: points the model guessed from her writing never train the outlook.
        let mood = TrainingMood.perDay(entries, dayStart: dayStart)
        var lifted: [AnchoredDay: Double] = [:]
        for w in workouts where [.strength, .hiit, .run, .cycle, .swim].contains(w.kind) && w.aiEligible {
            lifted[DayAnchor.day(for: w.start, timeZone: .current, dayStartHour: dayStart), default: 0] += Double(w.minutes)
        }
        let doseDays = doses.map { DayAnchor.day(for: $0.date, timeZone: .current, dayStartHour: dayStart) }
        var days = Set(mood.keys)
        days.insert(snap.today)
        if let first = days.min() {
            var d = first
            while d <= snap.today { if snap.summary(d) != nil { days.insert(d) }; d = d.adding(days: 1) }
        }
        let rhythm = SleepRhythm.outlookZ(NightSample.from(snap.all), days: days.sorted())
        return days.sorted().map { d in
            let m = mood[d]
            let lastDose = doseDays.filter { $0 <= d }.max()
            return OutlookBuilder.DayInput(day: d, sleepZ: snap.z(.sleep, on: d), restingHRZ: snap.z(.restingHR, on: d), hrvZ: snap.z(.hrv, on: d),
                                           luteal: snap.cycle?.phase(d).map { $0 == .luteal },
                                           sleepShiftZ: rhythm[d]?.shiftZ, sleepIrregularZ: rhythm[d]?.irregularZ,
                                           liftedYesterdayMin: lifted[d.adding(days: -1)] ?? 0,
                                           daysSinceDose: lastDose.map { d.ordinal - $0.ordinal },
                                           valence: m?.valence, arousal: m?.arousal)
        }
    }

    private static let system = """
    You write a short read of a mood outlook for a private journal. Use only the facts given. \
    Three or four plain sentences, calm and direct. Describe a lean, never a prediction. \
    Never diagnose, never label a state, never give advice, never reassure. \
    Do not use any number that is not in the facts.
    """

    private func writeRead(_ r: OutlookBuilder.Result) async {
        let llm = LLMService.shared
        guard llm.isDownloaded else { return }
        if llm.state != .ready { await llm.prepare() }
        let facts = OutlookBuilder.factsJSON(r)
        let prompt = "Facts: \(facts)\nWrite the read."
        // Facts from her numbers and the About me block; none of her entry text, so nothing of hers to gate.
        let model = llm.model(for: .outlook)
        let out = await OutputValidator.generate(model, GenerationRequest(system: Self.system + SeedImport.promptContext(context, full: true), prompt: prompt, maxTokens: 160, temperature: 0.3, ownText: ""),
                                                 policy: OutputPolicy(input: prompt, quietTopics: WordFinder.quietTopics(context), maxCharacters: 520))
        NSLog("AiHeartLLM outlook read: result=%d last=%@", out == nil ? 0 : 1, OutputValidator.lastFailure ?? "-")
        if let out, model.name != "Built-in rules" { read = out; readFromModel = true }
    }

    private func ask(_ q: String, _ r: OutlookBuilder.Result) async {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        answering = true; question = ""
        defer { answering = false }
        var facts = r.facts
        if let w = OutlookBuilder.whatIfMoreSleep(inputs, today: r.points[0].day, options: options) {
            facts["with_more_sleep_tomorrow"] = Outlook.valenceWord(w.more, usual: r.usualValence)
            facts["as_things_are_tomorrow"] = Outlook.valenceWord(w.now, usual: r.usualValence)
        }
        let fallback = Self.fallbackAnswer(q, r, facts: facts)
        let llm = LLMService.shared
        guard llm.isDownloaded else { answer = fallback; return }
        if llm.state != .ready { await llm.prepare() }
        let json = "{" + facts.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ", ") + "}"
        let prompt = "Facts: \(json)\nHer question: \(q)\nAnswer in two or three sentences from the facts only. If the facts do not answer it, say so."
        // Her question is her own text: it passes the self-harm gate before a cloud call.
        let out = await OutputValidator.generate(llm.model(for: .outlook), GenerationRequest(system: Self.system + SeedImport.promptContext(context, full: true), prompt: prompt, maxTokens: 140, temperature: 0.3, ownText: q),
                                                 policy: OutputPolicy(input: prompt, userText: q, quietTopics: WordFinder.quietTopics(context), maxCharacters: 420))
        answer = out ?? fallback
    }

    static func fallbackAnswer(_ q: String, _ r: OutlookBuilder.Result, facts: [String: String]) -> String {
        let lower = q.lowercased()
        if lower.contains("sleep") {
            if let more = facts["with_more_sleep_tomorrow"], let now = facts["as_things_are_tomorrow"] {
                return more == now ? "In your own days so far, a longer night has not moved the next day much: tomorrow stays \(now)."
                                   : "In your own days so far, a longer night goes with a next day that \(more), compared with \(now) as things are."
            }
            return "There is not enough sleep data yet to say."
        }
        let ds = r.drivers.filter { $0.size >= 0.01 }.prefix(3)
        if lower.contains("before") || lower.contains("changed") {
            return ds.isEmpty ? "Nothing stands out in your days so far."
                : "In your past days, the things that moved the next day most were " + ds.map { $0.feature.phrase }.joined(separator: ", ") + "."
        }
        return ds.isEmpty ? "Nothing pulls today away from your usual."
            : "Today's lean comes mostly from " + ds.map { "\($0.feature.phrase) (\($0.direction))" }.joined(separator: " and ") + "."
    }
}

/// Entry to the outlook from Insights · Today.
struct OutlookLinkCard: View {
    var body: some View {
        NavigationLink { OutlookView() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mood outlook").font(.headline).foregroundStyle(Palette.ink)
                    Text("Today and the next two days, from your own days").font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.onTint)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .buttonStyle(.plain)
    }
}

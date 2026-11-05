import AiHeartCore
import SwiftData
import SwiftUI

/// Records and reads her feedback on the app's guesses.
@MainActor
enum GuessLog {
    static func today(_ context: ModelContext) -> AnchoredDay {
        DayAnchor.day(for: .now, timeZone: .current, dayStartHour: AiHeartStore.settings(in: context).dayStartHour)
    }

    /// Notes the lean shown today (one row per day), so it can be checked against her entries.
    static func noteLean(_ dir: MoodLean.Direction?, context: ModelContext) {
        guard let dir else { return }
        let key = today(context).key
        let rows = (try? context.fetch(FetchDescriptor<GuessFeedback>(predicate: #Predicate { $0.kind == "lean" && $0.dayKey == key }))) ?? []
        let row = rows.first ?? { let r = GuessFeedback(kind: "lean", day: today(context)); context.insert(r); return r }()
        row.guess = "\(dir)"
        try? context.save()
    }

    static func answerLean(_ fit: Bool, context: ModelContext) {
        let key = today(context).key
        let rows = (try? context.fetch(FetchDescriptor<GuessFeedback>(predicate: #Predicate { $0.kind == "lean" && $0.dayKey == key }))) ?? []
        let row = rows.first ?? { let r = GuessFeedback(kind: "lean", day: today(context)); context.insert(r); return r }()
        row.fit = fit
        row.updatedAt = .now
        try? context.save()
    }

    static func noteWords(kind: String, shown: [String], picked: String?, context: ModelContext) {
        let r = GuessFeedback(kind: kind, day: today(context))
        r.shown = shown
        r.picked = picked
        r.fit = picked != nil
        context.insert(r)
        try? context.save()
    }

    static func leanSummary(_ rows: [GuessFeedback], entries: [Entry], dayStart: Int) -> LeanRecord.Summary {
        var leans: [AnchoredDay: MoodLean.Direction] = [:]
        var answers: [AnchoredDay: Bool] = [:]
        for r in rows where r.kind == "lean" {
            guard let d = AnchoredDay(key: r.dayKey) else { continue }
            switch r.guess {
            case "morePleasant": leans[d] = .morePleasant
            case "lessPleasant": leans[d] = .lessPleasant
            case "usual": leans[d] = .usual
            default: break
            }
            if let f = r.fit { answers[d] = f }
        }
        var sums: [AnchoredDay: (Double, Int)] = [:]
        // Her own mood points only: a model guess cannot check the model's lean.
        for e in entries where e.status != .released && !e.moodGuessed {
            guard let v = e.valence else { continue }
            let d = DayAnchor.day(for: e.createdAt, timeZone: e.timeZone, dayStartHour: dayStart)
            sums[d] = ((sums[d]?.0 ?? 0) + v, (sums[d]?.1 ?? 0) + 1)
        }
        let mood = sums.mapValues { $0.0 / Double($0.1) }
        let usual = mood.isEmpty ? 0 : Baselines.median(Array(mood.values))
        return LeanRecord.summarize(leans: leans, answers: answers, mood: mood, usual: usual)
    }

    static func wordCounts(_ rows: [GuessFeedback]) -> (picks: [String: Int], shown: [String: Int]) {
        var picks: [String: Int] = [:], shown: [String: Int] = [:]
        for r in rows where r.kind == "words" {
            for w in r.shown { shown[w, default: 0] += 1 }
            if let p = r.picked { picks[p, default: 0] += 1 }
        }
        return (picks, shown)
    }
}

/// "Fits / Not really" under the lean, once a day, and the lean's record.
struct LeanFeedbackRow: View {
    let summary: LeanRecord.Summary
    let answeredToday: Bool
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if answeredToday {
                Text("Thank you. Noted for today.").font(.footnote).foregroundStyle(Palette.muted)
            } else {
                HStack(spacing: 8) {
                    Text("Does this fit?").font(.footnote).foregroundStyle(Palette.muted)
                    Spacer()
                    small("Fits") { answer(true) }
                    small("Not really") { answer(false) }
                }
            }
            if let t = LeanRecord.text(summary) {
                Text(t).font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }

    private func small(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.onTint)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Palette.tint1, in: Capsule())
            .frame(minHeight: 44)
    }
}

/// Once a week (Sundays), a small card asking how the app is working. No notification;
/// "Not this week" dismisses it. Notes stay on the phone until she exports them.
struct AppFeedbackCard: View {
    @Environment(\.modelContext) private var context
    @State private var mood: String?
    @State private var text = ""
    @State private var sent = false

    static var weekKey: String {
        let c = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return "appFeedback.dismissed.\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)"
    }

    /// Sundays, unless she already answered in the last 6 days or dismissed it this week.
    static func isDue(_ context: ModelContext, enabled: Bool) -> Bool {
        guard enabled, Calendar.current.component(.weekday, from: .now) == 1,
              !UserDefaults.standard.bool(forKey: weekKey) else { return false }
        let since = Date().addingTimeInterval(-6 * 86400)
        let recent = (try? context.fetchCount(FetchDescriptor<AppFeedback>(predicate: #Predicate { $0.createdAt > since }))) ?? 0
        return recent == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sent {
                Text("Thank you. It is saved on your phone; you can send it from Export.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                Text("How is AiHeart working for you?").font(.headline).foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(["Good", "Mixed", "Not great"], id: \.self) { m in
                        Chip(title: m, selected: mood == m) { mood = mood == m ? nil : m }
                    }
                }
                TextField("What is working, what is not, what is missing?", text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                HStack {
                    Button("Not this week") { UserDefaults.standard.set(true, forKey: Self.weekKey); sent = true }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted).frame(minHeight: 44)
                    Spacer()
                    Button("Save") {
                        context.insert(AppFeedback(text: text.trimmingCharacters(in: .whitespacesAndNewlines), mood: mood))
                        try? context.save()
                        sent = true
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                    .disabled(mood == nil && text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// "AiHeart noticed": proposals for About me, only when she asks. Written by the model
/// when it is on the phone, from plain findings otherwise. Each one: Add or Dismiss.
struct AboutMeProposalsCard: View {
    @Binding var doc: AboutMeDoc
    @Environment(\.modelContext) private var context
    @Query private var summaries: [DaySummary]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Entry.createdAt) private var entries: [Entry]
    @Query private var workouts: [Workout]
    @Query private var quiet: [QuietTopic]
    @State private var proposals: [AboutMeProposals.Proposal] = []
    @State private var looking = false
    @State private var looked = false
    @State private var byModel = false

    static let handledKey = "aboutme.proposals.handled"
    var handled: Set<String> { Set(UserDefaults.standard.stringArray(forKey: Self.handledKey) ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AiHeart noticed").font(.headline).foregroundStyle(Palette.ink)
            Text("Lines you might add. Nothing is added unless you add it.")
                .font(.footnote).foregroundStyle(Palette.muted)
            ForEach(proposals) { p in
                VStack(alignment: .leading, spacing: 8) {
                    Text(p.text).font(.journal(.body)).foregroundStyle(Palette.ink)
                    HStack(spacing: 16) {
                        Button("Add") {
                            doc = AboutMeProposals.add(p, to: doc)
                            mark(p)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                        Button("Dismiss") { mark(p) }
                            .font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 4)
            }
            if looked && proposals.isEmpty {
                Text("Nothing new right now.").font(.subheadline).foregroundStyle(Palette.muted)
            }
            Button {
                Task { await look() }
            } label: {
                HStack(spacing: 8) {
                    if looking { ProgressView() }
                    Text(looking ? "Looking…" : "Look for new things")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            }
            .disabled(looking)
            if looked && !proposals.isEmpty {
                Text(byModel ? "Written by the language model on your phone, then checked." : "From your findings. With the language model downloaded, these are written from your entries too.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        #if DEBUG
        .task { if ProcessInfo.processInfo.arguments.contains("-lookProposals") { await look() } }
        #endif
    }

    private func mark(_ p: AboutMeProposals.Proposal) {
        var h = handled
        h.insert(p.id)
        UserDefaults.standard.set(Array(h), forKey: Self.handledKey)
        proposals.removeAll { $0.id == p.id }
    }

    private func look() async {
        looking = true
        defer { looking = false; looked = true }
        let s = settingsRows.first
        let dayStart = s?.dayStartHour ?? 4
        let snap = BodySnapshot.cached(summaries, settings: s)
        let input = PatternInputBuilder.make(snap: snap, entries: entries, workouts: workouts, dayStart: dayStart)
        let quietTerms = quiet.map(\.term)
        let kept = entries.filter { $0.status == .kept }
        let keptLines = entries.flatMap(\.keptLines)
        let words = WordTasks.vocabulary(from: kept.compactMap(\.word)).map { w in (w, kept.filter { $0.word == w }.count) }
        let findings = await Task.detached(priority: .utility) {
            AboutMeProposals.make(links: Patterns.links(input), lift: Patterns.liftGroups(input), phases: Patterns.phaseGroups(input),
                                  keptLines: keptLines, words: words)
        }.value
        let done = handled
        let existing = doc.markdown

        // The model first (cloud when she turned it on; entries that mention hurting yourself are left out).
        let llm = LLMService.shared
        if llm.isDownloaded, llm.state != .ready { await llm.prepare() }
        let model = llm.model(for: .aboutMe)
        let entryLines = AboutMeWriter.entryLines(kept.map { (word: $0.word, text: $0.text) }, quietTopics: quietTerms)
        if !(model is RuleBasedModel), !entryLines.isEmpty {
            let prompt = AboutMeWriter.prompt(findings: findings.map(\.text), entries: entryLines, existing: existing)
            let policy = OutputPolicy(input: prompt, userText: entryLines.joined(separator: " "), quietTopics: quietTerms, maxCharacters: 200)
            for attempt in 0..<2 {
                let req = GenerationRequest(system: AboutMeWriter.system, prompt: prompt, maxTokens: 120, temperature: 0.4 + 0.2 * Float(attempt),
                                        ownText: entryLines.joined(separator: "\n"))
                guard let raw = try? await model.generate(req) else { continue }
                let lines = AboutMeWriter.lines(from: raw, policy: policy, existing: existing)
                let fresh = lines.map { AboutMeProposals.Proposal(id: "llm:" + AboutMeProposals.stableHash($0.lowercased()), text: $0) }
                    .filter { !done.contains($0.id) }
                if !fresh.isEmpty { proposals = fresh; byModel = true; return }
            }
        }
        byModel = false
        proposals = findings.filter { !done.contains($0.id) && !existing.contains($0.text) }.prefix(4).map { $0 }
    }
}

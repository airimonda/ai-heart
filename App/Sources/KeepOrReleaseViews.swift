import AiHeartCore
import SwiftData
import SwiftUI
import UIKit

/// Runs the decision after a save (M9). Rules first; the model (cloud when she turned it on, behind the
/// self-harm gate, else on the phone) may veto a let-go and adds a second self-harm check. Default is keep.
/// If the model cannot run (unreachable, not loaded), the answer is "unsure": nothing is let go on rules
/// alone (owner, 2026-11-05).
@MainActor
enum AutoDecide {
    enum Outcome { case kept, letGo(Int), offerLetGo([String]), safety, heavy }

    static func run(_ entry: Entry, context: ModelContext) async -> Outcome {
        let s = AiHeartStore.settings(in: context)
        guard s.decideAuto, !s.pauseEverything else {
            NSLog("AiHeartDecide skipped: decideAuto=%d paused=%d", s.decideAuto ? 1 : 0, s.pauseEverything ? 1 : 0)
            return .kept
        }
        // Rules first; the model may only make the decision safer (docs/17).
        let llm = LLMService.shared
        let ready = llm.canAnswer(.decide)
        let model = llm.model(for: .decide)
        let rules = KeepOrRelease.decide(text: entry.text, word: entry.word, valence: entry.valence)
        NSLog("AiHeartDecide rules=%@ shameWords=%d model=%@", "\(rules)".prefix(20).description,
              KeepOrRelease.shameHits(entry.text ?? ""), ready ? model.name : "none")
        let decision = await ModelChecks.decideChecked(text: entry.text, word: entry.word, valence: entry.valence) { prompt in
            guard ready else { return .unavailable }
            let answer = await ask(model, prompt, ownText: entry.text ?? "")
            // The question kind and the answer only; never the text.
            let kind = prompt.hasPrefix("Does this text mention self-harm") ? "selfHarm"
                : prompt.hasPrefix("Does the writer sound hopeless") ? "hopeless"
                : prompt.hasPrefix("Is this text mainly about something the writer feels embarrassed") ? "shame" : "other"
            NSLog("AiHeartDecide %@ -> %@", kind, "\(answer)")
            return answer
        }
        NSLog("AiHeartDecide final=%@", "\(decision)".prefix(20).description)
        switch decision {
        case .keep:
            return .kept
        case .safetyKeep:
            return .safety
        case .heavyKeep:
            return .heavy
        case .letGo(let lines, _):
            // She is asked first and lets go by holding (docs/19). Off: today's automatic let-go.
            if s.releaseAsks { return .offerLetGo(lines) }
            return await perform(entry, keptLines: lines, by: .auto, context: context)
        }
    }

    /// The let-go itself, for the automatic path and for when she holds to let go.
    /// Returns .letGo(n), .safety (never released) or .kept.
    static func perform(_ entry: Entry, keptLines lines: [String], by: DecidedBy, context: ModelContext) async -> Outcome {
        let s = AiHeartStore.settings(in: context)
        entry.keepNumbers = s.keepNumbers
        // Gone at once: the notes must be written before the text is purged.
        if s.restDays == 0 { entry.releaseNote = await ReleaseNoteWriter.make(for: entry, keptLines: lines, context: context) }
        do {
            try EntryLifecycle.letGo(entry, restDays: s.restDays, keptLines: lines, by: by)
        } catch {
            return error as? LifecycleError == .safetyKeep ? .safety : .kept
        }
        try? context.save()
        if s.restDays == 0 { try? EntryLifecycle.runPurgeJob(in: context) }
        else { ReleaseNoteWriter.writeLater(entry, context: context) }
        return .letGo(lines.count)
    }

    /// Yes/no from the model; .unclear when the answer is neither, .unavailable when it could not be asked.
    /// `ownText` is her own text in the question, for the self-harm gate before a cloud call.
    static func ask(_ model: any AiHeartCore.LanguageModel, _ prompt: String, ownText: String) async -> ModelChecks.Answer {
        guard !(model is RuleBasedModel),
              let out = try? await model.generate(GenerationRequest(system: "Answer with one word: yes or no.", prompt: prompt,
                                                                    maxTokens: 3, temperature: 0, ownText: ownText)) else { return .unavailable }
        let l = out.lowercased()
        if l.hasPrefix("yes") { return .yes }
        if l.hasPrefix("no") { return .no }
        return .unclear
    }
}

/// Notes kept from a let-go entry (docs/16). Rules always; the model (cloud when she turned it on, with
/// text that mentions hurting yourself kept on the phone) with every part checked against her words. Written while the entry rests, so the text
/// is still there to read.
@MainActor
enum ReleaseNoteWriter {
    static func make(for entry: Entry, keptLines: [String], context: ModelContext) async -> ReleaseNote? {
        guard let text = entry.text else { return nil }
        return await make(text: text, keptLines: keptLines, sensations: entry.sensations, letGo: entry.status != .kept, context: context)
    }

    /// From plain text, e.g. a Listen session before it is saved.
    static func make(text: String, keptLines: [String], sensations: [String] = [], letGo: Bool = false, context: ModelContext) async -> ReleaseNote? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let quiet = WordFinder.quietTopics(context)
        let rules = ReleaseNotes.fallback(text: text, keptLines: keptLines, sensations: sensations, quietTopics: quiet)
        let llm = LLMService.shared
        if llm.isDownloaded, llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.notes) else {
            NSLog("AiHeartLLM notes: rules only (state=%@)", "\(llm.state)")
            return rules.isEmpty ? nil : rules
        }
        let model = llm.model(for: .notes)
        // Version 2 (docs/16): label her sentences, then one short question per call.
        let sentences = ReleaseNotes.noteSentences(text)
        guard !sentences.isEmpty else { return rules.isEmpty ? nil : rules }
        func ask(_ prompt: String, _ tokens: Int, yesNo: Bool = false, system: String? = nil) async -> String {
            let req = GenerationRequest(system: system ?? (yesNo ? ReleaseNotes.systemYesNo : ReleaseNotes.systemV2), prompt: prompt,
                                        maxTokens: tokens, temperature: 0, ownText: text)
            return (try? await model.generate(req)) ?? ""
        }
        var labels: [Int: NotePart] = [:]
        for chunk in ReleaseNotes.chunks(sentences.count) {
            let raw = await ask(ReleaseNotes.labelPrompt(sentences, chunk: chunk), 16 * chunk.count + 20)
            labels.merge(ReleaseNotes.parseLabels(raw, chunk: chunk)) { $1 }
        }
        let summary = await ask(ReleaseNotes.summaryPrompt(sentences), 40)
        let feelings = ReleaseNotes.parseFeelings(await ask(ReleaseNotes.feelingsPrompt(sentences), 30))
        let strength = ReleaseNotes.parseStrength(await ask(ReleaseNotes.strengthPrompt(sentences), 15), count: sentences.count)
        // Needs: the model picks one and the sentence that shows it, then a strict yes/no check of
        // that pair. A pick that fails the check is dropped: no need beats a wrong one.
        var needs: [NeedNote] = []
        for met in [false, true] {
            guard let (need, i) = ReleaseNotes.parseNeedPick(await ask(ReleaseNotes.needPickPrompt(sentences, met: met), 15), count: sentences.count),
                  !needs.contains(where: { $0.need == need }) else { continue }
            let verdict = await ask(ReleaseNotes.needVerifyPrompt(sentence: sentences[i], text: text, need: need, met: met), 3, yesNo: true)
            if verdict.lowercased().hasPrefix("yes") { needs.append(NeedNote(need: need, met: met, quote: sentences[i])) }
        }
        var note = ReleaseNotes.assemble(sentences: sentences, labels: labels, summary: summary, feelings: feelings,
                                         strength: strength, needs: needs, text: text, quietTopics: quiet)
        // Version 3 (owner, 2026-11-05): summaries per part, and only a line or two of her own words.
        if let prompt = ReleaseNotes.partSummaryPrompt(note) {
            let raw = await ask(prompt, 40 * NotePart.shown.count)
            note.partSummaries = ReleaseNotes.parsePartSummaries(raw, note: note, text: text, quietTopics: quiet)
            note.keyLines = ReleaseNotes.parseKeyLines(await ask(ReleaseNotes.keyLinesPrompt(sentences), 12), sentences: sentences, quietTopics: quiet)
            note.version = 3
        }
        NSLog("AiHeartLLM notes v3: labels=%d summaries=%d keyLines=%d needs=%d feelings=%d", labels.count,
              note.partSummaries?.count ?? 0, note.keyLines?.count ?? 0, needs.count, feelings.count)
        // Honest affirmations (owner, 2026-11-05): one more call, checked line by line. Not for heavy, hopeless or
        // self-harm entries; the fixed templates show when nothing is stored.
        if !labels.isEmpty, HonestAffirmations.mayWrite(for: text) {
            let raw = await ask(HonestAffirmations.prompt(sentences: sentences, labels: labels, note: note, noQuotes: letGo), 220, system: HonestAffirmations.system)
            let written = HonestAffirmations.parseWritten(raw, sentences: sentences, text: text, quietTopics: quiet)
            note.affirmations = written.isEmpty ? nil : written
            NSLog("AiHeartLLM affirmations: model=%@ rawLines=%d kept=%d letGo=%d", model.name,
                  raw.split(whereSeparator: \.isNewline).count, written.count, letGo ? 1 : 0)
        }
        // Labels are the core; without them fall back to the rule notes.
        return labels.isEmpty ? (rules.isEmpty ? nil : rules) : note
    }

    /// Entries whose notes are being written now, so screens can say so.
    static var pending = NotesPending.shared

    /// Notes for a kept entry (owner, 2026-11-04): written in the background right after saving,
    /// shown on the saved sheet, the heavy sheet and the entry.
    static func writeForKept(_ entry: Entry, context: ModelContext, again: Bool = false) {
        guard again || entry.releaseNote == nil, ReleaseNotes.worthWriting(entry.text), !pending.ids.contains(entry.syncId) else { return }
        let id = entry.syncId
        pending.ids.insert(id)
        Task { @MainActor in
            defer { pending.ids.remove(id) }
            let note = await make(for: entry, keptLines: KeepOrRelease.keptLines(entry.text ?? ""), context: context)
            guard entry.status != .released, entry.modelContext != nil, var note else { return }
            note.talkNotes = entry.releaseNote?.talkNotes  // notes about a talk survive a rewrite
            entry.releaseNote = note
            entry.updatedAt = .now
            try? context.save()
        }
    }

    /// Writes notes onto a resting entry in the background. Skipped if she brought it back meanwhile.
    static func writeLater(_ entry: Entry, context: ModelContext) {
        Task { @MainActor in
            let note = await make(for: entry, keptLines: entry.keptLines, context: context)
            guard entry.status == .resting, let note else { return }
            entry.releaseNote = note
            entry.updatedAt = .now
            try? context.save()
        }
    }
}

@MainActor @Observable
final class NotesPending {
    static let shared = NotesPending()
    var ids: Set<UUID> = []
}

/// The notes for an entry as they arrive: a quiet line while the model writes, then the card.
struct LiveNotes: View {
    let entry: Entry
    var pending = NotesPending.shared

    var body: some View {
        if let note = entry.releaseNote, !pending.ids.contains(entry.syncId) {
            ReleaseNoteCard(note: note, moodPoint: entry.moodGuessed ? nil : ReleaseNotes.moodPointLine(valence: entry.valence, arousal: entry.arousal))
                .id(entry.releaseNoteJSON)
            if entry.status == .kept || entry.status == .resting, entry.text?.isEmpty == false {
                // Notes can be off; she can ask for them again (older ones were written a cruder way).
                Button { ReleaseNoteWriter.writeForKept(entry, context: context, again: true) } label: {
                    Label("Write these notes again", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 44)
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint)
            }
        } else if pending.ids.contains(entry.syncId) {
            HStack(spacing: 8) {
                ProgressView()
                Text("Writing notes on how you reacted and what you needed…").font(.footnote).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        } else if entry.status == .kept, ReleaseNotes.worthWriting(entry.text) {
            // Older entries, saved before notes were written for kept ones: only when she asks.
            Button { ReleaseNoteWriter.writeForKept(entry, context: context) } label: {
                Label("Write notes on this moment", systemImage: "note.text").frame(maxWidth: .infinity, minHeight: 44)
            }
            .font(.headline).foregroundStyle(Palette.onTint)
        }
    }
    @Environment(\.modelContext) private var context
}

/// The notes, laid out like a session note: situation, reaction in parts, how strong it read,
/// needs, what helped. Quotes are her words; feelings and needs come from fixed lists.
struct ReleaseNoteCard: View {
    let note: ReleaseNote
    var moodPoint: String? = nil
    @State private var showWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Notes on this moment").font(.headline).foregroundStyle(Palette.ink)
            if let t = note.talkNotes { row("About the talk", t, quote: false) }
            if let h = note.happened { row("What happened", h, quote: false) }
            if note.version >= 2 {
                if !note.feelings.isEmpty { row("You felt", note.feelings.map(\.rawValue).joined(separator: ", "), quote: false) }
                if note.version >= 3 {
                    // Summaries per part; her words only where the model's summary failed its check.
                    ForEach(NotePart.shown, id: \.self) { part in
                        if let line = note.partSummary(part) { row(part.title, line, quote: false) }
                        else if let first = note.sentences(part).first { row(part.title, first, quote: true) }
                    }
                    if let lines = note.keyLines, !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            label("In your words")
                            ForEach(lines, id: \.self) { text($0, quote: true) }
                        }
                    }
                } else { ForEach(NotePart.shown, id: \.self) { part in
                    let lines = note.sentences(part)
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            label(part.title)
                            ForEach(lines, id: \.self) { text($0, quote: true) }
                        }
                    }
                } }
            } else if note.thought != nil || !note.feelings.isEmpty || note.body != nil || note.urge != nil {
                VStack(alignment: .leading, spacing: 8) {
                    label("How you reacted")
                    if let t = note.thought { part("Thought", t, quote: true) }
                    if !note.feelings.isEmpty { part("Felt", note.feelings.map(\.rawValue).joined(separator: ", "), quote: false) }
                    if let b = note.body { part("Body", b, quote: true) }
                    if let u = note.urge { part("Did or wanted to", u, quote: true) }
                }
            }
            if let i = note.intensity {
                VStack(alignment: .leading, spacing: 4) {
                    label("How strong it read")
                    Text(i.title).foregroundStyle(Palette.ink)
                    if note.version < 3, let q = note.intensityQuote { Text("“\(q)”").font(.journal(.subheadline)).italic().foregroundStyle(Palette.muted) }
                    Text("AiHeart's read of your words, not a measure.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if let m = moodPoint { row("Your mood point", m, quote: false) }
            if !note.missingNeeds.isEmpty { needs("Needs that seemed missing", note.missingNeeds) }
            if !note.metNeeds.isEmpty { needs("Needs that were met", note.metNeeds) }
            if note.version < 2, !note.helped.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("What helped, in your words")
                    ForEach(note.helped, id: \.self) { Text($0).font(.journal(.body)).italic().foregroundStyle(Palette.ink) }
                }
            }
            if note.summaryOnly == true {
                Text("You let this one go, so only a summary is kept, not your words.")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            let honest = HonestAffirmations.shown(note)
            let _ = NSLog("AiHeartCard: v=%d summaryOnly=%d written=%d shown=%d", note.version, note.summaryOnly == true ? 1 : 0,
                          note.affirmations?.count ?? -1, honest.count)
            if !honest.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    label("Honest things to hold")
                    ForEach(honest, id: \.text) { a in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.text).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                            Text(a.basis).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.tint1, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            DisclosureGroup(isExpanded: $showWhy) {
                Text(Self.why).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            } label: {
                Text("How these notes are made").font(.caption.weight(.semibold)).foregroundStyle(Palette.onTint)
            }
            .tint(Palette.onTint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    static let why = """
    Laid out like a chain analysis, a tool from dialectical behaviour therapy: what set it off, what went through your mind, \
    what you did, what it gave you, what it cost, what you want. The model sorts your own sentences into those parts, \
    then sums up each part in one line, using only what you wrote. A line or two of your own words is kept when it says \
    something important clearly. \
    The "honest things to hold" are written by the language model from your own sentences, each resting on sentences \
    it names, and checked by fixed rules: no praise of who you are, no promises, no advice, nothing you did not write. \
    A line that fails is dropped, and then fixed lines are used instead. \
    Feelings come from a fixed list. A need is shown only if a second, strict check agrees with the sentence it points to; \
    needs come from self-determination theory and schema therapy. Notes can still be wrong. They describe; they do not \
    diagnose or advise. Written on your phone.
    """

    private func label(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted).textCase(.uppercase)
    }

    private func row(_ title: String, _ value: String, quote: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            text(value, quote: quote)
        }
    }

    private func part(_ title: String, _ value: String, quote: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(Palette.muted).frame(width: 92, alignment: .leading)
            text(value, quote: quote)
        }
    }

    @ViewBuilder private func text(_ value: String, quote: Bool) -> some View {
        if quote { Text("“\(value)”").font(.journal(.body)).italic().foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true) }
        else { Text(value).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true) }
    }

    private func needs(_ title: String, _ items: [NeedNote]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            ForEach(items, id: \.need) { n in
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.need.title).font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    if !n.quote.isEmpty, note.version < 3 {
                        Text("“\(n.quote)”").font(.journal(.subheadline)).italic().foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A typed entry that reads as hopeless or at the limit (docs/17): kept in full, never let go, and
/// the fixed heavy card points to people and Something to try. Fixed words only, never the model.
struct HeavyKeptSheet: View {
    var entry: Entry? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Kept. This one stays.").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("It will not be let go, so you and your therapist can look at it later if you want.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    ListenHeavyCard()
                    if let entry { LiveNotes(entry: entry) }
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Press and hold to let go (docs/19). About a second and a half; lifting the finger stops it.
/// VoiceOver gets a normal button named "Let it go", because holding is hard with it. With
/// Reduce Motion the ring fills in steps instead of sweeping.
struct HoldToLetGo: View {
    var seconds = 1.5
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var holding: Task<Void, Never>?
    @State private var done = false

    var body: some View {
        ZStack {
            Circle().fill(Palette.flameTint)
            Circle().stroke(Palette.line, lineWidth: 8).padding(4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Palette.action, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
            VStack(spacing: 6) {
                Image(systemName: "leaf").font(.title.weight(.semibold))
                Text(holding == nil ? "Hold to let go" : "Keep holding")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Palette.onFlameTint)
            .padding(24)
        }
        .frame(width: 176, height: 176)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 80, perform: {}, onPressingChanged: { pressing in
            if pressing { start() } else { stop() }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Let it go")
        .accessibilityHint("Lets this one go now")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { finish() }
    }

    private func start() {
        guard holding == nil, !done else { return }
        let t0 = Date()
        holding = Task { @MainActor in
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(t0) / seconds)
                progress = reduceMotion ? (p * 4).rounded(.down) / 4 : p
                if p >= 1 { finish(); return }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    private func stop() {
        holding?.cancel()
        holding = nil
        guard !done else { return }
        if reduceMotion { progress = 0 } else { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
    }

    private func finish() {
        guard !done else { return }
        done = true
        holding?.cancel()
        holding = nil
        progress = 1
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onComplete()
    }
}

/// "Let it go?" with the hold control and an equally plain "Keep it". Used after a hard entry
/// (Now), and for letting go by hand (entry, Listen).
struct LetGoAskSheet: View {
    var title = "Let this one go?"
    var restDays: Int
    var busy = false
    /// Owner, 2026-11-04: for an embarrassing entry, also "keep it without the embarrassing parts".
    var onScrub: (() -> Void)? = nil
    let onLetGo: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(.title2.bold()).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Text("AiHeart keeps short notes on how you reacted and what helped.")
                Text(restDays == 0 ? "The rest is gone at once." : "The rest rests for \(restDays) day\(restDays == 1 ? "" : "s") first. You can bring it back until then.")
            }
            .font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            if busy {
                ProgressView("Letting go…").frame(width: 176, height: 176)
            } else {
                HoldToLetGo(onComplete: onLetGo)
                Text("Press and hold. Lift your finger to stop.").font(.footnote).foregroundStyle(Palette.muted)
            }
            if let onScrub {
                Button("Keep it, without the embarrassing parts", action: onScrub)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            }
            Button(onScrub == nil ? "Keep it" : "Keep it all", action: onKeep)
                .buttonStyle(SecondaryCapsule())
                .disabled(busy)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
    }
}

/// The ask-first sheet on Now for a hard entry. Holding lets it go with the same steps as the
/// automatic path; "Keep it" (or swiping away) keeps it.
/// After an entry is saved anywhere (Now, Listen, Talk it through's summary): the same checks
/// (owner, 2026-11-04). Self-harm opens the safety plan, heavy shows the heavy card, embarrassing or
/// shameful gets the offer to let go or keep without the embarrassing parts. Then `onFinished`.
struct AfterSaveCheck: ViewModifier {
    @Binding var entry: Entry?
    let onFinished: () -> Void
    @Environment(\.modelContext) private var context
    @State private var offer: LetGoOffer?
    @State private var heavy = false
    @State private var safety = false

    func body(content: Content) -> some View {
        content
            .task(id: entry?.syncId) {
                guard let e = entry else { return }
                switch await AutoDecide.run(e, context: context) {
                case .offerLetGo(let lines): offer = LetGoOffer(entry: e, lines: lines)
                case .heavy: heavy = true
                case .safety: safety = true
                case .kept, .letGo: finish()
                }
            }
            .sheet(item: $offer, onDismiss: finish) { o in LetGoOfferSheet(offer: o) { _ in offer = nil } }
            .sheet(isPresented: $heavy, onDismiss: finish) { HeavyKeptSheet(entry: entry) }
            .sheet(isPresented: $safety, onDismiss: finish) { SafetyPageView(readOnly: true) }
    }

    private func finish() {
        if let e = entry, e.status == .kept { ReleaseNoteWriter.writeForKept(e, context: context) }
        entry = nil
        onFinished()
    }
}

extension View {
    func afterSaveCheck(_ entry: Binding<Entry?>, onFinished: @escaping () -> Void) -> some View {
        modifier(AfterSaveCheck(entry: entry, onFinished: onFinished))
    }
}

struct LetGoOffer: Identifiable {
    let entry: Entry
    let lines: [String]
    var id: UUID { entry.syncId }
}

struct LetGoOfferSheet: View {
    let offer: LetGoOffer
    let onDone: (AutoDecide.Outcome) -> Void
    @Environment(\.modelContext) private var context
    @State private var busy = false
    @State private var scrubbing = false

    var body: some View {
        LetGoAskSheet(title: "This one sounds embarrassing. What should happen to it?",
                      restDays: AiHeartStore.settings(in: context).restDays, busy: busy,
                      onScrub: { scrubbing = true },
                      onLetGo: {
                          busy = true
                          Task { onDone(await AutoDecide.perform(offer.entry, keptLines: offer.lines, by: .user, context: context)) }
                      },
                      onKeep: { onDone(.kept) })
        .interactiveDismissDisabled(busy)
        .sheet(isPresented: $scrubbing) {
            ScrubSheet(entry: offer.entry) { scrubbing = false; onDone(.kept) }
        }
    }
}

/// Review of the embarrassing parts (owner, 2026-11-05: the model points, she decides, nothing is written
/// for her). The model (plus her own shame words) pre-selects sentences to drop; she can change that, and
/// can type her own words in place of a dropped sentence. Nothing changes until she taps the done button.
struct ScrubReviewSheet: View {
    let text: String
    var doneTitle = "Keep this"
    let onDone: (String?) -> Void
    @State private var sentences: [String] = []
    @State private var dropped: Set<Int> = []
    @State private var own: [Int: String] = [:]
    @State private var looking = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tap a sentence to take it out. For any you take out, you can write your own words instead. Nothing is written for you.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    if looking {
                        HStack(spacing: 8) { ProgressView(); Text("Looking…").font(.footnote).foregroundStyle(Palette.muted) }
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else if dropped.isEmpty {
                        Text("Nothing was picked. Tap a sentence if you want to take it out.").foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(sentences.enumerated()), id: \.offset) { i, s in row(i, s) }
                }
                .padding(20)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("The embarrassing parts").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(doneTitle) { onDone(ShameScrub.kept(sentences, dropping: dropped, replacing: own)) }.disabled(looking)
                }
            }
            .keyboardHideButton()
            .task { await look() }
        }
    }

    @ViewBuilder private func row(_ i: Int, _ s: String) -> some View {
        let out = dropped.contains(i)
        let mine = (own[i] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if out { dropped.remove(i) } else { dropped.insert(i) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if out {
                        Text(s).font(.journal(.body)).strikethrough().foregroundStyle(Palette.muted)
                        Text(mine.isEmpty ? "Removed" : "Replaced with your words").font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        Text(s).font(.journal(.body)).foregroundStyle(Palette.ink)
                        Text("Kept as it is").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityValue(out ? (mine.isEmpty ? "Removed" : "Replaced with your words") : "Kept as it is")
            if out {
                TextField("Your own words instead (optional)", text: Binding(get: { own[i] ?? "" }, set: { own[i] = $0 }), axis: .vertical)
                    .font(.journal(.body))
                    .padding(10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(out ? Palette.segment : Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func look() async {
        sentences = text.components(separatedBy: .newlines).flatMap(KeepOrRelease.sentences)
        defer { looking = false }
        guard !sentences.isEmpty else { return }
        // Her shame words first, then the on-device model's pick (not on the cloud list, owner 2026-11-05).
        // The model only points; it never writes anything.
        dropped = ShameScrub.fallback(sentences)
        let llm = LLMService.shared
        if llm.state != .ready { await llm.prepare() }
        if llm.canAnswer(.other), let raw = try? await llm.model(for: .other).generate(
            GenerationRequest(system: ShameScrub.system, prompt: ShameScrub.prompt(sentences), maxTokens: 30, temperature: 0)) {
            dropped.formUnion(ShameScrub.parse(raw, count: sentences.count))
        }
        NSLog("AiHeartUI scrub: picked %d of %d", dropped.count, sentences.count)
    }
}

/// Plain text (a talk's words before they are remembered).
struct TextScrubSheet: View {
    let text: String
    let onDone: (String?) -> Void
    var body: some View { ScrubReviewSheet(text: text, doneTitle: "Remember this", onDone: onDone) }
}

/// An entry: the kept text replaces the old one; notes are written again.
struct ScrubSheet: View {
    let entry: Entry
    let onDone: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrubReviewSheet(text: entry.text ?? "", doneTitle: "Keep this") { kept in
            if let kept, kept != entry.text {
                entry.text = kept
                entry.keptLines = []
                entry.releaseNote = nil
                entry.updatedAt = .now
                try? context.save()
                NSLog("AiHeartUI scrub applied to an entry")
                ReleaseNoteWriter.writeForKept(entry, context: context, again: true)
            }
            onDone()
        }
    }
}

/// A "Let go" button made deliberate: the same hold control in a sheet. The action runs after
/// the sheet has closed, so it can open its own sheets.
struct LetGoConfirm: ViewModifier {
    @Binding var isPresented: Bool
    let onLetGo: () -> Void
    @Environment(\.modelContext) private var context
    @State private var pending = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            if pending { pending = false; onLetGo() }
        }) {
            LetGoAskSheet(restDays: max(AiHeartStore.settings(in: context).restDays, 1),
                          onLetGo: { pending = true; isPresented = false },
                          onKeep: { isPresented = false })
        }
    }
}

extension View {
    func letGoConfirm(isPresented: Binding<Bool>, onLetGo: @escaping () -> Void) -> some View {
        modifier(LetGoConfirm(isPresented: isPresented, onLetGo: onLetGo))
    }
}

/// Saved, let go (screen 22): a bottom sheet with Undo.
struct LetGoSheet: View {
    let entry: Entry
    let keptCount: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showEntry = false
    @State private var showBurning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "leaf")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.onFlameTint)
                    .frame(width: 52, height: 52)
                    .background(Palette.flameTint, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let go, gently").font(.title3.bold()).foregroundStyle(Palette.ink)
                    Text(subtitle).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 20) {
                Button("Let it go now") { showBurning = true }
                if entry.status == .resting { Button("See what was kept") { showEntry = true } }
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            Text("Optional. It rests and lets go either way.").font(.caption).foregroundStyle(Palette.muted)
            HStack {
                Button("Undo") {
                    if entry.status == .resting { try? EntryLifecycle.bringBack(entry); try? context.save() }
                    dismiss()
                }
                .font(.headline).foregroundStyle(Palette.onTint).frame(minWidth: 44, minHeight: 44)
                .disabled(entry.status != .resting)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).frame(width: 140)
            }
        }
        .padding(24)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
        .sheet(isPresented: $showEntry) { NavigationStack { RestingEntryView(entry: entry) } }
        .fullScreenCover(isPresented: $showBurning, onDismiss: { dismiss() }) { BurningView(entry: entry) }
    }

    private var subtitle: String {
        let lines = "Keeps a short summary of how you reacted, in its own words"
        let numbers = entry.keepNumbers ? ", and your numbers." : "."
        let rest = entry.status == .released ? " The rest, including your exact lines, is gone." : " Resting first."
        return lines + numbers + rest
    }
}

/// Resting entry (screen 13). Pink lines are kept; tap a line to change it.
struct RestingEntryView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kept: [String] = []
    @State private var confirmDelete = false
    @State private var writing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(header).font(.subheadline).foregroundStyle(Palette.muted)
                if let note = entry.releaseNote {
                    // Keyed on the stored JSON so the card redraws as soon as rewritten notes are saved.
                    ReleaseNoteCard(note: note, moodPoint: ReleaseNotes.moodPointLine(valence: entry.valence, arousal: entry.arousal))
                        .id(entry.releaseNoteJSON)
                    if entry.text?.isEmpty == false {
                        // While it rests the text is still here, so the notes can be written again (owner, 2026-11-05).
                        Button {
                            writing = true
                            Task {
                                let note = await ReleaseNoteWriter.make(for: entry, keptLines: entry.keptLines, context: context)
                                NSLog("AiHeartRewrite: status=%@ made=%d aff=%d", entry.statusRaw, note == nil ? 0 : 1, note?.affirmations?.count ?? -1)
                                if entry.status == .resting, let note { entry.releaseNote = note; entry.updatedAt = .now; try? context.save() }
                                NSLog("AiHeartRewrite: stored aff=%d", entry.releaseNote?.affirmations?.count ?? -1)
                                writing = false
                            }
                        } label: {
                            Label(writing ? "Writing notes…" : "Write these notes again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).disabled(writing)
                    }
                } else if entry.text?.isEmpty == false {
                    Button {
                        writing = true
                        Task {
                            let note = await ReleaseNoteWriter.make(for: entry, keptLines: entry.keptLines, context: context)
                            if entry.status == .resting, let note { entry.releaseNote = note; entry.updatedAt = .now; try? context.save() }
                            writing = false
                        }
                    } label: {
                        HStack { if writing { ProgressView() }; Text(writing ? "Writing notes…" : "Write notes on this moment") }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(writing)
                    .font(.headline).foregroundStyle(Palette.onTint)
                }
                Text("Your words").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted).textCase(.uppercase)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(KeepOrRelease.sentences(entry.text ?? "").enumerated()), id: \.offset) { _, line in
                        let isKept = kept.contains(line)
                        Button { toggle(line) } label: {
                            HStack(alignment: .top) {
                                Text(line).font(.journal(.body)).foregroundStyle(Palette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if isKept { Text("marked").font(.caption.weight(.semibold)).foregroundStyle(Palette.onTint) }
                            }
                            .padding(12)
                            .background(isKept ? Palette.tint1 : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isKept ? .isSelected : [])
                        .accessibilityHint(isKept ? "Tap to unmark this line" : "Tap to mark this line")
                    }
                }
                .padding(14)
                .card()
                Text("Tap a line to mark it or not. Marked lines help write the notes; they go with the rest. Your numbers stay in your charts either way.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Button("Bring it all back") {
                    try? EntryLifecycle.bringBack(entry)
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Delete this entry", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Resting entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { kept = entry.keptLines }
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                EntryActions.delete(entry, context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It goes to Recently deleted in your journal for 30 days.") }
    }

    private var header: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: entry.restUntil ?? .now).day ?? 0)
        return "The pink lines help write your notes. In \(days == 0 ? "less than a day" : days == 1 ? "1 day" : "\(days) days") everything goes except a short summary."
    }

    private func toggle(_ line: String) {
        if let i = kept.firstIndex(of: line) { kept.remove(at: i) } else { kept.append(line) }
        // Keep her order.
        let order = KeepOrRelease.sentences(entry.text ?? "")
        kept.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        entry.keptLines = kept
        entry.updatedAt = .now
        try? context.save()
    }
}

/// How it decides (screen 23).
struct DecidesView: View {
    @Bindable var s: AppSettings
    @Environment(\.modelContext) private var context
    @State private var confirmAtOnce = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(CloudSettings.isOn ? "Checks run on the cloud model you chose. Text that mentions hurting yourself never goes, and photos never do." : "On your phone. Nothing leaves it.").font(.subheadline).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    block("Kept in full", "Entries that feel good, neutral, or mixed. If it is unsure, it keeps.")
                    Divider().overlay(Palette.line)
                    block("Let go, keeping a summary", "Hard entries. It keeps a short summary, like a therapist's notes: the situation, your thought, feelings, body and what you did, how strong it read, which needs seemed missing or met, and what helped, in its own words, not yours. Plus your numbers. It lets go of the retelling and of your exact lines.")
                    Divider().overlay(Palette.line)
                    block("Never let go", "Anything about hurting yourself. Those stay, and your safety page opens.")
                    Divider().overlay(Palette.line)
                    block("Resting first", "Let-go entries are hidden for \(s.restDays == 0 ? "no time" : "\(s.restDays) days"). You can bring any back until then.")
                }
                .card()
                VStack(spacing: 0) {
                    RuleToggle(title: "Let AiHeart decide", subtitle: "Keep or let go, for you", isOn: $s.decideAuto)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Ask me first", subtitle: "Hold to let go. Letting go by your own hand is the part research tested.", isOn: $s.releaseAsks)
                    Divider().overlay(Palette.line).padding(.leading, 18)
                    RuleToggle(title: "Keep the numbers", subtitle: "Mood point and body map stay in your charts", isOn: $s.keepNumbers)
                }
                .card()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rest before it is gone").font(.headline).foregroundStyle(Palette.ink)
                    Picker("Rest", selection: Binding(get: { s.restDays }, set: { v in
                        if v == 0 { confirmAtOnce = true } else { s.restDays = v; save() }
                    })) {
                        Text("7 days").tag(7); Text("3 days").tag(3); Text("Gone at once").tag(0)
                    }
                    .pickerStyle(.segmented)
                    Text("It can misjudge, which is why resting exists. Gone at once cannot be undone.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                .padding(18)
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("How it decides")
        .onChange(of: s.decideAuto) { save() }
        .onChange(of: s.releaseAsks) { save() }
        .onChange(of: s.keepNumbers) { save() }
        .confirmationDialog("Gone at once?", isPresented: $confirmAtOnce, titleVisibility: .visible) {
            Button("Gone at once", role: .destructive) { s.restDays = 0; save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Let-go entries will be removed straight away, with no time to bring them back.")
        }
    }

    private func save() { s.updatedAt = .now; try? context.save() }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(Palette.ink)
            Text(text).font(.subheadline).foregroundStyle(Palette.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum EntryActions {
    /// Deletes an entry for good and leaves a tombstone, so a synced copy cannot return.
    /// Moves an entry to Recently deleted for 30 days (owner, 2026-11-04: "retrieve deleted entries at
    /// will"). It is gone from everywhere else; she can restore it or delete it for good (docs/22).
    static func delete(_ entry: Entry, context: ModelContext) {
        NSLog("AiHeartUI delete entry to Recently deleted (status %@)", entry.statusRaw)
        RecentlyDeleted.move(entry, in: context)
    }
}

/// Long-press on a journal card: delete with confirmation.
struct DeleteEntryMenu: ViewModifier {
    let entry: Entry
    var onOpen: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @State private var confirm = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let onOpen { Button("Open", systemImage: "arrow.up.right") { onOpen() } }
                Button("Delete", systemImage: "trash", role: .destructive) { NSLog("AiHeartUI delete: context menu"); confirm = true }
            }
            .alert("Delete this entry?", isPresented: $confirm) {
                Button("Delete", role: .destructive) { EntryActions.delete(entry, context: context) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It goes to Recently deleted in your journal for 30 days.")
            }
    }
}

/// A let-go entry: only the lines she kept remain. She can delete what is left.
struct LetGoEntryView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TintLabel(text: entry.keepNumbers ? "Let go · numbers kept" : "Let go", tint: Palette.flameTint, ink: Palette.onFlameTint)
                if let note = entry.releaseNote {
                    ReleaseNoteCard(note: note, moodPoint: entry.keepNumbers ? ReleaseNotes.moodPointLine(valence: entry.valence, arousal: entry.arousal) : nil)
                }
                if entry.keptLines.isEmpty, entry.releaseNote != nil {
                    EmptyView()
                } else if entry.keptLines.isEmpty {
                    Text("No summary was kept for this entry.").foregroundStyle(Palette.muted)
                } else {
                    KeptLines(lines: entry.keptLines).padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                }
                Text("The rest is gone. \(entry.keepNumbers ? "Its mood point stays in your charts." : "")")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Button("Delete what is left", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle(entry.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                dismiss()
                EntryActions.delete(entry, context: context)
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The notes, kept lines and its numbers go to Recently deleted in your journal for 30 days.") }
    }
}

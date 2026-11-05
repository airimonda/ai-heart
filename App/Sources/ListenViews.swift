import AiHeartCore
import AVFoundation
import SwiftData
import SwiftUI

/// Listen (M17, docs/13; designs Listen, ListenAfter, ListenReflect, ListenSettings).
/// A quiet place to talk or type. It mostly listens: no persona, no advice, no memory of
/// past sessions. Nothing is kept unless she chooses. Self-harm stops it and shows her
/// safety page.
struct ListenView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    @Query private var quiet: [QuietTopic]
    @State private var speech = SpeechListener()
    @State private var typing = false
    @State private var typed = ""
    @State private var showAfter = false
    @State private var showReflect = false
    @State private var showSort = false
    @State private var safety = false
    @State private var nudge: String?
    @State private var nudges = 0
    @State private var lastNudge: Date?
    @State private var saidLong = false
    @State private var started = Date()
    @State private var finished = false
    @State private var reviewing = false
    /// Her corrections to the transcript, if she made any.
    @State private var edited: String?
    @FocusState private var typeFocus: Bool

    private var settings: AppSettings? { settingsRows.first }
    private var transcript: String {
        [edited ?? speech.transcript, typed].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The entry just kept, while the after-save checks run.
    @State private var checking: Entry?

    var body: some View { bodyContent.keyboardHideButton().afterSaveCheck($checking) { dismissAll() } }

    @ViewBuilder private var bodyContent: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Listen").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Done") { end() }.font(.headline).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                }
                .padding(.horizontal, 24).padding(.top, 8)
                VStack(spacing: 6) {
                    Text(title).font(.title.bold()).foregroundStyle(Palette.ink)
                    Text(nudge ?? subtitle).font(.subheadline).foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center).animation(.easeInOut, value: nudge)
                }
                .padding(.top, 16).padding(.horizontal, 24)
                Spacer()
                if typing { typeBox } else { ListenLevel(speech: speech) }
                Spacer(minLength: 16)
                controls
                Text("An AI on your phone. Nothing is kept unless you choose.")
                    .font(.caption).foregroundStyle(Palette.muted).padding(.top, 10)
                Button("My safety page") { safety = true }
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 32)
            }
            .padding(.bottom, 8)
        }
        .task {
            started = .now
            if !typing { await speech.start() }
            if case .unavailable = speech.state { typing = true }
        }
        .task(id: "tick") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick()
            }
        }
        .onChange(of: transcript) { _, t in
            if ListenSafety.flags(t) { NSLog("AiHeartUI listen: safety stop"); speech.pause(); safety = true }
        }
        .sheet(isPresented: $reviewing) {
            ListenTranscriptReview(text: edited ?? speech.transcript, failed: speech.transcriptionFailed) { corrected in
                if let corrected { edited = corrected }
                reviewing = false
                showAfter = true
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showAfter) {
            ListenAfterSheet(transcript: transcript, flagged: ListenSafety.flags(transcript)) { action in
                showAfter = false
                handle(action)
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showReflect) {
            ListenReflectView(transcript: transcript, quiet: quiet.map(\.term), flagged: ListenSafety.flags(transcript)) { action in
                showReflect = false
                handle(action)
            }
        }
        .fullScreenCover(isPresented: $showSort) {
            ListenSortView(transcript: transcript, quiet: quiet.map(\.term), flagged: ListenSafety.flags(transcript)) { action in
                showSort = false
                handle(action)
            }
        }
        .fullScreenCover(isPresented: $safety) {
            ListenSafetyView(transcript: transcript) { kept in
                safety = false
                if kept { record("keep") ; dismissAll() }
            }
        }
        .onDisappear { if !finished { speech.discard() } }
    }

    private var title: String {
        if typing { return "Type it out" }
        if speech.transcribing { return "Writing it down" }
        switch speech.state {
        case .paused: return "Paused"
        case .unavailable: return "Type it out"
        default: return "Listening"
        }
    }

    private var subtitle: String {
        if case .unavailable(let why) = speech.state { return why }
        if speech.transcribing { return "Going through all of what you said, on this phone." }
        return "Say it all, as long as you need. The words come after you are done."
    }

    private var typeBox: some View {
        TextField("Write whatever you need.", text: $typed, axis: .vertical)
            .font(.journal(.title3))
            .lineLimit(5...12)
            .focused($typeFocus)
            .padding(18)
            .card()
            .padding(.horizontal, 24)
            .onAppear { typeFocus = true }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                if !typing, speech.state == .listening || speech.state == .paused {
                    Button(speech.state == .paused ? "Go on" : "Pause") {
                        if speech.state == .paused { speech.resume() } else { speech.pause() }
                    }
                    .buttonStyle(SecondaryCapsule())
                }
                Button(speech.transcribing ? "Writing it down\u{2026}" : "I am done") { done() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled((transcript.isEmpty && !speech.hasRecording) || speech.transcribing)
            }
            .padding(.horizontal, 24)
            if !typing {
                Button("Type instead") { speech.pause(); typing = true }
                    .font(.subheadline).underline().foregroundStyle(Palette.muted).frame(minHeight: 44)
            }
        }
    }

    // MARK: Flow

    private func tick() {
        guard !typing, speech.state == .listening, !safety else { return }
        let silence = Date().timeIntervalSince(speech.lastSpeech)
        let offers = settings?.listenOffers ?? .ask
        if ListenRules.shouldNudge(silence: silence, offers: offers, nudgesSoFar: nudges,
                                   secondsSinceLastNudge: lastNudge.map { Date().timeIntervalSince($0) }) {
            nudge = ListenRules.nudges[nudges % ListenRules.nudges.count]
            nudges += 1; lastNudge = .now
            speak(nudge!)
        }
        if ListenRules.shouldSayLong(elapsed: Date().timeIntervalSince(started), enabled: settings?.listenLongNote ?? false, alreadySaid: saidLong) {
            saidLong = true
            nudge = ListenRules.longSessionLine
        }
    }

    /// Transcribe the whole recording first (owner, 2026-11-02), then offer what to do with it.
    private func done() {
        speech.pause()
        typeFocus = false
        Task {
            let recorded = speech.hasRecording
            await speech.finish()
            edited = nil
            guard !ListenSafety.flags(transcript) else { return }   // the safety page opens instead
            if recorded { reviewing = true } else { showAfter = true }
        }
    }

    enum Action { case reflect, sort, word(String), body([String], [String]), keep, letGo, nothing, more }

    private func handle(_ a: Action) {
        switch a {
        case .reflect: showReflect = true
        case .sort: showSort = true
        case .more:
            if typing { typeFocus = true } else { speech.resume() }
        case .word(let w): save(word: w, regions: [], sensations: [], offer: "word")
        case .body(let r, let s): save(word: nil, regions: r, sensations: s, offer: "body")
        case .keep: save(word: nil, regions: [], sensations: [], offer: "keep")
        case .letGo: letGo()
        case .nothing:
            record("nothing")
            speech.discard(); typed = ""
            dismissAll()
        }
    }

    private func save(word: String?, regions: [String], sensations: [String], offer: String) {
        let d = CaptureDraft()
        d.text = transcript
        attachRecording(d)
        d.word = word
        d.regions = regions
        d.sensations = sensations
        let entry = d.save(in: context)
        record(offer)
        // Same checks as the journal (owner, 2026-11-04): then Listen closes.
        checking = entry
    }

    private func letGo() {
        guard !ListenSafety.flags(transcript) else { save(word: nil, regions: [], sensations: [], offer: "keep"); return }
        let d = CaptureDraft()
        d.text = transcript
        attachRecording(d)
        let e = d.save(in: context)
        try? EntryLifecycle.letGo(e, restDays: max(settings?.restDays ?? 7, 1), keptLines: KeepOrRelease.keptLines(transcript))
        try? context.save()
        if e.status == .resting { ReleaseNoteWriter.writeLater(e, context: context) }
        record("letGo")
        dismissAll()
    }

    /// Her voice, kept with the entry (owner, 2026-11-02). Released with it if she lets it go.
    private func attachRecording(_ d: CaptureDraft) {
        if let (data, seconds) = speech.recording() {
            d.audio = data
            d.audioSeconds = seconds
        }
    }

    /// Length and the offer she chose. Never what she said.
    private func record(_ offer: String) {
        let s = ListenSession()
        s.seconds = Date().timeIntervalSince(started)
        s.offerRaw = offer
        s.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        context.insert(s)
        try? context.save()
    }

    private func dismissAll() {
        finished = true
        speech.discard(); typed = ""
        dismiss()
    }

    private func end() {
        if transcript.isEmpty && !speech.hasRecording { dismissAll() } else { done() }
    }

    private let synth = AVSpeechSynthesizer()
    private func speak(_ s: String) {
        guard settings?.listenSpeak == true else { return }
        synth.speak(AVSpeechUtterance(string: s))
    }
}

/// While she talks: how long, and a quiet level so she can see it is hearing her.
/// No words on screen (owner, 2026-11-02). Uses the app palette, so it reads in dark mode too.
struct ListenLevel: View {
    let speech: SpeechListener
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bars = 9

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let active = speech.state == .listening
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(0..<bars, id: \.self) { i in
                        // Middle bars move most; the edges stay low.
                        let shape = 1 - abs(Double(i) - Double(bars - 1) / 2) / Double(bars)
                        let l = reduceMotion ? 0.3 : Double(speech.level)
                        Capsule()
                            .fill(Palette.action.opacity(active ? 0.85 : 0.3))
                            .frame(width: 8, height: 10 + 70 * CGFloat(l * shape))
                    }
                }
                .frame(height: 84)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: speech.level)
                Text(formatDuration(speech.elapsed))
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(active ? "Recording, \(Int(speech.elapsed)) seconds" : "Paused, \(Int(speech.elapsed)) seconds")
        }
    }
}

/// "What you said": the full transcript after she is done. She can read it, fix words, or skip.
struct ListenTranscriptReview: View {
    let failed: Bool
    let onDone: (String?) -> Void
    @State private var text: String
    private let original: String

    init(text: String, failed: Bool, onDone: @escaping (String?) -> Void) {
        self.failed = failed
        self.onDone = onDone
        self.original = text
        _text = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if failed || original.isEmpty {
                    Text("It could not be turned into words on this phone. The recording is still here, and Keep saves it.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer()
                } else {
                    Text("Fix any word, or skip this.").font(.subheadline).foregroundStyle(Palette.muted)
                    TextEditor(text: $text)
                        .font(.journal(.body))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .card()
                        .accessibilityLabel("What you said")
                }
                Button("Continue") { onDone(text == original ? nil : text) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("What you said").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip") { onDone(nil) } } }
        }
    }
}

struct SecondaryCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().stroke(Palette.line))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "That is out." Offers, all optional. Doing nothing keeps nothing.
struct ListenAfterSheet: View {
    let transcript: String
    let flagged: Bool
    let onPick: (ListenView.Action) -> Void
    @State private var picking: Pick?
    @State private var reaching = false
    @State private var trying = false
    @State private var confirmLetGo = false
    @State private var talking = false
    enum Pick: String, Identifiable { case word, body; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("That is out.").font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("Only if you want to do something with it.").font(.subheadline).foregroundStyle(Palette.muted)
                if ListenSafety.feelsHeavy(transcript) { ListenHeavyCard() }
                VStack(spacing: 0) {
                    row("Something to try", "Breathing, grounding, body, thoughts, moving", "leaf") { trying = true }
                    Divider().padding(.leading, 16)
                    if !flagged {
                        row("Talk it through", "Questions to help you think it over", "text.bubble") { talking = true }
                        Divider().padding(.leading, 16)
                    }
                    row("Help me sort it", "What happened, how I reacted, what I needed", "square.stack.3d.up") { onPick(.sort) }
                    Divider().padding(.leading, 16)
                    row("Say it back to me", "A short reflection in your words", "ear") { onPick(.reflect) }
                    Divider().padding(.leading, 16)
                    row("Put a word on it", "Words that might fit", "text.alignleft") { picking = .word }
                    Divider().padding(.leading, 16)
                    row("Where do I feel it?", "Tap on the body", "figure.stand") { picking = .body }
                    Divider().padding(.leading, 16)
                    row("Keep it as an entry", "As you said it", "book.closed") { onPick(.keep) }
                    if !flagged {
                        Divider().padding(.leading, 16)
                        row("Let it go", "Keep notes and what helped", "flame") { confirmLetGo = true }
                    }
                    Divider().padding(.leading, 16)
                    row("Who I can reach", "My therapist, my people, crisis lines", "phone") { reaching = true }
                }
                .card()
                Button("Nothing. Just stop.") { onPick(.nothing) }
                    .font(.headline).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, minHeight: 48)
                Button("Let me say more") { onPick(.more) }
                    .font(.subheadline).foregroundStyle(Palette.onTint).frame(maxWidth: .infinity, minHeight: 40)
            }
            .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .sheet(isPresented: $reaching) { ListenReachSheet() }
            .letGoConfirm(isPresented: $confirmLetGo) { onPick(.letGo) }
            .sheet(isPresented: $trying) { HardMomentsView() }
            .sheet(isPresented: $talking) { TalkView(seed: transcript) }
            .sheet(item: $picking) { p in
                switch p {
                case .word: ListenWordPicker(transcript: transcript) { w in picking = nil; onPick(.word(w)) }
                case .body: ListenBodyPicker { r, s in picking = nil; onPick(.body(r, s)) }
                }
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Palette.onTint).frame(width: 40, height: 40).background(Palette.tint1, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(sub).font(.footnote).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16).frame(minHeight: 60).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "What I heard": her words, shortened. Model when it passes the checks, else extractive.
struct ListenReflectView: View {
    @Environment(\.modelContext) private var context
    let transcript: String
    let quiet: [String]
    let flagged: Bool
    let onPick: (ListenView.Action) -> Void
    @State private var reflection: String?
    @State private var fits: Bool?
    @State private var picking: ListenAfterSheet.Pick?
    @State private var confirmLetGo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From what you said").font(.subheadline).foregroundStyle(Palette.muted)
                        Text("What I heard").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if let reflection {
                            Text(reflection).font(.journal(.title3).italic()).foregroundStyle(Palette.ink)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        Text("Only what you said, shortened. I may have it wrong.").font(.footnote).foregroundStyle(Palette.muted)
                        FlowLayout(spacing: 8) {
                            Chip(title: "Yes, that fits", selected: fits == true) { fits = true }
                            Chip(title: "Not quite", selected: fits == false) { fits = false }
                            Chip(title: "Let me say more") { onPick(.more) }
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
                    VStack(spacing: 0) {
                        Button { picking = .word } label: { optRow("Put a word on it", "Words that might fit", "text.alignleft") }.buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                        Button { picking = .body } label: { optRow("Where do I feel it?", "Tap on the body", "figure.stand") }.buttonStyle(.plain)
                    }
                    .card()
                    HStack(spacing: 10) {
                        Button("Keep as entry") { onPick(.keep) }.buttonStyle(SecondaryCapsule())
                        if !flagged { Button("Let it go") { confirmLetGo = true }.buttonStyle(PrimaryButtonStyle()) }
                    }
                    Text("If you do nothing, nothing is kept.").font(.footnote).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onPick(.nothing) } } }
            .letGoConfirm(isPresented: $confirmLetGo) { onPick(.letGo) }
            .sheet(item: $picking) { p in
                switch p {
                case .word: ListenWordPicker(transcript: transcript) { w in picking = nil; onPick(.word(w)) }
                case .body: ListenBodyPicker { r, s in picking = nil; onPick(.body(r, s)) }
                }
            }
            .task { reflection = await makeReflection() }
        }
    }

    private func optRow(_ title: String, _ sub: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.onTint).frame(width: 40, height: 40).background(Palette.tint1, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(sub).font(.footnote).foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 16).frame(minHeight: 60).contentShape(Rectangle())
    }

    private func makeReflection() async -> String {
        let extracted = ListenRules.fallbackReflection(transcript, quietTopics: quiet)
        let fallback = extracted.isEmpty ? "I heard you. I may not have it right in words." : extracted
        let llm = LLMService.shared
        guard llm.isDownloaded else { return fallback }
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.listen) else { return fallback }
        let model = llm.model(for: .listen)
        for _ in 0..<3 {
            let req = GenerationRequest(system: ListenRules.system + SeedImport.promptContext(context, full: false), prompt: ListenRules.reflectionPrompt(transcript: transcript), maxTokens: 90, temperature: 0.3, ownText: transcript)
            guard let raw = try? await model.generate(req) else { continue }
            let out = ListenRules.cleanedReflection(raw)
            if ListenRules.rejection(out, transcript: transcript, quietTopics: quiet) == nil,
               ListenRules.echoesHer(out, transcript: transcript) { return out }
        }
        NSLog("AiHeartLLM listen: reflection fell back")
        return fallback
    }
}

/// "Help me sort it": her words sorted, so she can look at it clearly. If she has not said what she
/// knows yet, it asks once, with a fixed line. It never suggests what to do.
struct ListenSortView: View {
    let transcript: String
    let quiet: [String]
    let flagged: Bool
    let onPick: (ListenView.Action) -> Void
    @State private var sorted: ListenSorted?
    @State private var note: ReleaseNote?
    @State private var notesLoading = false
    @State private var confirmLetGo = false
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Laid out").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    if ListenSafety.feelsHeavy(transcript) { ListenHeavyCard() }
                    if let sorted {
                        section("What happened", sorted.happened)
                        section("What I feel", sorted.felt)
                        if sorted.know.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("What do you already know about this?").font(.journal(.title3)).foregroundStyle(Palette.ink)
                                Button("Let me say it") { onPick(.more) }.buttonStyle(SecondaryCapsule())
                            }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
                        } else {
                            section("What I already know", sorted.know)
                        }
                        Text("Only your words, sorted. It may be off.").font(.footnote).foregroundStyle(Palette.muted)
                        if let note {
                            ReleaseNoteCard(note: note)
                        } else if notesLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Writing notes on how you reacted and what you needed…").font(.footnote).foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                    Button("Let me say more") { onPick(.more) }
                        .font(.subheadline).foregroundStyle(Palette.onTint).frame(maxWidth: .infinity, minHeight: 44)
                    HStack(spacing: 10) {
                        Button("Keep as entry") { onPick(.keep) }.buttonStyle(SecondaryCapsule())
                        if !flagged { Button("Let it go") { confirmLetGo = true }.buttonStyle(PrimaryButtonStyle()) }
                    }
                    Text("If you do nothing, nothing is kept.").font(.footnote).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onPick(.nothing) } } }
            .letGoConfirm(isPresented: $confirmLetGo) { onPick(.letGo) }
            .task {
                sorted = await makeSorted()
                notesLoading = true
                note = await ReleaseNoteWriter.make(text: transcript, keptLines: KeepOrRelease.keptLines(transcript), context: context)
                notesLoading = false
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.muted)
                ForEach(lines, id: \.self) { Text($0).font(.journal(.body)).foregroundStyle(Palette.ink) }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }

    private func makeSorted() async -> ListenSorted {
        let fallback = ListenSort.fallback(transcript, quietTopics: quiet)
        let llm = LLMService.shared
        guard llm.isDownloaded else { return fallback }
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.listen) else { return fallback }
        let model = llm.model(for: .listen)
        for _ in 0..<2 {
            let req = GenerationRequest(system: ListenSort.system, prompt: ListenSort.prompt(transcript: transcript), maxTokens: 160, temperature: 0.2, ownText: transcript)
            guard let raw = try? await model.generate(req) else { continue }
            if let s = ListenSort.parse(raw, transcript: transcript, quietTopics: quiet) { return s }
        }
        NSLog("AiHeartLLM listen: sort fell back")
        return fallback
    }
}

/// Fixed card when what she said reads as heavy. Points to people. It does not respond to a crisis.
struct ListenHeavyCard: View {
    @State private var reaching = false
    @State private var trying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This looks heavy.").font(.headline).foregroundStyle(Palette.ink)
            Text("It may be one for your therapist, or someone on a crisis line. They can do what this can\u{2019}t.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            HStack(spacing: 16) {
                Button("See who I can reach") { reaching = true }
                Button("Something to try") { trying = true }
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        .sheet(isPresented: $reaching) { ListenReachSheet() }
        .sheet(isPresented: $trying) { HardMomentsView() }
    }
}

/// Her safety plan as she wrote it (her therapist and people), then the crisis lines.
struct ListenReachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SafetyPlanReadBody(settings: settingsRows.first,
                                       emptyNote: "Your therapist\u{2019}s number can go on your safety plan, in My rules.")
                    CrisisLines()
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Who I can reach").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Words that might fit what she said; one tap keeps the entry with that word.
struct ListenWordPicker: View {
    let transcript: String
    let onPick: (String) -> Void
    @Environment(\.modelContext) private var context
    @State private var words: [String] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Words that might fit. Tap one to keep this with it.").font(.subheadline).foregroundStyle(Palette.muted)
                if words.isEmpty { ProgressView() }
                FlowLayout(spacing: 8) { ForEach(words, id: \.self) { w in Chip(title: w) { onPick(w) } } }
                Spacer()
            }
            .padding(24)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Put a word on it").navigationBarTitleDisplayMode(.inline)
            .task { words = await WordFinder.forText(transcript, context: context).words }
        }
        .presentationDetents([.medium])
    }
}

/// Where she feels it; Done keeps the entry with those places.
struct ListenBodyPicker: View {
    let onPick: ([String], [String]) -> Void
    @State private var draft = CaptureDraft()
    var body: some View {
        NavigationStack {
            BodyMapView(draft: draft)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Keep") { onPick(draft.regions, draft.sensations) } } }
        }
    }
}

/// Self-harm detected: listening stops. Her safety plan and crisis lines, nothing else.
/// It never counsels. She can keep what she said; it is never let go.
struct ListenSafetyView: View {
    let transcript: String
    let onClose: (Bool) -> Void
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Listening has stopped.").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("This is a tool on your phone. It can't help in a crisis. The people on your page, and these lines, can.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    SafetyPlanReadBody(settings: settingsRows.first)
                    CrisisLines()
                    Button("Keep what I said") {
                        let d = CaptureDraft(); d.text = transcript; _ = d.save(in: context)
                        onClose(true)
                    }
                    .buttonStyle(SecondaryCapsule())
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { onClose(false) } } }
        }
    }
}

/// My rules > Listen.
struct ListenSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("How it listens, and how often it offers.").font(.subheadline).foregroundStyle(Palette.muted)
                if let s = settingsRows.first {
                    @Bindable var s = s
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How often it offers things").font(.headline).foregroundStyle(Palette.ink)
                        Picker("Offers", selection: Binding(get: { s.listenOffers }, set: { s.listenOffers = $0; try? context.save() })) {
                            ForEach(ListenOffers.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("Offers are things like \u{201C}put a word on it\u{201D}. The AI never gives advice. Something to try is a fixed list from research.").font(.footnote).foregroundStyle(Palette.muted)
                    }
                    .padding(16).card()
                    VStack(spacing: 0) {
                        RuleToggle(title: "Speak replies aloud", subtitle: "Replies are short text by default.", isOn: $s.listenSpeak)
                        Divider().padding(.leading, 16)
                        RuleToggle(title: "Tell me when a session runs long", subtitle: "A gentle line, once.", isOn: $s.listenLongNote)
                        Divider().padding(.leading, 16)
                        RuleToggle(title: "Quiet topics are respected", subtitle: "It will not raise them.", isOn: .constant(true)).disabled(true)
                        Divider().padding(.leading, 16)
                        RuleToggle(title: "Show my safety page link", subtitle: "Always on screen while listening.", isOn: .constant(true)).disabled(true)
                    }
                    .card()
                    .onChange(of: "\(s.listenSpeak)\(s.listenLongNote)") { s.updatedAt = .now; try? context.save() }
                }
                Text("Listen is a tool on your phone, not a person. It cannot respond to a crisis. If you might hurt yourself, your safety page and the people on it come first.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Listen")
    }
}

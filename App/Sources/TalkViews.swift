import AiHeartCore
import SwiftData
import SwiftUI

// Talk it through (docs/21). A bounded conversation for talking a hard moment through with
// reflective questions. No persona, no advice. Her kept entries, notes and the talks she chose to
// remember are searched on the phone (older memories count for less, none are forgotten); only the few
// passages shown as chips go with the conversation (redacted, docs/20). Safety is checked on the phone
// before any model call, and a turn that mentions self-harm is kept out of every later prompt. Message
// text is never logged: lengths and timings only.

/// One thing in the conversation.
private struct TalkItem: Identifiable {
    enum Kind { case her, app, heavyCard, safetyCard, wrap, notice, end }
    let id = UUID()
    var kind: Kind
    var text = ""
    /// Passages that went with this reply. Only the ones the reply used are shown as chips; the rest sit
    /// behind one quiet line, so she can still see what left the phone.
    var snippets: [Snippet] = []
    var used: [Snippet] = []
    /// One of her turns that mentions self-harm: shown to her, never sent to a model in any later prompt.
    var flagged = false
}

struct TalkView: View {
    /// Her first message, when she comes from Listen.
    var seed: String? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [TalkItem] = []
    @State private var input = ""
    @State private var sending = false
    @State private var index: LocalRetrieval.Index?
    @State private var removed: Set<String> = []
    @State private var startedAt = Date()
    @State private var herCount = 0
    @State private var wrapShown = false
    @State private var extraAllowed = false
    @State private var ended = false
    @State private var heavyShown = false
    @State private var noModel = false
    @State private var showSafety = false
    @State private var askKeep = false
    /// After "Remember it": About me lines proposed from her words in this talk, each added only by her.
    @State private var proposing = false
    @State private var askShame = false
    @State private var scrubbingTalk = false
    /// After scrubbing, About me proposals use only what she kept.
    @State private var proposingFrom: String?
    /// The notes about the talk and her optional own words, shown before the entry is saved.
    @State private var drafting = false
    @State private var checking: Entry?
    @State private var viewing: Snippet?
    @State private var speech = SpeechListener()
    @State private var seeded = false
    @FocusState private var focused: Bool

    /// Her words that may go to a model or be remembered: never a turn that mentions self-harm.
    private var herTexts: [String] { items.filter { $0.kind == .her && !$0.flagged }.map(\.text) }
    /// Every word she wrote, for the journal entry she chooses to keep (it stays on the phone).
    private var allHerTexts: [String] { items.filter { $0.kind == .her }.map(\.text) }
    /// The conversation as the models see it.
    private var turns: [TalkTurn] {
        items.compactMap { i in
            switch i.kind {
            case .her: i.flagged ? nil : TalkTurn(.her, i.text)
            case .app: TalkTurn(.app, i.text)
            default: nil
            }
        }
    }

    var body: some View {
        bodyContent.keyboardHideButton()
            .afterSaveCheck($checking) { proposing = true }
    }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if noModel { unavailable } else { conversation }
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Talk it through").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showSafety = true } label: { Image(systemName: "phone") }.accessibilityLabel("My safety page")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { finish() } }
            }
            .sheet(isPresented: $showSafety) { SafetyPageView(readOnly: true, keptNote: false) }
            .sheet(item: $viewing) { s in snippetSheet(s) }
            .sheet(isPresented: $proposing, onDismiss: { dismiss() }) { TalkAboutMeSheet(words: proposingFrom.map { [$0] } ?? herTexts) }
            .sheet(isPresented: $drafting) {
                TalkSummarySheet(turns: turns) { own, notes in
                    drafting = false
                    if let own {
                        // The entry is only her words: what she typed, else what she said in the talk.
                        let d = CaptureDraft()
                        d.text = own.isEmpty ? herTexts.joined(separator: "\n") : own
                        let e = d.save(in: context)
                        if let notes {
                            var n = e.releaseNote ?? ReleaseNote()
                            n.talkNotes = notes
                            e.releaseNote = n
                            try? context.save()
                        }
                        ReleaseNoteWriter.writeForKept(e, context: context, again: true)
                        // After the sheet closes, the journal checks run, then About me.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { checking = e }
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proposing = true }
                    }
                }
            }
            .confirmationDialog("This talk has something embarrassing in it.", isPresented: $askShame, titleVisibility: .visible) {
                Button("Forget this one", role: .destructive) { leave() }
                Button("Remember it, without the embarrassing parts") { scrubbingTalk = true }
                Button("Remember it all") { remember(journal: false) }
                Button("Remember it and keep it in my journal") { remember(journal: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only what you wrote is remembered, on this phone. Nothing the app said is saved.")
            }
            .sheet(isPresented: $scrubbingTalk) {
                TextScrubSheet(text: herTexts.joined(separator: "\n")) { kept in
                    scrubbingTalk = false
                    if let kept { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { rememberScrubbed(kept) } }
                }
            }
            .confirmationDialog("Remember this talk?", isPresented: $askKeep, titleVisibility: .visible) {
                Button("Remember it") { remember(journal: false) }
                Button("Remember it and keep it in my journal") { remember(journal: true) }
                Button("Forget this one", role: .destructive) { leave() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only what you wrote is remembered, on this phone, so a later talk can mirror your words back. Nothing the app said is saved.")
            }
        }
        .interactiveDismissDisabled(!items.isEmpty)
        .task { await start() }
        .onDisappear { speech.discard() }
    }

    // MARK: Screens

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        intro
                        ForEach(items) { item in row(item).id(item.id) }
                        if sending {
                            HStack(spacing: 8) { ProgressView(); Text("Reading what you wrote\u{2026}").font(.footnote).foregroundStyle(Palette.muted) }
                                .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: items.count) { _, _ in
                    guard let last = items.last else { return }
                    if reduceMotion { proxy.scrollTo(last.id, anchor: .bottom) }
                    else { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider().overlay(Palette.line)
            composer
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CloudSettings.isOn ? "An AI to help you think a hard moment through. It asks questions. It does not give advice."
                                    : "An AI on your phone, to help you think a hard moment through. It asks questions. It does not give advice.")
                .font(.footnote).foregroundStyle(Palette.muted)
            Text(CloudSettings.isOn
                 ? "What you write goes to the cloud model, with up to four short passages from your kept notes and the talks you chose to remember, and your About me. Anything that mentions hurting yourself stays on this phone. Remembered talks are kept on this phone and count for less as they get older."
                 : "Everything stays on this phone. It may look through your kept notes and the talks you chose to remember (older ones count for less), and shows you what it used.")
                .font(.footnote).foregroundStyle(Palette.muted)
        }
        .padding(.bottom, 4)
    }

    private var unavailable: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Talk it through needs the cloud model or the on-device model. You can still write it down.")
                .font(.body).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
            Button("Write it down instead") { dismiss() }
                .font(.headline).foregroundStyle(Palette.onAction)
                .frame(maxWidth: .infinity, minHeight: 52).background(Palette.action, in: Capsule())
            Spacer()
        }
        .padding(28)
    }

    @ViewBuilder private var composer: some View {
        if ended {
            Text(TalkItThrough.endLine).font(.subheadline).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 56).padding(.horizontal, 20)
        } else {
            VStack(spacing: 6) {
                if case .unavailable(let why) = speech.state { Text(why).font(.footnote).foregroundStyle(Palette.muted) }
                HStack(alignment: .bottom, spacing: 10) {
                    Button { Task { await toggleMic() } } label: {
                        Image(systemName: speech.state == .listening ? "stop.circle.fill" : (speech.transcribing ? "ellipsis.circle" : "mic"))
                            .font(.title2).foregroundStyle(Palette.onTint).frame(width: 44, height: 44)
                    }
                    .disabled(speech.transcribing || sending || waitingForChoice)
                    .accessibilityLabel(speech.state == .listening ? "Stop and write out what I said" : "Speak instead of typing")
                    TextField(waitingForChoice ? "Choose above first." : "Say what is on your mind.", text: $input, axis: .vertical)
                        .disabled(waitingForChoice)
                        .font(.body).lineLimit(1...6).focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
                    Button { Task { await send() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(canSend ? Palette.action : Palette.line)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var canSend: Bool {
        !sending && speech.state != .listening && waitingForChoice == false
            && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// After the wrap-up line she chooses first: keep a note and stop, or one more thing.
    private var waitingForChoice: Bool { wrapShown && !extraAllowed }

    // MARK: Rows

    @ViewBuilder private func row(_ item: TalkItem) -> some View {
        switch item.kind {
        case .her:
            HStack {
                Spacer(minLength: 48)
                Text(item.text).font(.body).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Palette.tint1, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("You: \(item.text)")
            }
        case .app:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.text).font(.body).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
                        .accessibilityLabel("Reply: \(item.text)")
                    Spacer(minLength: 48)
                }
                if !item.used.isEmpty {
                    FlowLayout(spacing: 6) { ForEach(item.used) { chip($0) } }
                }
                if item.snippets.count > item.used.count {
                    DisclosureGroup {
                        FlowLayout(spacing: 6) { ForEach(item.snippets.filter { s in !item.used.contains(s) }) { chip($0) } }
                    } label: {
                        Text("\(item.snippets.count - item.used.count) note\(item.snippets.count - item.used.count == 1 ? "" : "s") sent for context")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    .tint(Palette.muted)
                }
            }
        case .heavyCard:
            ListenHeavyCard()
        case .safetyCard:
            VStack(alignment: .leading, spacing: 8) {
                Text("This is not one for this space.").font(.headline).foregroundStyle(Palette.ink)
                Text("Your safety page has the people you named and the crisis lines. You can keep talking here after you look.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Button("Open my safety page") { showSafety = true }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        case .wrap:
            VStack(alignment: .leading, spacing: 8) {
                Text(item.text).font(.body).foregroundStyle(Palette.ink)
                if !extraAllowed && !ended {
                    HStack(spacing: 16) {
                        Button("Keep a note and stop") { askKeep = true }
                        Button("One more thing") { extraAllowed = true; focused = true }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
        case .notice:
            Text(item.text).font(.footnote).foregroundStyle(Palette.muted)
        case .end:
            Text(item.text).font(.subheadline).foregroundStyle(Palette.muted)
        }
    }

    private func chip(_ s: Snippet) -> some View {
        let gone = removed.contains(s.id)
        let date = s.date.formatted(date: .abbreviated, time: .omitted)
        return HStack(spacing: 0) {
            Button { viewing = s } label: {
                Text(gone ? "Not used again: \(date)" : (s.fromTalk ? "From your talk: \(date), \(MemoryRecency.ageText(of: s.date))" : "From your notes: \(date)"))
                    .font(.footnote).foregroundStyle(gone ? Palette.muted : Palette.ink)
                    .padding(.leading, 12).padding(.trailing, gone ? 12 : 4).frame(minHeight: 44)
            }
            if !gone {
                Button { removed.insert(s.id) } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                        .padding(.horizontal, 10).frame(minHeight: 44)
                }
                .accessibilityLabel("Stop using the note from \(date) in this talk")
            }
        }
        .background(Palette.card, in: Capsule())
        .overlay(Capsule().stroke(Palette.line))
        .contextMenu {
            if !gone { Button("Stop using this note", systemImage: "xmark") { removed.insert(s.id) } }
        }
    }

    private func snippetSheet(_ s: Snippet) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(s.date.formatted(date: .long, time: .omitted) + (s.fromTalk ? " (" + MemoryRecency.ageText(of: s.date) + ")" : ""))
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Text(s.text).font(.journal(.body)).foregroundStyle(Palette.ink)
                    Text("This is what went with your message, with names and numbers swapped out when the cloud model is on.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                    if !removed.contains(s.id) {
                        Button("Stop using this note in this talk") { removed.insert(s.id); viewing = nil }
                            .font(.headline).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                    }
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("From your notes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { viewing = nil } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Flow

    private func start() async {
        guard !seeded else { return }
        seeded = true
        startedAt = Date()
        let llm = LLMService.shared
        if llm.state != .ready { await llm.prepare() }
        guard llm.state == .ready else { noModel = true; return }
        // Index her kept notes on the phone. Embedding every chunk takes a moment, off the main actor.
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let talks = (try? context.fetch(FetchDescriptor<TalkMemory>())) ?? []
        let quiet = WordFinder.quietTopics(context)
        let docs = LocalRetrieval.documents(from: entries, quietTopics: quiet) + LocalRetrieval.documents(fromTalks: talks, quietTopics: quiet)
        let t0 = Date()
        let built = await Task.detached(priority: .userInitiated) { LocalRetrieval.Index(documents: docs) }.value
        NSLog("AiHeartTalk index: %d passages in %.1f s", docs.count, Date().timeIntervalSince(t0))
        index = built
        if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await send(text: seed) } else { focused = true }
    }

    private func send() async { await send(text: input) }

    private func send(text raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !ended else { return }
        guard !waitingForChoice else { return }
        input = ""
        // On the phone, before any model call. The turn is marked before it joins the conversation, so a
        // flagged turn is never part of the history, summary, shame check or About me prompts.
        let safety = TalkItThrough.safety(herMessage: text)
        items.append(TalkItem(kind: .her, text: text, flagged: safety == .selfHarm))
        herCount += 1
        NSLog("AiHeartTalk message %d: %d chars", herCount, text.count)

        switch safety {
        case .selfHarm:
            NSLog("AiHeartTalk safety: self-harm, no model call")
            items.append(TalkItem(kind: .safetyCard))
            showSafety = true
            return
        case .heavy:
            if !heavyShown { heavyShown = true; items.append(TalkItem(kind: .heavyCard)) }
        case .none:
            break
        }

        // A long session wraps up once, with a fixed line and no model.
        if !wrapShown, TalkItThrough.shouldWrap(startedAt: startedAt, herMessages: herCount) {
            wrapShown = true
            items.append(TalkItem(kind: .wrap, text: TalkItThrough.wrapLine))
            return
        }

        sending = true
        defer { sending = false }
        let turns = self.turns
        // Her last two messages are the question for the search.
        let query = herTexts.suffix(2).joined(separator: " ")
        let snippets = index?.search(query, k: TalkItThrough.maxSnippets, excluding: removed) ?? []
        let quiet = WordFinder.quietTopics(context)
        let t0 = Date()
        let about = ((try? context.fetch(FetchDescriptor<AboutMe>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []).first?.markdown ?? ""
        let previous = items.filter { $0.kind == .app }.map(\.text).filter { TalkItThrough.fallbacks.contains($0) }
        let talkModel = LLMService.shared.model(for: .talk)
        let modelName = talkModel.name
        let result = await TalkItThrough.reply(model: talkModel, turns: turns, snippets: snippets, quietTopics: quiet,
                                               aboutMe: about, previousFallbacks: previous) { reason in
            // Reason and model name only; never her words or the reply.
            NSLog("AiHeartTalk %@ (%@)", reason, modelName)
        }
        NSLog("AiHeartTalk reply in %.1f s, %d passages sent", Date().timeIntervalSince(t0), snippets.count)
        switch result {
        case .model(let reply), .fallback(let reply):
            items.append(TalkItem(kind: .app, text: reply, snippets: snippets,
                                  used: TalkItThrough.usedSnippets(reply: reply, snippets: snippets)))
        case .unavailable:
            items.append(TalkItem(kind: .notice, text: "The model could not be reached just now. What you wrote is still here. You can send it again, or write it down."))
        }
        // The one more message is answered; then this one is over.
        if wrapShown, extraAllowed {
            if case .unavailable = result {} else {
                ended = true
                items.append(TalkItem(kind: .end, text: TalkItThrough.endLine))
            }
        }
    }

    private func toggleMic() async {
        if speech.state == .listening {
            await speech.finish()
            let said = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            speech.discard()
            if !said.isEmpty { input = input.isEmpty ? said : input + " " + said }
            focused = true
        } else {
            await speech.start()
        }
    }

    // MARK: Ending

    private func finish() {
        speech.discard()
        guard herCount > 0 else { dismiss(); return }
        // Owner, 2026-11-04: the shame check should work in the chat too. Her words are checked (her
        // shame words, then the model's yes or no); embarrassing talks get a different ending.
        Task {
            let words = herTexts.joined(separator: "\n")
            var shameful = KeepOrRelease.shameHits(words) > 0
            let llm = LLMService.shared
            if !shameful, llm.canAnswer(.talk) {
                shameful = await AutoDecide.ask(llm.model(for: .talk), ModelChecks.shameQuestion(words), ownText: words) == .yes
            }
            NSLog("AiHeartTalk end: shameful=%d", shameful ? 1 : 0)
            if shameful { askShame = true } else { askKeep = true }
        }
    }

    /// Remembers only what she chose to keep of her words (after scrubbing).
    private func rememberScrubbed(_ text: String) {
        context.insert(TalkMemory(date: startedAt, text: text, deviceId: UIDevice.current.identifierForVendor?.uuidString ?? ""))
        try? context.save()
        proposingFrom = text
        proposing = true
    }

    /// Her messages only, as a talk memory (the mirror), and as an entry if she asks.
    private func remember(journal: Bool) {
        let words = herTexts.joined(separator: "\n")
        context.insert(TalkMemory(date: startedAt, text: words, deviceId: UIDevice.current.identifierForVendor?.uuidString ?? ""))
        try? context.save()
        if journal { drafting = true } else { proposing = true }
    }

    /// Her messages only, as one entry. Nothing the app said is stored.
    private func keepNote() {
        saveEntry()
        dismiss()
    }

    private func saveEntry() {
        let d = CaptureDraft()
        d.text = allHerTexts.joined(separator: "\n")
        let entry = d.save(in: context)
        ReleaseNoteWriter.writeForKept(entry, context: context)
    }

    private func leave() { dismiss() }
}


/// After a remembered talk: up to three About me lines from her own words in it (owner, 2026-11-04:
/// "Talk it through should remember past chats, so About me should be updated"). Written by the
/// model, checked by the output rules, and added only when she taps Add. Never names other people.
struct TalkAboutMeSheet: View {
    let words: [String]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var added: Set<String> = []
    @State private var skipped: Set<String> = []
    @State private var looking = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add to About me?").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("From what you said in this talk. Only what you add is kept, and you can change it any time in About me.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    if looking {
                        HStack(spacing: 8) { ProgressView(); Text("Looking at what you said…").font(.footnote).foregroundStyle(Palette.muted) }
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else if lines.isEmpty {
                        Text("Nothing new to add this time.").foregroundStyle(Palette.muted)
                    }
                    ForEach(lines.filter { !skipped.contains($0) }, id: \.self) { line in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(line).font(.journal(.body)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 20) {
                                if added.contains(line) {
                                    Label("Added", systemImage: "checkmark").foregroundStyle(Palette.onTint)
                                } else {
                                    Button("Add") { add(line) }.font(.headline).foregroundStyle(Palette.onTint)
                                    Button("Not this") { skipped.insert(line) }.foregroundStyle(Palette.muted)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                }
                .padding(24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await look() }
        }
    }

    private func row() -> AboutMe {
        let rows = (try? context.fetch(FetchDescriptor<AboutMe>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
        if let r = rows.first { return r }
        let r = AboutMe(); context.insert(r); return r
    }

    private func look() async {
        defer { looking = false }
        let quiet = WordFinder.quietTopics(context)
        let entryLines = AboutMeWriter.entryLines([(word: nil, text: words.joined(separator: "\n"))], quietTopics: quiet)
        guard !entryLines.isEmpty else { return }
        let llm = LLMService.shared
        if llm.state != .ready { await llm.prepare() }
        let model = llm.model(for: .talk)
        guard !(model is RuleBasedModel) else { return }
        let existing = row().markdown
        let prompt = AboutMeWriter.prompt(findings: [], entries: entryLines, existing: existing)
        let policy = OutputPolicy(input: prompt, userText: entryLines.joined(separator: " "), quietTopics: quiet, maxCharacters: 200)
        for attempt in 0..<2 {
            let req = GenerationRequest(system: AboutMeWriter.system, prompt: prompt, maxTokens: 160, temperature: 0.4 + 0.2 * Float(attempt),
                                    ownText: entryLines.joined(separator: "\n"))
            guard let raw = try? await model.generate(req) else { continue }
            // Never a line that touches self-harm; those stay in her own words, in her journal.
            let found = AboutMeWriter.lines(from: raw, policy: policy, existing: existing).filter { !SafetyCheck.mentionsSelfHarm($0) }
            if !found.isEmpty { lines = found; return }
        }
    }

    private func add(_ line: String) {
        let r = row()
        let p = AboutMeProposals.Proposal(id: "talk:" + AboutMeProposals.stableHash(line.lowercased()), text: line)
        r.markdown = AboutMeProposals.add(p, to: AboutMeDoc.parse(r.markdown)).markdown
        r.updatedAt = .now
        try? context.save()
        added.insert(line)
    }
}


/// What goes into the journal from a talk (owner, 2026-11-05): the entry is only her own words. The model
/// writes short notes about the talk, addressed to her as "you", shown read-only and stored as notes, never
/// as her text. If the notes fail the checks she just sees none.
struct TalkSummarySheet: View {
    let turns: [TalkTurn]
    /// Her own typed words (empty if none) and the notes, or nil when she skips.
    let onDone: (String?, String?) -> Void
    @Environment(\.modelContext) private var context
    @State private var notes: String?
    @State private var own = ""
    @State private var writing = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your journal entry is your own words. The notes below are about the talk and are kept beside it.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    if writing {
                        HStack(spacing: 8) { ProgressView(); Text("Making notes on the talk…").font(.footnote).foregroundStyle(Palette.muted) }
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if let notes {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes about this talk").font(.headline).foregroundStyle(Palette.ink)
                            Text(notes).font(.body).foregroundStyle(Palette.ink)
                            Text("Written by the app, not by you.").font(.caption).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add your own words").font(.headline).foregroundStyle(Palette.ink)
                        TextEditor(text: $own)
                            .font(.journal(.body))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        Text("Optional. Left empty, the entry is what you said in the talk.").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                .padding(20)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("For your journal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { onDone(nil, nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onDone(own.trimmingCharacters(in: .whitespacesAndNewlines), notes) }.disabled(writing)
                }
            }
            .keyboardHideButton()
            .task { await write() }
        }
        .interactiveDismissDisabled()
    }

    private func write() async {
        defer { writing = false }
        let herWords = turns.filter { $0.role == .her }.map(\.text).joined(separator: "\n")
        let llm = LLMService.shared
        if llm.state != .ready { await llm.prepare() }
        guard llm.canAnswer(.talk) else { return }
        let req = GenerationRequest(system: TalkItThrough.notesSystem, prompt: TalkItThrough.notesPrompt(turns: turns),
                                    maxTokens: 200, temperature: 0.3, ownText: herWords)
        if let raw = try? await llm.model(for: .talk).generate(req) {
            notes = TalkItThrough.checkNotes(raw, herWords: herWords, quietTopics: WordFinder.quietTopics(context))
        }
    }
}

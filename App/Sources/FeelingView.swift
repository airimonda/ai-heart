import AiHeartCore
import Speech
import SwiftData
import SwiftUI

/// How does it feel? (screen 10). Choosing a word places the point; she can drag it.
struct FeelingView: View {
    let draft: CaptureDraft
    let initialWord: String?
    let suggestions: WordSuggestions
    var findWords = false
    let onSaved: (Entry) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var word: String?
    @State private var ownWord = ""
    @State private var point = MoodPoint.center
    @State private var placed = false
    @State private var showMore = false
    @State private var typingOwn = false
    @State private var found: [String] = []
    @State private var finding = false
    @State private var foundByModel = false

    var body: some View { bodyContent.keyboardHideButton() }

    @ViewBuilder private var bodyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How does it feel?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                    Text(suggestions.fromBody && !suggestions.notes.isEmpty
                         ? "Guessed from your body today: \(suggestions.notes.joined(separator: ", ")). Pick a word, or place the point yourself."
                         : "Pick a word, or place the point yourself.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                if findWords {
                    VStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 0) // keeps the container non-empty so .task runs
                        if finding {
                            HStack(spacing: 8) { ProgressView(); Text("Looking at what you wrote…") }
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        } else if !found.isEmpty {
                            Text(foundByModel ? "From what you wrote" : "Words you have used before")
                                .font(.subheadline).foregroundStyle(Palette.muted)
                            FlowLayout(spacing: 10) {
                                ForEach(found, id: \.self) { w in Chip(title: w, selected: word == w) { choose(w) } }
                            }
                        }
                    }
                    .task {
                        finding = true
                        let r = await WordFinder.forText(draft.text, context: context)
                        found = r.words; foundByModel = r.fromModel
                        finding = false
                    }
                }

                FlowLayout(spacing: 10) {
                    ForEach(suggestions.words.filter { !found.contains($0) } + (showMore ? MoodWords.more.filter { !suggestions.words.contains($0) } + MoodWords.staticSuggestions.filter { !suggestions.words.contains($0) } : []), id: \.self) { w in
                        Chip(title: w, selected: word == w) { choose(w) }
                    }
                    Chip(title: "My own", selected: typingOwn) {
                        typingOwn = true
                        word = nil
                    }
                }

                if typingOwn {
                    TextField("Your word", text: $ownWord)
                        .font(.journal(.title3))
                        .padding(14)
                        .card(radius: 16)
                        .submitLabel(.done)
                }

                Text(placedCaption)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if MoodGuess.isLong(draft.text) && !placed && word == nil {
                    Text("Optional. You wrote a lot; AiHeart can guess from your words.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }

                MoodPad(point: Binding(get: { point }, set: { point = $0; placed = true }))
                    .frame(height: 340)

                Button {
                    withAnimation { showMore.toggle() }
                } label: {
                    HStack {
                        Text("Another way to describe it")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: showMore ? "minus" : "plus")
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(18)
                    .card()
                }
                .buttonStyle(.plain)

                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: save)
            }
        }
        .onAppear {
            if let initialWord { choose(initialWord) }
        }
    }

    private var placedCaption: String {
        if let word { return "Placed from \"\(word)\". Drag to adjust." }
        return placed ? "Drag to adjust." : "Drag the point to where it sits."
    }

    private func choose(_ w: String) {
        word = w
        typingOwn = false
        if let p = MoodWords.point(for: w) {
            withAnimation(.snappy) { point = p }
            placed = true
        }
    }

    private func save() {
        let own = ownWord.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.word = typingOwn ? (own.isEmpty ? nil : own) : word
        draft.point = (placed || draft.word != nil) ? point : nil
        guard !draft.isEmpty else { dismiss(); return }
        onSaved(draft.save(in: context))
    }
}

/// The pleasant / stirred pad. Horizontal: unpleasant to pleasant. Vertical: still to stirred.
struct MoodPad: View {
    @Binding var point: MoodPoint
    var compact = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pos = CGPoint(x: (point.valence + 1) / 2 * size.width,
                              y: (1 - (point.arousal + 1) / 2) * size.height)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: size.width / 2, y: 0)); p.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(Palette.line, lineWidth: 1)

                if !compact { labels(size) }

                Circle()
                    .fill(Palette.tint1)
                    .frame(width: compact ? 0 : 56, height: compact ? 0 : 56)
                    .position(pos)
                Circle()
                    .fill(compact ? Palette.dataMark : Palette.pink)
                    .frame(width: compact ? 8 : 34, height: compact ? 8 : 34)
                    .position(pos)
            }
            .contentShape(Rectangle())
            .gesture(compact ? nil : DragGesture(minimumDistance: 0).onChanged { g in
                point = MoodPoint(valence: Double(g.location.x / size.width) * 2 - 1,
                                  arousal: 1 - Double(g.location.y / size.height) * 2)
            })
        }
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: compact ? 6 : Radius.card, style: .continuous).stroke(Palette.line, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Mood point")
        .accessibilityValue(MoodPad.describe(point))
        .accessibilityAdjustableAction { dir in
            guard !compact else { return }
            point = MoodPoint(valence: point.valence + (dir == .increment ? 0.1 : -0.1), arousal: point.arousal)
        }
    }

    static func describe(_ p: MoodPoint) -> String {
        let v = p.valence > 0.15 ? "pleasant" : p.valence < -0.15 ? "unpleasant" : "neither pleasant nor unpleasant"
        let a = p.arousal > 0.15 ? "stirred" : p.arousal < -0.15 ? "still" : "neither still nor stirred"
        return "\(v), \(a)"
    }

    @ViewBuilder private func labels(_ s: CGSize) -> some View {
        let style = Font.subheadline
        Group {
            Text("stirred").position(x: s.width / 2, y: 20)
            Text("still").position(x: s.width / 2, y: s.height - 20)
            Text("unpleasant").position(x: 52, y: s.height / 2 - 2)
            Text("pleasant").position(x: s.width - 40, y: s.height / 2 - 2)
            Text("tense").position(x: 40, y: 42)
            Text("excited").position(x: s.width - 46, y: 42)
            Text("low").position(x: 28, y: s.height - 42)
            Text("calm").position(x: s.width - 34, y: s.height - 42)
        }
        .font(style)
        .foregroundStyle(Palette.muted)
        .accessibilityHidden(true)
    }
}

/// Write or talk (screen 07). No prompts, no structure.
struct WriteOrTalkView: View {
    let draft: CaptureDraft
    let onSaved: (Entry) -> Void
    let findWords: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VoiceRecorder()
    @State private var talking = false
    @State private var transcribing = false
    @FocusState private var focused: Bool

    var body: some View { bodyContent.keyboardHideButton() }

    @ViewBuilder private var bodyContent: some View {
        @Bindable var draft = draft
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Write or talk")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }

            if talking {
                talkPanel
            } else {
                TextField("Write or talk. No prompts, no structure.", text: $draft.text, axis: .vertical)
                    .font(.journal(.title3))
                    .foregroundStyle(Palette.ink)
                    .focused($focused)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
                    .card()
                    .onTapGesture { focused = true }
            }

            HStack(spacing: 10) {
                Chip(title: talking ? "Write instead" : "Talk instead") {
                    if talking, recorder.isRecording { Task { await finishRecording() } }
                    talking.toggle()
                }
                Chip(title: "Help me find the words", action: findWords)
            }

            Button(transcribing ? "Writing it down\u{2026}" : "Save") {
                Task {
                    if recorder.isRecording { await finishRecording() }
                    guard !draft.isEmpty else { dismiss(); return }
                    onSaved(draft.save(in: context))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(transcribing)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(Palette.surface.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if recorder.isRecording { _ = recorder.stop() }
                    dismiss()
                }
            }
        }
        .onDisappear { if recorder.isRecording { _ = recorder.stop() } }
    }

    private var talkPanel: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(formatDuration(recorder.isRecording ? recorder.elapsed : (draft.audioSeconds ?? 0)))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Button {
                if recorder.isRecording { Task { await finishRecording() } } else { Task { await recorder.start() } }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.onAction)
                    .frame(width: 96, height: 96)
                    .background(Palette.action, in: Circle())
            }
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
            Text(recorder.denied ? "Microphone access is off. You can turn it on in Settings."
                 : transcribing ? "Writing down all of what you said, on this phone."
                 : draft.audio != nil && !recorder.isRecording ? "Voice note and its words are ready. Save keeps both."
                 : "Only saved if you tap Save.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    /// Keeps the voice note and adds its words, transcribed from the whole recording once she
    /// stops (owner, 2026-11-02). On the phone only.
    private func finishRecording() async {
        guard let (data, seconds) = recorder.stop() else { return }
        draft.audio = data
        draft.audioSeconds = seconds
        transcribing = true
        defer { transcribing = false }
        _ = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aiheart-talk-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url, options: .completeFileProtection)) != nil else { return }
        let language = Locale.current.language.languageCode?.identifier == "ja" ? "ja-JP" : "en-US"
        guard let text = await FileTranscriber.transcribe(url, language: language), !text.isEmpty else { return }
        let before = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.text = before.isEmpty ? text : before + "\n\n" + text
    }
}

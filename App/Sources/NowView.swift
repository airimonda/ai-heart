import AiHeartCore
import PhotosUI
import SwiftData
import SwiftUI

enum NowRoute: Hashable { case feeling(String?), findWords, body, write, rules, aboutMe, cycle, labs, export }

struct NowView: View {
    @Binding var tab: AppTab
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsRows: [AppSettings]
    @Query private var summaries: [DaySummary]
    @Query private var entries: [Entry]
    @Query private var workouts: [Workout]
    @State private var lean: MoodLean.Result?
    @State private var leanReady = false
    @State private var promptSkip = 0
    @State private var prompt: String?
    @State private var todayPhotos = TodayPhotos.shared
    @State private var photoError: String?
    @State private var letGo: (Entry, Int)?
    @State private var offer: LetGoOffer?
    @State private var offered: (Entry, AutoDecide.Outcome)?
    @State private var showSafety = false
    @State private var heavyEntry: Entry?
    @Query private var guesses: [GuessFeedback]
    @State private var leanAnsweredToday = false
    @State private var showLeanAnyway = UserDefaults.standard.bool(forKey: "lean.showAnyway")
    @State private var draft = CaptureDraft()
    @State private var path = NavigationPath()
    @State private var saved: Entry?
    @State private var urgent: [UrgentSigns.Finding] = []
    @State private var showListen = false
    @State private var showTalk = false
    @State private var showHard = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @FocusState private var typing: Bool

    private var paused: Bool { settingsRows.first?.pauseEverything ?? false }

    private var snapshot: BodySnapshot { BodySnapshot.cached(summaries, settings: settingsRows.first) }
    private var suggestions: WordSuggestions {
        let s = BodyWords.suggest(snapshot.hasData ? snapshot.bodyToday : nil, paused: paused)
        // Words she never picks give way to ones she does, within the same quadrant.
        let c = GuessLog.wordCounts(guesses)
        return WordSuggestions(words: WordPreference.adjust(s.words, picks: c.picks, shown: c.shown), notes: s.notes, fromBody: s.fromBody)
    }

    /// After she logs something, check today's body words and check-in against the fixed
    /// urgent-sign rules. Each finding shows once a day.
    private func checkUrgent() {
        guard saved == nil, letGo == nil, offer == nil, !showSafety, heavyEntry == nil else { return }
        let today = snapshot.today
        let row = summaries.first { $0.dayKey == today.key && $0.deviceId != DemoData.tag }
        let found = UrgentWatch.pending(entries: entries.filter { $0.deviceId != DemoData.tag }, summary: row,
                                        today: today, dayStart: settingsRows.first?.dayStartHour ?? 4)
        if !found.isEmpty { NSLog("AiHeartUI urgent signs shown: %d", found.count); urgent = found }
    }

    private var leanSummary: LeanRecord.Summary {
        GuessLog.leanSummary(guesses, entries: entries, dayStart: settingsRows.first?.dayStartHour ?? 4)
    }

    var body: some View { bodyContent.keyboardHideButton() }

    @ViewBuilder private var bodyContent: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    captureBox
                    actionRow
                    if !paused { DailyLogCard() }
                    if !paused { EarlySignsCard() }
                    TodayCard(snap: snapshot, paused: paused, showLean: settingsRows.first?.outlookOn ?? true,
                              lean: lean, leanReady: leanReady, summary: leanSummary,
                              leanPaused: leanSummary.paused && !showLeanAnyway,
                              answeredToday: leanAnsweredToday,
                              answer: { fit in GuessLog.answerLean(fit, context: context); leanAnsweredToday = true },
                              showAnyway: { showLeanAnyway = true; UserDefaults.standard.set(true, forKey: "lean.showAnyway") }) { tab = .insights }
                    if !paused { NowVibeLine(plain: true) }
                    if !paused, todayPhotos.status == .notDetermined {
                        // One-time ask; afterwards today's photos sit inside the writing box.
                        TodayPhotosCard(onPick: { _ in }, browse: browsePhotos)
                    } else if !paused, todayPhotos.available.isEmpty {
                        promptCard
                    }
                    if !paused, AppFeedbackCard.isDue(context, enabled: settingsRows.first?.askForAppFeedback ?? true) {
                        AppFeedbackCard()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-scrollBottom") ? .bottom : .top)
            #endif
            .background(Palette.surface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: summaries.count + entries.count) { await computeLean() }
            .onAppear { todayPhotos.reload(dayStartHour: settingsRows.first?.dayStartHour ?? 4) }
            .onChange(of: scenePhase) { _, p in if p == .active { todayPhotos.reload(dayStartHour: settingsRows.first?.dayStartHour ?? 4) } }
            .navigationDestination(for: NowRoute.self) { route in
                Group {
                switch route {
                case .feeling(let word): FeelingView(draft: draft, initialWord: word, suggestions: suggestions, onSaved: show)
                case .findWords: FeelingView(draft: draft, initialWord: nil, suggestions: suggestions, findWords: true, onSaved: show)
                case .body: BodyMapView(draft: draft, onSave: show)
                case .write: WriteOrTalkView(draft: draft, onSaved: show, findWords: { path.append(NowRoute.findWords) })
                case .rules: RulesView()
                case .aboutMe: AboutMeView()
                case .cycle: YourCycleView()
                case .labs: LabsView()
                case .export: ExportView()
                }
                }
                .toolbar(.hidden, for: .tabBar)
            }
        }
        .sheet(item: $saved) { entry in
            SavedSheet(entry: entry) { restoreDraft(from: entry) }
        }
        .sheet(isPresented: Binding(get: { letGo != nil }, set: { if !$0 { letGo = nil } })) {
            if let (e, n) = letGo { LetGoSheet(entry: e, keptCount: n) }
        }
        .sheet(item: $offer, onDismiss: afterOffer) { o in
            LetGoOfferSheet(offer: o) { outcome in offered = (o.entry, outcome); offer = nil }
        }
        .sheet(isPresented: $showSafety) { SafetyPageView(readOnly: true) }
        .sheet(item: $heavyEntry) { e in HeavyKeptSheet(entry: e) }
        .fullScreenCover(isPresented: $showListen) { ListenView() }
        .sheet(isPresented: $showTalk) { TalkView() }
        .sheet(isPresented: $showHard) { HardRightNowSheet() }
        .sheet(isPresented: Binding(get: { !urgent.isEmpty }, set: { if !$0 { urgent = [] } })) { UrgentSheet(findings: urgent) }
        .onChange(of: saved == nil) { _, closed in if closed { checkUrgent() } }
        .onAppear(perform: checkUrgent)
        #if DEBUG
        .fullScreenCover(item: Binding(get: { ProcessInfo.processInfo.arguments.contains("-burnDemo") ? entries.first { $0.status == .resting } : nil }, set: { _ in })) { BurningView(entry: $0) }
        #endif
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in attach(ImageTools.prepare(image)) }.ignoresSafeArea()
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openBody") { path = NavigationPath([NowRoute.body]) }
            if args.contains("-openListen") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showListen = true } }
            if args.contains("-openFeeling") { path = NavigationPath([NowRoute.feeling("Wired")]) }
            if args.contains("-openRules") { path = NavigationPath([NowRoute.rules]) }
            if args.contains("-openAboutMe") { path = NavigationPath([NowRoute.aboutMe]) }
            if args.contains("-openCycle") { path = NavigationPath([NowRoute.cycle]) }
            if args.contains("-openLabs") { path = NavigationPath([NowRoute.labs]) }
            if args.contains("-openExport") { path = NavigationPath([NowRoute.export]) }
            if args.contains("-saveHard") {
                draft.text = "[Sample] It was an awful day. We had a fight and I cried for an hour. A walk helped a bit. I needed someone to listen. Tomorrow I will rest."
                draft.word = "Heavy"
                draft.point = MoodPoint(valence: -0.7, arousal: -0.2)
                show(draft.save(in: context))
            }
            if args.contains("-findWords") { draft.text = "[Sample] Long day, kept thinking about the move."; path = NavigationPath([NowRoute.findWords]) }
            if args.contains("-openBodyMore") || args.contains("-bodyAll") || args.contains("-bodyBack") { path = NavigationPath([NowRoute.body]) }
        }
        #endif
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            NSLog("AiHeartPhoto picked from library")
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                NSLog("AiHeartPhoto library bytes %d", data?.count ?? -1)
                attach(data.flatMap(ImageTools.prepare))
                photoItem = nil
            }
        }
    }

    /// Today's lean, computed off the main thread from her own clear links.
    private func computeLean() async {
        let snap = snapshot
        let input = PatternInputBuilder.make(snap: snap, entries: entries, workouts: workouts, dayStart: settingsRows.first?.dayStartHour ?? 4)
        let yesterday = snap.today.adding(days: -1)
        var z: [String: Double] = [:]
        z["Sleep"] = snap.z(.sleep, on: snap.today)
        z["Resting HR"] = snap.z(.restingHR, on: yesterday)
        z["HRV"] = snap.z(.hrv, on: yesterday)
        z["Wrist temp"] = snap.z(.wristTemp, on: yesterday)
        z["Steps"] = snap.z(.steps, on: yesterday)
        let zz = z
        let result = await Task.detached(priority: .utility) { MoodLean.compute(links: Patterns.links(input), z: zz) }.value
        lean = result
        leanReady = true
        GuessLog.noteLean(result?.direction, context: context)
        let key = GuessLog.today(context).key
        leanAnsweredToday = guesses.contains { $0.kind == "lean" && $0.dayKey == key && $0.fit != nil }
    }

    /// The system photo picker: any photo she chooses, from any date.
    private func browsePhotos() {
        prompt = "What was happening here?"
        showPhotoPicker = true
    }

    private var promptCard: some View {
        let text = WritingPrompts.pick(day: snapshot.today, body: snapshot.hasData ? snapshot.bodyToday : nil, skip: promptSkip)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Something to write about, if you like").font(.subheadline).foregroundStyle(Palette.muted)
            Button {
                prompt = text
                typing = true
            } label: {
                Text(text)
                    .font(.journal(.title3))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts writing with this in mind")
            HStack(spacing: 20) {
                Button("Another") { promptSkip += 1 }
                Button("Browse your photos", action: browsePhotos)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.onTint)
            .frame(minHeight: 44)
        }
        .padding(18)
        .card()
    }

    private func attach(_ prepared: (photo: Data, thumb: Data)?) {
        NSLog("AiHeartPhoto attach: %@", prepared == nil ? "failed" : "ok")
        guard let prepared else {
            photoError = "That photo could not be opened. If it is in iCloud, try again in a moment."
            return
        }
        photoError = nil
        draft.photo = prepared.photo
        draft.thumb = prepared.thumb
    }

    private func show(_ entry: Entry) {
        let wasPushed = !path.isEmpty
        path = NavigationPath()
        typing = false
        Task {
            let outcome = await AutoDecide.run(entry, context: context)
            // A sheet set while the pushed screen is still popping is dropped by SwiftUI, and then
            // nothing confirms the save. Wait for the pop to finish first.
            if wasPushed { try? await Task.sleep(for: .milliseconds(600)) }
            NSLog("AiHeartUI after save: %@", "\(outcome)")
            // Notes on kept entries (resting ones get theirs from the let-go path).
            switch outcome {
            case .kept, .heavy, .safety, .offerLetGo: ReleaseNoteWriter.writeForKept(entry, context: context)
            default: break
            }
            switch outcome {
            case .kept:
                saved = entry
                Task { await ToneGuesser.guessMood(for: entry, context: context); await ToneGuesser.run(context) }
            case .letGo(let n): letGo = (entry, n)
            case .offerLetGo(let lines):
                offered = (entry, .kept)
                offer = LetGoOffer(entry: entry, lines: lines)
                Task { await ToneGuesser.guessMood(for: entry, context: context) }
            case .safety: showSafety = true
            case .heavy: heavyEntry = entry
            }
        }
    }

    /// Undo on the saved sheet: her words go back into the box, so nothing she wrote is lost.
    private func restoreDraft(from e: Entry) {
        draft.text = e.text ?? ""
        draft.word = e.word
        draft.photo = e.photoData
        draft.thumb = e.thumbData
        draft.regions = e.bodyRegions
        draft.sensations = e.sensations
        draft.audio = e.audioData
        draft.audioSeconds = e.audioSeconds
        if !e.moodGuessed, let v = e.valence, let a = e.arousal { draft.point = MoodPoint(valence: v, arousal: a) }
        typing = !draft.text.isEmpty
    }

    /// After the ask-first sheet closes: let go (she held), or kept (Keep it, or swiped away).
    private func afterOffer() {
        guard let (entry, outcome) = offered else { return }
        offered = nil
        switch outcome {
        case .letGo(let n): letGo = (entry, n)
        case .safety: showSafety = true
        default:
            saved = entry
            Task { await ToneGuesser.run(context) }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(Palette.action)
                .accessibilityHidden(true)
            Text("AiHeart")
                .font(.title2.bold())
                .foregroundStyle(Palette.action)
            Spacer()
            Button { path.append(NowRoute.rules) } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("My rules")
        }
        .padding(.top, 8)
    }

    private var captureBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anything to put down?")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
            TextField(prompt ?? "Write, talk, or tap a word below.", text: $draft.text, axis: .vertical)
                .font(.journal(.title3))
                .foregroundStyle(Palette.ink)
                .lineLimit(4...10)
                .focused($typing)

            if draft.photo != nil || !draft.regions.isEmpty || draft.audio != nil {
                attachments
            }
            if let photo = draft.thumb, !paused {
                PhotoWords(photo: photo, draft: draft)
            }
            if let photoError {
                Text(photoError).font(.footnote).foregroundStyle(Palette.muted)
            }
            if !paused, draft.photo == nil, !todayPhotos.available.isEmpty { inlinePhotos }

            HStack(alignment: .top, spacing: 14) {
                Menu {
                    if CameraPicker.isAvailable {
                        Button("Take photo", systemImage: "camera") { showCamera = true }
                    }
                    Button("Choose photo", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                } label: {
                    LabeledIcon(systemName: "camera", title: "Photo")
                }
                .accessibilityLabel("Add a photo")

                Button { path.append(NowRoute.write) } label: { LabeledIcon(systemName: "mic", title: "Talk") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Write or talk")

                Button { path.append(NowRoute.body) } label: { LabeledIcon(systemName: "figure.stand.dress", title: "Body") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Where do you feel it")

                Spacer()

                Button {
                    show(draft.save(in: context))
                } label: {
                    Text("Save")
                        .lineLimit(1)
                        .fixedSize()
                        .font(.headline)
                        .foregroundStyle(draft.isEmpty ? Palette.onTint.opacity(0.5) : Palette.onAction)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 48)
                        .background(draft.isEmpty ? Palette.tint1 : Palette.action, in: Capsule())
                }
                .disabled(draft.isEmpty)
            }
            if !paused && draft.isEmpty {
                Divider().overlay(Palette.line)
                words
            }
        }
        .padding(20)
        .frame(minHeight: 250, alignment: .top)
        .card(radius: Radius.capture)
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
    }

    /// One row of three quiet buttons (owner, 2026-11-04: Now felt crowded). "Hard right now?" stays
    /// even with Pause everything on: taps only, no typing (docs/15).
    private var actionRow: some View {
        HStack(spacing: 8) {
            if !paused {
                pill("Listen", "waveform") { showListen = true }
                pill("Talk it through", "text.bubble") { showTalk = true }
            }
            pill("Hard right now?", "leaf") { showHard = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.onTint)
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(Palette.tint1, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var attachments: some View {
        HStack(spacing: 10) {
            if let thumb = draft.thumb, let image = UIImage(data: thumb) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        RemoveButton(label: "Remove photo") { draft.photo = nil; draft.thumb = nil }
                    }
            }
            if draft.audio != nil {
                Label(formatDuration(draft.audioSeconds ?? 0), systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(Palette.onTint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Palette.tint1, in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        RemoveButton(label: "Remove voice note") { draft.audio = nil; draft.audioSeconds = nil }
                    }
            }
            if !draft.regions.isEmpty {
                Text(bodySummary(regions: draft.regions, sensations: draft.sensations))
                    .font(.subheadline)
                    .foregroundStyle(Palette.onTint)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Palette.tint1, in: Capsule())
                    .onTapGesture { path.append(NowRoute.body) }
            }
        }
    }

    /// Today's photos as a strip inside the writing box: tap one to attach it.
    private var inlinePhotos: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("From today").font(.footnote).foregroundStyle(Palette.muted)
                Spacer()
                Button("Skip") { todayPhotos.skippedToday = true; todayPhotos.reload(dayStartHour: settingsRows.first?.dayStartHour ?? 4) }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 32)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(todayPhotos.available, id: \.localIdentifier) { a in
                        Button {
                            todayPhotos.usedIDs.insert(a.localIdentifier)
                            Task {
                                attach(await todayPhotos.prepared(a))
                                prompt = "What was happening here?"
                                typing = true
                            }
                        } label: { Thumb(asset: a, side: 64) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use photo from \(a.creationDate?.formatted(date: .omitted, time: .shortened) ?? "today")")
                    }
                }
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BodyWords.caption(suggestions))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            // One row that scrolls sideways: it never wraps, so chips can never overlap.
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(suggestions.words, id: \.self) { word in
                    Chip(title: word) {
                        GuessLog.noteWords(kind: "words", shown: suggestions.words, picked: word, context: context)
                        draft.word = word
                        show(draft.save(in: context))
                    }
                    .accessibilityHint("Saves this word now")
                }
                Chip(title: "My own") {
                    // None of the suggestions fit.
                    GuessLog.noteWords(kind: "words", shown: suggestions.words, picked: nil, context: context)
                    path.append(NowRoute.feeling(nil))
                }
              }
            }
        }
    }
}

/// Round icon with a small word under it, so each capture action says what it does.
struct LabeledIcon: View {
    let systemName: String
    let title: String
    var body: some View {
        VStack(spacing: 4) {
            CircleIcon(systemName: systemName)
            Text(title).font(.caption2.weight(.medium)).foregroundStyle(Palette.muted)
        }
    }
}

struct CircleIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.title3)
            .foregroundStyle(Palette.onTint)
            .frame(width: 52, height: 52)
            .background(Palette.card, in: Circle())
            .overlay(Circle().stroke(Palette.line, lineWidth: 1))
    }
}

struct RemoveButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Palette.onAction, Palette.muted)
                .font(.body)
                .frame(width: 44, height: 44)
        }
        .offset(x: 18, y: -18)
        .accessibilityLabel(label)
    }
}

/// Top of Now (owner, 2026-10-31: no cycle here). The date, a glance at the body against
/// her usual, and a lean for today's mood from her own clear links. Tap opens Insights.
struct TodayCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let snap: BodySnapshot
    let paused: Bool
    let showLean: Bool
    let lean: MoodLean.Result?
    let leanReady: Bool
    var summary = LeanRecord.Summary(answered: 0, fit: 0, checked: 0, matched: 0)
    var leanPaused = false
    var answeredToday = false
    var answer: (Bool) -> Void = { _ in }
    var showAnyway: () -> Void = {}
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                if paused {
                    Text("Paused. Capture still works.").font(.subheadline).foregroundStyle(Palette.muted)
                } else if !snap.hasData {
                    Text("Body signals appear once Apple Health is connected.").font(.subheadline).foregroundStyle(Palette.muted)
                } else {
                    // Four across normally; two by two at the largest text sizes.
                    let cols = typeSize.isAccessibilitySize ? 2 : 4
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .topLeading), count: cols), alignment: .leading, spacing: 12) {
                        glance("Sleep", .sleep, day: snap.today)
                        glance("Resting HR", .restingHR, day: snap.today)
                        glance("HRV", .hrv, day: snap.today)
                        glance("Steps", .steps, day: snap.today.adding(days: -1), note: "yesterday")
                    }
                    if showLean {
                        Divider().overlay(Palette.line)
                        if leanPaused {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("The mood lean is paused: it missed more often than it fit (\(summary.fit) of \(summary.answered) days).")
                                    .font(.subheadline).foregroundStyle(Palette.ink)
                                Button("Show it anyway", action: showAnyway)
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.onTint).frame(minHeight: 44)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle").foregroundStyle(Palette.onTint).accessibilityHidden(true)
                                Text(leanReady ? MoodLean.sentence(lean) : "Looking at how your body and mood line up…")
                                    .font(.subheadline).foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if leanReady, lean != nil {
                                LeanFeedbackRow(summary: summary, answeredToday: answeredToday, answer: answer)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Insights, Today")
    }

    private func glance(_ title: String, _ signal: Signal, day: AnchoredDay, note: String? = nil) -> some View {
        let reading = snap.reading(signal, on: day)
        let arrow: String = switch reading?.direction { case 1: "arrow.up"; case -1: "arrow.down"; default: "equal" }
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            HStack(spacing: 3) {
                Text(snap.formatted(signal, on: day) ?? "–").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if reading != nil {
                    Image(systemName: arrow).font(.caption2.weight(.bold))
                        .foregroundStyle(reading == .within ? Palette.muted : Palette.dataMark)
                }
            }
            Text(note ?? (reading.map { $0 == .within ? "usual" : ($0.direction > 0 ? "above usual" : "below usual") } ?? " "))
                .font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

func bodySummary(regions: [String], sensations: [String]) -> String {
    let r = regions.map(BodyRegion.label(for:)).joined(separator: ", ")
    let s = sensations.map { $0.lowercased() }.joined(separator: ", ")
    return s.isEmpty ? r : "\(r) · \(s)"
}

/// Saved result as a bottom sheet (screen 25). The let-go variant (22) arrives with M9.
struct SavedSheet: View {
    let entry: Entry
    /// Puts her words back in the capture box before the entry is removed.
    var onUndo: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Taps in the first moment are ignored: the sheet rises where the Save button was, and a
    /// second tap on Save used to land on Undo and remove the entry (owner report, 2026-11-04).
    @State private var armed = false
    @State private var showNotes = false
    var pending = NotesPending.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.onAction)
                    .frame(width: 52, height: 52)
                    .background(Palette.action, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kept in your journal")
                        .font(.title3.bold())
                        .foregroundStyle(Palette.ink)
                    Text("As you wrote it.")
                        .foregroundStyle(Palette.muted)
                }
            }
            if entry.releaseNote != nil {
                Button { showNotes = true } label: {
                    Label("See notes on this moment", systemImage: "note.text").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .font(.headline).foregroundStyle(Palette.onTint)
            } else if pending.ids.contains(entry.syncId) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Writing notes on how you reacted…").font(.footnote).foregroundStyle(Palette.muted)
                }
                .frame(minHeight: 44)
            }
            HStack {
                Button("Undo") {
                    guard armed else { return }
                    NSLog("AiHeartUI saved sheet: undo")
                    onUndo()
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(Palette.onTint)
                .frame(minWidth: 44, minHeight: 44)
                Spacer()
                Button("Done") { if armed { dismiss() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 140)
            }
        }
        .padding(24)
        .task { try? await Task.sleep(for: .milliseconds(1000)); armed = true }
        .presentationDetents([.height(290)])
        .sheet(isPresented: $showNotes) {
            NavigationStack {
                ScrollView { LiveNotes(entry: entry).padding(20) }
                    .background(Palette.surface.ignoresSafeArea())
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showNotes = false } } }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.surface)
    }
}


/// "Hard right now?": the three ways to get help, one tap each (docs/15, docs/17).
struct HardRightNowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reaching = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hard right now?").font(.title2.bold()).foregroundStyle(Palette.ink)
                Text("Pick one. You can stop any time.").font(.subheadline).foregroundStyle(Palette.muted)
                VStack(spacing: 0) {
                    row("Something to try", "Breathing, grounding, body, thoughts, moving", "leaf") {
                        dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppRouter.shared.openHardMoments = true }
                    }
                    Divider().padding(.leading, 16)
                    row("My safety plan", "Your steps, people and numbers", "list.bullet.clipboard") {
                        dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { AppRouter.shared.openSafetyPlan = true }
                    }
                    Divider().padding(.leading, 16)
                    row("Who I can reach", "My therapist, my people, crisis lines", "phone") { reaching = true }
                }
                .card()
                Spacer()
            }
            .padding(24)
            .background(Palette.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $reaching) { ListenReachSheet() }
        }
        .presentationDetents([.medium])
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

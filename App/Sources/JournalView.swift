import AiHeartCore
import SwiftData
import SwiftUI

enum JournalFilter: String, CaseIterable, Identifiable {
    case all = "Everything", photos = "Photos", words = "Words", writing = "Writing", voice = "Voice notes", body = "Body"
    var id: String { rawValue }

    func includes(_ e: Entry) -> Bool {
        switch self {
        case .all: true
        case .photos: e.photoData != nil || e.thumbData != nil
        case .words: e.word != nil
        case .writing: (e.text ?? "").isEmpty == false
        case .voice: e.audioData != nil
        case .body: !e.bodyRegions.isEmpty
        }
    }
}

struct JournalView: View {
    @State private var showDeleted = false
    @Query private var deletedRows: [DeletedEntry]
    private var deletedCount: Int { deletedRows.count }
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @Query private var quiet: [QuietTopic]
    @Query private var settingsRows: [AppSettings]
    @Query private var summaries: [DaySummary]
    @Query private var workouts: [Workout]
    @State private var mode = 0
    @State private var query = ""
    @State private var filter: JournalFilter = .all
    @State private var path = NavigationPath()

    private var dayStart: Int { settingsRows.first?.dayStartHour ?? 4 }

    private var visible: [Entry] {
        let terms = quiet.map(\.term)
        return entries.filter { filter.includes($0) && JournalSearch.matches($0, query: query, quietTopics: terms) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("View", selection: $mode) {
                        Text("Entries").tag(0)
                        Text("Month").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if entries.isEmpty {
                        EmptyJournal()
                    } else if mode == 0 {
                        EntriesList(entries: visible, dayStart: dayStart, snap: BodySnapshot.cached(summaries, settings: settingsRows.first),
                                    workoutsByDay: Dictionary(grouping: workouts) { DayAnchor.day(for: $0.start, timeZone: .current, dayStartHour: dayStart) })
                    } else {
                        MonthView(entries: visible, dayStart: dayStart, snap: BodySnapshot.cached(summaries, settings: settingsRows.first))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("Journal")
            .searchable(text: $query, prompt: "Search your journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $filter) {
                            ForEach(JournalFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Button { showDeleted = true } label: {
                            Label(deletedCount == 0 ? "Recently deleted" : "Recently deleted (\(deletedCount))", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter")
                }
            }
            .navigationDestination(for: Entry.self) { EntryDetailView(entry: $0) }
            .navigationDestination(isPresented: $showDeleted) { RecentlyDeletedView() }
            .navigationDestination(for: OpenEntryRoute.self) { $0.destination }
            .environment(\.openEntry, { path.append(OpenEntryRoute(entry: $0)) })
            .onAppear {
                // Diagnostics: counts by state only, never content.
                let c = Dictionary(grouping: entries, by: \.statusRaw).mapValues(\.count)
                NSLog("AiHeartUI journal: kept=%d resting=%d released=%d", c["kept"] ?? 0, c["resting"] ?? 0, c["released"] ?? 0)
            }
            #if DEBUG
            .onAppear { if ProcessInfo.processInfo.arguments.contains("-month") { mode = 1 } }
            #endif
        }
    }
}

struct EmptyJournal: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Nothing here yet.")
                .font(.journal(.title3))
                .foregroundStyle(Palette.ink)
            Text("What you put down on Now appears here.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Entries grouped by month, then by anchored day. Days with nothing are simply absent.
struct EntriesList: View {
    let entries: [Entry]
    let dayStart: Int
    let snap: BodySnapshot
    var workoutsByDay: [AnchoredDay: [Workout]] = [:]

    private struct DayGroup: Identifiable {
        let day: AnchoredDay
        let entries: [Entry]
        var id: AnchoredDay { day }
    }

    private struct MonthGroup: Identifiable {
        let year: Int, month: Int
        let days: [DayGroup]
        var id: Int { year * 100 + month }
        var count: Int { days.reduce(0) { $0 + $1.entries.count } }
    }

    private var months: [MonthGroup] {
        let byDay = Dictionary(grouping: entries) { DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: dayStart) }
        let days = byDay.map { DayGroup(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
        let byMonth = Dictionary(grouping: days) { $0.day.year * 100 + $0.day.month }
        return byMonth.map { MonthGroup(year: $0.key / 100, month: $0.key % 100, days: $0.value.sorted { $0.day > $1.day }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            if entries.isEmpty {
                Text("No entries match.")
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
            ForEach(months) { m in
                HStack(alignment: .firstTextBaseline) {
                    Text(monthTitle(m.year, m.month))
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(m.count == 1 ? "1 entry" : "\(m.count) entries")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 4)
                ForEach(m.days) { d in
                    DayRow(day: d.day, entries: d.entries, summary: snap.summary(d.day), cycleDay: snap.cycle?.cycleDay(d.day), workouts: workoutsByDay[d.day] ?? [])
                }
            }
        }
    }

    private func monthTitle(_ y: Int, _ m: Int) -> String {
        let date = AnchoredDay(year: y, month: m, day: 1).date(in: Calendar.current)
        return date.formatted(.dateTime.month(.wide).year())
    }
}

struct DayRow: View {
    let day: AnchoredDay
    let entries: [Entry]
    var summary: DaySummary?
    var cycleDay: Int?
    var workouts: [Workout] = []

    /// Quiet line above the day: sleep, workouts and steps. Media (M18) joins later.
    private var summaryLine: String? {
        var parts: [String] = []
        if let s = summary?.sleepMin { parts.append("Sleep \(BodyFormat.duration(s))") }
        for w in workouts.sorted(by: { $0.start < $1.start }) {
            parts.append("\(w.kind == .strength ? "Lift" : w.kind.label) \(w.minutes) min")
        }
        if workouts.isEmpty, let st = summary?.steps { parts.append("\(Int(st.rounded()).formatted()) steps") }
        // Several entries in a day (owner, 2026-11-02): say so, and say when they were far apart.
        let kept = entries.filter { $0.status != .released }
        if kept.count >= 2 {
            let mood = DayMood(kept.compactMap { e in e.valence.flatMap { v in e.arousal.map { MoodPoint(valence: v, arousal: $0) } } })
            parts.append("\(kept.count) entries" + (mood?.mixed == true ? ", a mixed day" : ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let date = day.date(in: Calendar.current)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(day.day)")
                    .font(.title.bold())
                    .foregroundStyle(Palette.ink)
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                if let cycleDay {
                    Text("Day \(cycleDay)")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 2)
                }
            }
            .frame(width: 52, alignment: .leading)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 10) {
                if let summaryLine {
                    Text(summaryLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                ForEach(entries) { e in
                    OpenableEntry(entry: e)
                }
            }
        }
    }
}

/// One entry in a list. A tap anywhere on the card opens it (kept, resting or let go);
/// long-press offers Open and Delete. The card's left edge carries its mood color.
/// Route to any entry, whatever its state. Handled once at the stack level.
struct OpenEntryRoute: Hashable {
    let entry: Entry
    static func == (a: Self, b: Self) -> Bool { a.entry.persistentModelID == b.entry.persistentModelID }
    func hash(into h: inout Hasher) { h.combine(entry.persistentModelID) }

    @ViewBuilder var destination: some View {
        switch entry.status {
        case .kept: EntryDetailView(entry: entry)
        case .resting: RestingEntryView(entry: entry)
        case .released: LetGoEntryView(entry: entry)
        }
    }
}

private struct OpenEntryKey: EnvironmentKey { static let defaultValue: ((Entry) -> Void)? = nil }
extension EnvironmentValues {
    var openEntry: ((Entry) -> Void)? {
        get { self[OpenEntryKey.self] }
        set { self[OpenEntryKey.self] = newValue }
    }
}

struct OpenableEntry: View {
    let entry: Entry
    @Environment(\.openEntry) private var openEntry

    private func open() {
        NSLog("AiHeartUI open entry: status=%@ handler=%d", entry.statusRaw, openEntry == nil ? 0 : 1)
        openEntry?(entry)
    }

    var body: some View {
        EntryCard(entry: entry)
            .moodEdge(entry)
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            .modifier(DeleteEntryMenu(entry: entry, onOpen: { open() }))
    }
}

extension View {
    /// The whole card takes the entry's mood color (owner, 2026-11-01).
    func moodEdge(_ entry: Entry) -> some View { modifier(MoodWash(entry: entry)) }
}

/// Mood color over a whole card: her mood point, else the model's tone, else the text
/// reader (lighter). Softer in dark mode so text stays readable.
struct MoodWash: ViewModifier {
    let entry: Entry
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let point: (Double, Double, Bool)? = {
            if let v = entry.valence, let a = entry.arousal { return (v, a, false) }
            if let v = entry.toneValence { return (v, entry.toneArousal ?? 0, true) }
            if let t = entry.text, !t.isEmpty, entry.status == .kept, let v = CaptionTone.valence(t, id: entry.syncId) { return (v, 0, true) }
            return nil
        }()
        if let (v, a, guessed) = point {
            let c = MoodColor.color(valence: v, arousal: a)
            let color = Color(red: c.r, green: c.g, blue: c.b)
            content
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(color.opacity(scheme == .dark ? (guessed ? 0.16 : 0.24) : (guessed ? 0.32 : 0.45)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .accessibilityValue(MoodColor.words(valence: v, arousal: a) + (guessed ? ", guessed from your words" : ""))
        } else {
            content
        }
    }
}

/// Photo entries get a card; words, voice and writing get a compact row;
/// resting and let-go entries show only the lines she kept.
struct EntryCard: View {
    let entry: Entry
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        switch entry.status {
        case .resting: RestingCard(entry: entry)
        case .released: LetGoCard(entry: entry)
        case .kept:
            if let thumb = entry.thumbData, let image = UIImage(data: thumb) {
                photoCard(image)
            } else {
                compactRow
            }
        }
    }

    private func photoCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 200)
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
                .accessibilityLabel("Photo")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.caption ?? entry.word ?? "Photo")
                        .font(.journal(.title3).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                EntryMarks(entry: entry)
            }
            .padding(16)
        }
        .card()
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder private var compactRow: some View {
        if typeSize.isAccessibilitySize {
            // Largest text: icon and time above, words below, nothing squeezed.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).foregroundStyle(Palette.onTint).accessibilityHidden(true)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened)).font(.subheadline).foregroundStyle(Palette.muted)
                }
                Text(title)
                    .font(entry.word != nil && entry.caption == nil ? .title3.weight(.semibold) : .journal(.body))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.muted) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else {
            regularRow
        }
    }

    private var regularRow: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.onTint)
                .frame(width: 52, height: 52)
                .background(Palette.tint1, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(entry.word != nil && entry.caption == nil ? .title3.weight(.semibold) : .journal(.body))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(14)
        .card()
    }

    private var icon: String {
        switch entry.kind {
        case .voice: "mic"
        case .body: "figure.stand.dress"
        case .write: "text.alignleft"
        default: entry.audioData != nil ? "mic" : "circle.fill"
        }
    }

    private var title: String {
        if let w = entry.word, entry.caption == nil { return w }
        if let c = entry.caption { return c }
        if !entry.bodyRegions.isEmpty { return bodySummary(regions: entry.bodyRegions, sensations: entry.sensations) }
        if entry.audioData != nil { return "Voice note" }
        if let v = entry.valence, let a = entry.arousal { return MoodPad.describe(MoodPoint(valence: v, arousal: a)).capitalized }
        return "Entry"
    }

    private var subtitle: String? {
        var parts: [String] = []
        if entry.caption != nil, let w = entry.word { parts.append(w) }
        if entry.audioData != nil { parts.append("Voice note · \(formatDuration(entry.audioSeconds ?? 0))") }
        if !entry.bodyRegions.isEmpty, title != bodySummary(regions: entry.bodyRegions, sensations: entry.sensations) {
            parts.append(bodySummary(regions: entry.bodyRegions, sensations: entry.sensations))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Her word, a tiny mood pad and a tiny body glow.
struct EntryMarks: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 10) {
            if let w = entry.word { TintLabel(text: w) }
            if !entry.bodyRegions.isEmpty {
                let regions = Set(entry.bodyRegions.compactMap(BodyRegion.init(rawValue:)))
                BodyFigureView(selected: regions, side: BodyRegion.bestSide(for: regions), pulse: false)
                    .frame(height: 40)
                    .accessibilityLabel(entry.bodyRegions.map(BodyRegion.label(for:)).joined(separator: ", "))
            }
        }
    }
}

struct RestingCard: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TintLabel(text: restLabel, tint: Palette.lilacBand, ink: Palette.ink)
            KeptLines(lines: entry.keptLines)
            HStack(alignment: .firstTextBaseline) {
                Text(entry.decidedBy == .auto ? "AiHeart let this one go." : "You let this one go.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Spacer()
                BringBackButton(entry: entry)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var restLabel: String {
        guard let until = entry.restUntil else { return "Resting" }
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: until).day ?? 0)
        return days == 1 ? "Resting · 1 day" : "Resting · \(days) days"
    }
}

struct LetGoCard: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TintLabel(text: entry.keepNumbers ? "Let go · numbers kept" : "Let go", tint: Palette.flameTint, ink: Palette.onFlameTint)
            KeptLines(lines: entry.keptLines)
            Text("The rest is gone.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct KeptLines: View {
    let lines: [String]
    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { Text($0).font(.journal(.body)).italic().foregroundStyle(Palette.ink) }
            }
        }
    }
}

struct BringBackButton: View {
    let entry: Entry
    @Environment(\.modelContext) private var context

    var body: some View {
        Button("Bring it back") {
            try? EntryLifecycle.bringBack(entry)
            try? context.save()
        }
        .font(.headline)
        .foregroundStyle(Palette.onTint)
        .frame(minHeight: 44)
    }
}


/// Recently deleted (owner, 2026-11-04; docs/22): entries she deleted, for 30 days. Restore puts one
/// back exactly as it was; Delete now removes it for good.
struct RecentlyDeletedView: View {
    @Query(sort: \DeletedEntry.deletedAt, order: .reverse) private var rows: [DeletedEntry]
    @Environment(\.modelContext) private var context
    @State private var confirm: DeletedEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Entries you delete stay here for 30 days, then they are gone for good.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if rows.isEmpty {
                    Text("Nothing here.").foregroundStyle(Palette.muted).frame(maxWidth: .infinity, minHeight: 120)
                }
                ForEach(rows) { d in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(d.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                        Text(d.preview.isEmpty ? "(no words)" : d.preview).font(.journal(.body)).foregroundStyle(Palette.ink).lineLimit(3)
                        HStack(spacing: 20) {
                            Button("Restore") {
                                RecentlyDeleted.restore(d, in: context)
                                NSLog("AiHeartUI restored a deleted entry")
                            }
                            .font(.headline).foregroundStyle(Palette.onTint)
                            Button("Delete now", role: .destructive) { confirm = d }
                            Spacer()
                            let left = RecentlyDeleted.daysLeft(d)
                            Text("\(left) day\(left == 1 ? "" : "s") left").font(.caption).foregroundStyle(Palette.muted)
                        }
                        .frame(minHeight: 44)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                }
            }
            .padding(20)
        }
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("Recently deleted")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete for good?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Delete for good", role: .destructive) { if let d = confirm { RecentlyDeleted.purge(d, in: context) }; confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text("This one cannot be brought back.") }
    }
}

import NaturalLanguage
import AiHeartCore
import SwiftUI

/// Journal · Month (screen 12). Photo days show a thumbnail, feeling-only days a dot,
/// the selected day is ringed, and a thin bar under each day shows the estimated cycle phase.
struct MonthView: View {
    let entries: [Entry]
    let dayStart: Int
    let snap: BodySnapshot
    @State private var monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var selected: AnchoredDay?

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday, as drawn
        return c
    }

    private var byDay: [AnchoredDay: [Entry]] {
        Dictionary(grouping: entries) { DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: dayStart) }
    }

    var body: some View {
        let groups = byDay
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 14) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous month")
                    Spacer()
                    Text(monthStart.formatted(.dateTime.month(.wide).year()))
                        .font(.title3.bold())
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("Next month")
                }
                .foregroundStyle(Palette.onTint)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                    // Indexed: the symbols repeat (T, S), so they cannot be their own ids.
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(day: day, entries: groups[day] ?? [], selected: selected == day, phase: snap.cycle?.phase(day))
                                .onTapGesture { if groups[day] != nil { selected = day } }
                        } else {
                            Color.clear.frame(height: 64)
                        }
                    }
                }

            }
            .padding(16)
            .card()

            if let selected, let list = groups[selected] {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.date(in: .current).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title3.bold())
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(list.count == 1 ? "1 entry" : "\(list.count) entries")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                ForEach(list.sorted { $0.createdAt > $1.createdAt }) { e in
                    OpenableEntry(entry: e)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-prevMonth") { shift(-1) }
            #endif
            if selected == nil {
                let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: dayStart)
                if byDay[today] != nil { selected = today }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        return Array(s[1...] + s[..<1])
    }

    private var cells: [AnchoredDay?] {
        let comps = cal.dateComponents([.year, .month], from: monthStart)
        let range = cal.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let weekday = cal.component(.weekday, from: monthStart) // 1 = Sunday
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading)
            + range.map { AnchoredDay(year: comps.year ?? 0, month: comps.month ?? 0, day: $0) }
    }

    private func shift(_ by: Int) {
        if let d = cal.date(byAdding: .month, value: by, to: monthStart) { monthStart = d }
    }
}

struct DayCell: View {
    let day: AnchoredDay
    let entries: [Entry]
    let selected: Bool
    var phase: CyclePhase?

    private var kept: [Entry] { entries.filter { $0.status != .released } }

    /// All of the day's mood points (owner, 2026-11-02: several entries a day).
    private var dayMood: DayMood? {
        DayMood(kept.compactMap { e in e.valence.flatMap { v in e.arousal.map { MoodPoint(valence: v, arousal: $0) } } })
    }

    /// Mean mood point of the day, as a color.
    private var moodPoint: (Double, Double)? { dayMood.map { ($0.valence, $0.arousal) } }

    /// Tone read from captions or text when no entry that day has a mood point. A guess,
    /// so it is drawn dashed. Read on the phone (NaturalLanguage); nothing leaves it.
    private var guessedValence: Double? {
        guard moodPoint == nil else { return nil }
        let tones = kept.compactMap { e in e.toneValence ?? (e.text?.isEmpty == false ? e.text : nil).flatMap { CaptionTone.valence($0, id: e.syncId) } }
        guard !tones.isEmpty else { return nil }
        return tones.reduce(0, +) / Double(tones.count)
    }

    private var mood: MoodColor.RGB? {
        if let p = moodPoint { return MoodColor.color(valence: p.0, arousal: p.1) }
        return guessedValence.map { MoodColor.color(valence: $0, arousal: kept.compactMap(\.toneArousal).first ?? 0) }
    }
    private var moodGuessed: Bool { moodPoint == nil && guessedValence != nil }

    /// 0...1: how strongly the day glows. Strong pleasant days glow most (more so when
    /// stirred); unpleasant days stay pale. Owner, 2026-11-01.
    private var intensity: Double {
        let v = moodPoint?.0 ?? guessedValence ?? 0
        let a = moodPoint?.1 ?? kept.compactMap(\.toneArousal).first ?? 0
        let pleasant = max(0, min(1, (v + 1) / 2))
        return pow(pleasant, 1.6) * (0.75 + 0.25 * (a + 1) / 2)
    }

    /// She wrote something that day (or kept lines from it).
    private var wrote: Bool { kept.contains { !($0.text ?? "").isEmpty || !$0.keptLines.isEmpty } }

    private var photo: UIImage? {
        entries.lazy.compactMap { $0.status == .kept ? $0.thumbData : nil }.first.flatMap(UIImage.init(data:))
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(day.day)")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
            ZStack {
                if let photo {
                    // Full-size photo with a soft glow in the day's mood color.
                    let glow = mood.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay {
                            if let glow { Circle().strokeBorder(glow.opacity(0.35 + 0.65 * intensity), lineWidth: 2) }
                        }
                        .shadow(color: (glow ?? .clear).opacity(0.15 + 0.85 * intensity), radius: 3 + 5 * intensity)
                        .shadow(color: (glow ?? .clear).opacity(0.75 * intensity), radius: 6 + 8 * intensity)
                } else if let mood {
                    let c = Color(red: mood.r, green: mood.g, blue: mood.b)
                    Circle().fill(c.opacity(0.4 + 0.6 * intensity))
                        .frame(width: 40, height: 40)
                        .shadow(color: c.opacity(0.7 * intensity), radius: 2 + 6 * intensity)
                } else if !entries.isEmpty {
                    Circle().fill(Palette.card).overlay(Circle().stroke(Palette.line))
                        .frame(width: 40, height: 40)
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                if selected {
                    Circle().stroke(Palette.action, lineWidth: 2.5).frame(width: 46, height: 46)
                }
                if let m = dayMood, m.mixed {
                    // A mixed day: the mean color hides the low point, so it shows as a small dot.
                    let low = MoodColor.color(valence: m.lowest.valence, arousal: m.lowest.arousal)
                    Circle().fill(Color(red: low.r, green: low.g, blue: low.b))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Palette.surface, lineWidth: 1.5))
                        .offset(x: -16, y: 16)
                }
                if wrote {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.onAction)
                        .frame(width: 17, height: 17)
                        .background(Palette.action, in: Circle())
                        .overlay(Circle().stroke(Palette.surface, lineWidth: 1.5))
                        .offset(x: 16, y: -16)
                }
            }
            .frame(width: 46, height: 46)
            Capsule()
                .fill(phase?.color ?? .clear)
                .frame(width: 26, height: 4)
        }
        .frame(minHeight: 70)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : (entries.isEmpty ? [] : .isButton))
    }

    private var accessibility: String {
        let date = day.date(in: .current).formatted(.dateTime.day().month(.wide))
        let p = phase.map { ", \($0.rawValue) phase" } ?? ""
        if entries.isEmpty { return date + p }
        let m = (moodPoint.map { ", felt \(MoodColor.words(valence: $0.0, arousal: $0.1))" } ?? "") + (dayMood?.mixed == true ? ", a mixed day" : "")
        return "\(date), \(entries.count == 1 ? "1 entry" : "\(entries.count) entries")\(photo != nil ? ", with a photo" : "")\(wrote ? ", with writing" : "")\(m)\(p)"
    }
}

/// On-device tone of a caption or entry text, −1 to 1. Cached per entry and text.
enum CaptionTone {
    @MainActor private static var cache: [String: Double?] = [:]

    /// Feeling words in English, Japanese and Tagalog, with a rough valence.
    static let lexicon: [String: Double] = [
        "happy": 0.7, "great": 0.6, "good": 0.4, "fun": 0.6, "love": 0.7, "loved": 0.7, "amazing": 0.8, "excited": 0.7,
        "grateful": 0.6, "thankful": 0.6, "proud": 0.6, "calm": 0.5, "peaceful": 0.6, "relaxed": 0.5, "nice": 0.4,
        "beautiful": 0.6, "best": 0.7, "glad": 0.5, "enjoyed": 0.6, "yay": 0.7, "content": 0.5, "cozy": 0.5,
        "sad": -0.6, "tired": -0.3, "angry": -0.6, "upset": -0.6, "anxious": -0.5, "stressed": -0.5, "lonely": -0.6,
        "bad": -0.5, "awful": -0.8, "worried": -0.5, "hurt": -0.6, "cried": -0.6, "exhausted": -0.5, "sick": -0.4,
        "楽しい": 0.7, "嬉しい": 0.7, "うれしい": 0.7, "幸せ": 0.8, "最高": 0.8, "良い": 0.4, "いい": 0.3, "好き": 0.6,
        "落ち着": 0.5, "感謝": 0.6, "悲しい": -0.6, "疲れ": -0.3, "辛い": -0.6, "つらい": -0.6, "不安": -0.5, "怒": -0.6,
        "寂しい": -0.6, "しんどい": -0.5,
        "masaya": 0.7, "saya": 0.6, "ang saya": 0.8, "sarap": 0.6, "ganda": 0.5, "salamat": 0.5, "kilig": 0.7,
        "malungkot": -0.6, "pagod": -0.3, "galit": -0.6, "nakakainis": -0.5, "lungkot": -0.6, "kaba": -0.4,
    ]

    @MainActor static func valence(_ text: String, id: UUID) -> Double? {
        let key = "\(id)|\(text.hashValue)"
        if let hit = cache[key] { return hit }
        var scores: [Double] = []
        // Apple's on-device sentiment, sentence by sentence.
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .sentimentScore) { tag, _ in
            if let v = tag.flatMap({ Double($0.rawValue) }), v != 0 { scores.append(v) }
            return true
        }
        // Her own feeling words, in any of her languages.
        let lower = text.lowercased()
        for (w, v) in lexicon where lower.contains(w) { scores.append(v) }
        let out: Double? = scores.isEmpty ? nil : max(-1, min(1, scores.reduce(0, +) / Double(scores.count)))
        cache[key] = out
        return out
    }
}

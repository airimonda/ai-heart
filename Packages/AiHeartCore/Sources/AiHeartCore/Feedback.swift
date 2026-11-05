import Foundation
import SwiftData

// Feedback (owner, 2026-10-31): on the app's guesses (mood lean, suggested words, photo
// words), and on the app itself. Kept on her devices. The app learns only in plain,
// visible ways: a lean that keeps missing pauses itself; words she never picks give way.

/// One record per guess she answered, or per guess checked against her own entries.
@Model
public final class GuessFeedback {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""
    /// "lean", "words", "photoWords".
    public var kind: String = ""
    public var dayKey: String = ""
    /// For the lean: "morePleasant" | "lessPleasant" | "usual".
    public var guess: String?
    /// Her answer: true fits, false does not, nil not answered.
    public var fit: Bool?
    /// For words: the words shown, and the one she picked (nil if none fit).
    @Attribute(.allowsCloudEncryption) public var shown: [String] = []
    @Attribute(.allowsCloudEncryption) public var picked: String?

    public init(kind: String, day: AnchoredDay) {
        self.kind = kind
        self.dayKey = day.key
    }
}

/// Her notes about the app itself. Shared only if she exports them.
@Model
public final class AppFeedback {
    public var syncId: UUID = UUID()
    public var createdAt: Date = Date()
    @Attribute(.allowsCloudEncryption) public var text: String = ""
    public var mood: String?

    public init(text: String, mood: String?) {
        self.text = text
        self.mood = mood
    }
}

public enum LeanRecord {
    public static let minAnswers = 10

    public struct Summary: Equatable, Sendable {
        public let answered: Int
        public let fit: Int
        /// Days where her own logged mood could be compared with the lean.
        public let checked: Int
        public let matched: Int
        /// True once it has missed more than it fit over enough days.
        public var paused: Bool { answered >= minAnswers && Double(fit) / Double(answered) < 0.5 }

        public init(answered: Int, fit: Int, checked: Int, matched: Int) {
            self.answered = answered; self.fit = fit; self.checked = checked; self.matched = matched
        }
    }

    /// - Parameters:
    ///   - leans: the lean shown each day.
    ///   - answers: her fits / doesn't fit, by day.
    ///   - mood: her mean pleasantness per day, from entries.
    ///   - usual: her usual pleasantness (median over the same days).
    public static func summarize(leans: [AnchoredDay: MoodLean.Direction], answers: [AnchoredDay: Bool],
                                 mood: [AnchoredDay: Double], usual: Double) -> Summary {
        let answered = answers.count
        let fit = answers.values.filter { $0 }.count
        var checked = 0, matched = 0
        for (day, dir) in leans {
            guard let m = mood[day] else { continue }
            checked += 1
            let actual: MoodLean.Direction = m > usual + 0.15 ? .morePleasant : m < usual - 0.15 ? .lessPleasant : .usual
            if actual == dir { matched += 1 }
        }
        return Summary(answered: answered, fit: fit, checked: checked, matched: matched)
    }

    public static func text(_ s: Summary) -> String? {
        var parts: [String] = []
        func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
        if s.answered > 0 { parts.append("Fit on \(s.fit) of \(days(s.answered)) you answered") }
        if s.checked > 0 { parts.append("matched your entries on \(s.matched) of \(days(s.checked))") }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: "; ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + "."
    }
}

public enum WordPreference {
    /// The four quadrants of the pad, each with the words that can stand for it.
    public static let quadrants: [[String]] = [
        ["Wired", "Tense", "Restless"],
        ["Tired", "Heavy", "Flat", "Low"],
        ["Bright", "Excited"],
        ["Calm", "Content", "Okay"],
    ]

    /// Replaces a suggested word with another from the same quadrant when she has picked
    /// that one clearly more often, and has never picked the suggested one despite seeing
    /// it several times. Keeps the set balanced: still one word per quadrant.
    public static func adjust(_ words: [String], picks: [String: Int], shown: [String: Int]) -> [String] {
        words.map { w in
            guard let q = quadrants.first(where: { $0.contains(w) }) else { return w }
            let neverPicked = (picks[w] ?? 0) == 0 && (shown[w] ?? 0) >= 5
            guard neverPicked, let better = q.filter({ $0 != w && !words.contains($0) })
                .max(by: { (picks[$0] ?? 0) < (picks[$1] ?? 0) }), (picks[better] ?? 0) >= 2 else { return w }
            return better
        }
    }
}

public enum AboutMeProposals {
    public struct Proposal: Equatable, Sendable, Identifiable {
        /// Stable across updates of the numbers, so a dismissal sticks.
        public let id: String
        public let text: String
        public init(id: String, text: String) { self.id = id; self.text = text }
    }

    public static let sectionTitle = "Noticed by AiHeart, added by me"

    public static func make(links: [Patterns.Link], lift: [Patterns.Group], phases: [Patterns.Group],
                            keptLines: [String], words: [(String, Int)]) -> [Proposal] {
        var out: [Proposal] = []
        let names: [String: (up: String, down: String, lagWord: String)] = [
            "Sleep": ("Longer sleep", "Shorter sleep", "days"),
            "Resting HR": ("A higher resting heart rate", "A lower resting heart rate", "next days"),
            "HRV": ("A higher HRV", "A lower HRV", "next days"),
            "Wrist temp": ("A warmer wrist temperature", "A cooler wrist temperature", "next days"),
            "Steps": ("More steps", "Fewer steps", "next days"),
            "Training load": ("More training", "Less training", "next days"),
        ]
        for l in links {
            guard let iv = l.interval, iv.excludesZero, let n = names[l.title] else { continue }
            let text = "\(n.up) went with \(iv.estimate > 0 ? "more" : "less") pleasant \(n.lagWord) for me (\(iv.n) days, clearer than chance)."
            out.append(Proposal(id: "link:\(l.title):\(iv.estimate > 0 ? "+" : "-")", text: text))
        }
        if lift.count == 2, let a = lift[0].interval, let b = lift[1].interval, a.low > b.high || b.low > a.high {
            let word = a.estimate > b.estimate ? "more" : "less"
            out.append(Proposal(id: "lift:\(word)", text: "Days I lifted were \(word) pleasant on average (\(a.n + b.n) days)."))
        }
        let ready = phases.filter { $0.interval != nil }
        if ready.count >= 3, let low = ready.min(by: { $0.interval!.estimate < $1.interval!.estimate }),
           ready.filter({ $0.id != low.id }).allSatisfy({ $0.interval!.low > low.interval!.high }) {
            out.append(Proposal(id: "phase:\(low.label)", text: "\(low.label) days were less pleasant for me on average (\(low.n) days)."))
        }
        var counts: [String: (String, Int)] = [:]
        for line in keptLines {
            let k = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            counts[k] = (counts[k]?.0 ?? line, (counts[k]?.1 ?? 0) + 1)
        }
        for (k, v) in counts where v.1 >= 2 {
            out.append(Proposal(id: "helped:\(stableHash(k))", text: "Something that has helped me: \(v.0)"))
        }
        for (w, c) in words.prefix(2) where c >= 10 {
            out.append(Proposal(id: "word:\(w.lowercased())", text: "A word I often use for how I feel: \(w) (\(c) times)."))
        }
        return out
    }

    /// FNV-1a, so ids for her own lines carry no readable content.
    public static func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Adds one line to the "noticed" section of About me.
    public static func add(_ p: Proposal, to doc: AboutMeDoc) -> AboutMeDoc {
        var d = doc
        let line = "- " + p.text
        if let i = d.sections.firstIndex(where: { $0.title == sectionTitle }) {
            if !d.sections[i].body.contains(p.text) {
                d.sections[i].body = d.sections[i].body.isEmpty ? line : d.sections[i].body + "\n" + line
            }
        } else {
            d.sections.append(.init(title: sectionTitle, body: line))
        }
        return d
    }
}

/// About me proposals written by the language model (owner, 2026-10-31). Runs only when she
/// asks, from her kept writing and her clear findings. Every line is checked on its own;
/// she adds or dismisses each one.
public enum AboutMeWriter {
    public static let system = """
    You help a person add a few lines to a private page about herself. Write in the first \
    person, as her, plainly. Use only what is given. Never diagnose, never label a state, \
    never give advice, never reassure, never name other people. One line per proposal.
    """

    public static func prompt(findings: [String], entries: [String], existing: String) -> String {
        """
        What her own data shows clearly:
        \(findings.isEmpty ? "(nothing clear yet)" : findings.map { "- " + $0 }.joined(separator: "\n"))

        Some of her recent entries:
        \(entries.map { "- " + $0 }.joined(separator: "\n"))

        Already on her page (do not repeat):
        \(existing.isEmpty ? "(empty)" : existing)

        Write up to three short lines, under 20 words each, that she might add to her page \
        about herself: things she seems to notice, value, or return to. One line each, no numbering.
        """
    }

    /// Splits the reply into candidate lines and keeps only those that pass the checks.
    public static func lines(from raw: String, policy: OutputPolicy, existing: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "^[-*•\\d.)\\s]+", with: "", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.split(separator: " ").count <= 24 }
            .filter { OutputValidator.check($0, policy).isEmpty }
            .filter { !existing.localizedCaseInsensitiveContains($0) }
            .prefix(3).map { $0 }
    }

    /// Entries she has kept, trimmed, never touching a quiet topic.
    public static func entryLines(_ texts: [(word: String?, text: String?)], quietTopics: [String], limit: Int = 40, maxChars: Int = 2400) -> [String] {
        var out: [String] = []
        var total = 0
        for t in texts.reversed() {
            let body = [t.word, t.text].compactMap { $0 }.joined(separator: ": ")
            guard !body.isEmpty else { continue }
            let lower = body.lowercased()
            // An entry that mentions hurting yourself is never sent to the cloud, so it is not used here.
            if CloudGate.blocks(body) { continue }
            if quietTopics.contains(where: { !$0.isEmpty && lower.contains($0.lowercased()) }) { continue }
            let line = String(body.prefix(160))
            if total + line.count > maxChars || out.count >= limit { break }
            out.append(line); total += line.count
        }
        return out
    }
}

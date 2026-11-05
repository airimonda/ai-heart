import Foundation
import SwiftData

// Hard moments (owner, 2026-11-02; docs/15). "Something to try": a fixed, evidence-labeled menu of
// things she can do when it is hard (grounding, breathing, body, reframing, moving). The model never
// writes, picks or changes these. She says what it is like by tapping one of four plain options; the
// app never infers or names her state. Her own notes, written on a steady day, always come first.

/// What it is like right now, in her words. A tap, never a guess by the app.
public enum HardState: String, CaseIterable, Codable, Sendable, Identifiable {
    case fast, heavy, loop, flooded
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: "Fast"
        case .heavy: "Heavy"
        case .loop: "Stuck on a thought"
        case .flooded: "Too much"
        }
    }

    public var detail: String {
        switch self {
        case .fast: "Racing, wired, cannot settle."
        case .heavy: "Slow, flat, low."
        case .loop: "The same thought keeps coming back."
        case .flooded: "Flooded. The past feels close."
        }
    }

    public var icon: String {
        switch self {
        case .fast: "hare"
        case .heavy: "cloud"
        case .loop: "arrow.triangle.2.circlepath"
        case .flooded: "water.waves"
        }
    }
}

/// How much research stands behind a technique, in the words of docs/12.
public enum EvidenceStrength: String, Codable, Sendable {
    case moderate, limited, judgment

    public var label: String {
        switch self {
        case .moderate: "Moderate evidence"
        case .limited: "Limited evidence"
        case .judgment: "Design judgment, not research"
        }
    }
}

public struct Technique: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let minutes: Int
    /// Literal, numbered, one action each. Shown one at a time.
    public let steps: [String]
    /// Seconds for a step that runs on a timer (breathing). nil = she taps Next.
    public let stepSeconds: Int?
    public let strength: EvidenceStrength
    /// One plain line: what the research found and its limit.
    public let evidence: String
    /// Where it fits, in order of how well.
    public let fits: [HardState]
    /// Some steps ask her to write. Those answers stay on the screen unless she keeps them.
    public let writes: Bool
}

public enum HardMoments {
    /// Fixed catalog. Edit only with a source in docs/15.
    public static let catalog: [Technique] = [
        Technique(
            id: "sigh", title: "Long breath out", summary: "Two breaths in through the nose, one long breath out.", minutes: 5,
            steps: [
                "Sit or lie down. Your eyes can stay open.",
                "Breathe in through your nose.",
                "At the top, take one more short breath in through your nose.",
                "Breathe out slowly through your mouth, longer than the breath in.",
                "Repeat for five minutes. The timer runs. Stop any time.",
            ],
            stepSeconds: 300, strength: .moderate,
            evidence: "Five minutes a day of this breathing lifted mood and lowered anxiety a bit more than mindfulness in a one-month trial (Balban 2023). Healthy adults only.",
            fits: [.fast, .flooded, .loop], writes: false),
        Technique(
            id: "tense", title: "Tense and let go", summary: "Tighten one part of the body, then let it go.", minutes: 8,
            steps: [
                "Make fists. Hold for 5 seconds. Let go and notice the difference for 10 seconds.",
                "Lift your shoulders to your ears. Hold for 5. Let go for 10.",
                "Scrunch your face. Hold for 5. Let go for 10.",
                "Press your feet into the floor. Hold for 5. Let go for 10.",
                "Tighten your stomach. Hold for 5. Let go for 10.",
                "Sit for a moment and notice what is looser.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "Progressive muscle relaxation lowered stress and anxiety in a 2024 review of 14 studies. Effects ranged from small to large and quality varied.",
            fits: [.fast, .flooded], writes: false),
        Technique(
            id: "senses", title: "Name what is around you", summary: "Bring attention to the room you are in now.", minutes: 3,
            steps: [
                "Say or type 5 things you can see.",
                "4 things you can touch. Touch them.",
                "3 things you can hear.",
                "2 things you can smell, or 2 smells you like.",
                "1 thing you can taste, or 1 slow sip of water.",
                "Say today's date and where you are.",
            ],
            stepSeconds: nil, strength: .limited,
            evidence: "A common grounding script. Very little trial evidence for this script itself.",
            fits: [.flooded, .fast], writes: false),
        Technique(
            id: "defuse", title: "Let the thought be a thought", summary: "Notice it without arguing with it or checking it.", minutes: 3,
            steps: [
                "Put the thought in a few words.",
                "Say it again, starting with: \u{201C}I am having the thought that \u{2026}\u{201D}",
                "Now: \u{201C}I notice I am having the thought that \u{2026}\u{201D}",
                "Do not argue with it, check it, or ask anyone if it is true. Let it be there.",
                "Turn to one small thing in front of you, with the thought still there.",
            ],
            stepSeconds: nil, strength: .limited,
            evidence: "In lab studies, stepping back from a thought did better than distraction and about as well as arguing with it. Arguing and checking can turn into a loop of their own.",
            fits: [.loop], writes: false),
        Technique(
            id: "reframe", title: "Check the thought", summary: "Five questions. You write the answers; nothing is written for you.", minutes: 10,
            steps: [
                "What is the thought, in one line?",
                "What supports it? Facts only.",
                "What does not fit with it?",
                "If a friend had this thought, what would you tell them?",
                "Another way to see it, in your words. It does not have to be positive.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "Checking thoughts (cognitive restructuring) is a core part of CBT for low mood and anxiety. It has not beaten simpler methods, and self-guided single-use evidence is thin.",
            fits: [.heavy], writes: true),
        Technique(
            id: "distance", title: "Step back from it", summary: "Write about it using your name instead of \u{201C}I\u{201D}.", minutes: 5,
            steps: [
                "Write one or two lines about what is happening, using your own name or \u{201C}you\u{201D} instead of \u{201C}I\u{201D}.",
                "Write how [your name] feels right now, still without \u{201C}I\u{201D}.",
                "Write what [your name] already knows about moments like this.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "Talking or writing about yourself from a distance lowered distress across 48 studies. Most were short lab tasks.",
            fits: [.heavy, .fast], writes: true),
        Technique(
            id: "walk", title: "Move a little", summary: "A 10 to 20 minute walk, at a pace you can talk at.", minutes: 15,
            steps: [
                "Put on shoes. That counts as a start.",
                "Walk for 10 to 20 minutes at a pace you can still talk at.",
                "If it is late, keep it easy. A hard workout late at night can cost sleep.",
                "When you are back, notice one thing in your body.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "One session of exercise lowers anxiety a little (small to moderate in reviews). Regular activity lowers low mood about as much as therapy (Singh 2023, 1,039 trials).",
            fits: [.heavy, .fast], writes: false),
        Technique(
            id: "tiny", title: "One small thing", summary: "Pick one task that takes two minutes, and do only that.", minutes: 2,
            steps: [
                "Pick one: drink water, open a window, wash your face, put one thing away, step outside.",
                "Do only that one.",
                "Notice that it is done.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "Doing small planned activities (behavioral activation) helps low mood about as much as CBT in reviews. From background knowledge; not re-checked in this research.",
            fits: [.heavy], writes: false),
        Technique(
            id: "sleep", title: "Protect tonight\u{2019}s sleep", summary: "Keep tonight steady. Big decisions wait until after sleep.", minutes: 2,
            steps: [
                "Keep your usual bedtime and wake time tonight.",
                "Dim the lights and screens an hour before bed.",
                "Write down any big idea or decision. It can wait until after you have slept.",
                "Skip caffeine and hard workouts for the rest of the day.",
            ],
            stepSeconds: nil, strength: .moderate,
            evidence: "Sleep loss is the most reported trigger of mood episodes (n = 3,140). Keeping daily rhythms regular reduced new episodes in a trial of rhythm therapy.",
            fits: [.fast], writes: false),
        Technique(
            id: "quiet", title: "Less input", summary: "Fewer sounds, less light, fewer words.", minutes: 5,
            steps: [
                "Lower the lights or close your eyes.",
                "Put on headphones or ear plugs, or move somewhere quieter.",
                "You do not have to talk or explain. Sit for five minutes.",
                "Hold something heavy or soft, if that helps.",
            ],
            stepSeconds: nil, strength: .judgment,
            evidence: "Taking sensory input down is a common support for overload and shutdown. No trials were found for it.",
            fits: [.flooded, .fast], writes: false),
    ]

    public static func technique(_ id: String) -> Technique? { catalog.first { $0.id == id } }

    /// Her results with a technique, from her own tries. Shown only once she has `minTries`.
    public struct Result: Equatable, Sendable {
        public let tries: Int
        /// Mean of (before - after) on a 0 to 10 scale. Positive = it eased.
        public let meanDrop: Double
    }

    public static let minTries = 3

    /// Her own mean change per technique for one state, only for techniques with enough rated tries.
    public static func results(_ tries: [TechniqueTry], state: HardState) -> [String: Result] {
        var byId: [String: [Double]] = [:]
        for t in tries where t.stateRaw == state.rawValue {
            guard let b = t.before, let a = t.after else { continue }
            byId[t.techniqueId, default: []].append(Double(b - a))
        }
        return byId.compactMapValues { d in
            d.count >= minTries ? Result(tries: d.count, meanDrop: d.reduce(0, +) / Double(d.count)) : nil
        }
    }

    /// What to show for a state: at most `limit` techniques. Order: those that eased it for her
    /// (enough tries, mean drop >= 1) by her mean drop; then the fixed order of fit; then what did not
    /// ease it for her, last. Nothing is hidden: "More" shows the rest.
    public static func offers(for state: HardState, tries: [TechniqueTry], limit: Int = 3) -> (shown: [Technique], more: [Technique]) {
        let mine = results(tries, state: state)
        let fitting = catalog.filter { $0.fits.contains(state) }
            .sorted { ($0.fits.firstIndex(of: state) ?? 9) < ($1.fits.firstIndex(of: state) ?? 9) }
        let helped = fitting.filter { (mine[$0.id]?.meanDrop ?? 0) >= 1 }
            .sorted { mine[$0.id]!.meanDrop > mine[$1.id]!.meanDrop }
        let didNot = fitting.filter { mine[$0.id].map { $0.meanDrop < 1 } ?? false }
        let untried = fitting.filter { mine[$0.id] == nil }
        let ordered = helped + untried + didNot
        let rest = catalog.filter { !$0.fits.contains(state) }
        return (Array(ordered.prefix(limit)), Array(ordered.dropFirst(limit)) + rest)
    }
}

/// One try of one technique: which, when, for which state, and how strong it felt before and after
/// (0 to 10, both optional). Never what she wrote during it.
@Model
public final class TechniqueTry {
    public var syncId: UUID = UUID()
    public var date: Date = Date()
    public var techniqueId: String = ""
    public var stateRaw: String = HardState.heavy.rawValue
    public var before: Int?
    public var after: Int?
    public var deviceId: String = ""

    public init(date: Date = Date(), techniqueId: String, state: HardState, before: Int? = nil, after: Int? = nil, deviceId: String = "") {
        self.date = date
        self.techniqueId = techniqueId
        self.stateRaw = state.rawValue
        self.before = before
        self.after = after
        self.deviceId = deviceId
    }

    public var state: HardState { HardState(rawValue: stateRaw) ?? .heavy }
}

extension AppSettings {
    /// Her note from a steady day for this state (docs/15). Empty if she has not written one.
    public func steadyNote(for state: HardState) -> String {
        switch state {
        case .fast: steadyFast
        case .heavy: steadyHeavy
        case .loop: steadyLoop
        case .flooded: steadyFlooded
        }
    }

    public func setSteadyNote(_ text: String, for state: HardState) {
        switch state {
        case .fast: steadyFast = text
        case .heavy: steadyHeavy = text
        case .loop: steadyLoop = text
        case .flooded: steadyFlooded = text
        }
        updatedAt = .now
    }
}

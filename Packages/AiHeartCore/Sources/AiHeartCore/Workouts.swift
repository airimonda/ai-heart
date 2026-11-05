import Foundation
import SwiftData

// Training (M5). Workouts come from Apple Health and Hevy; there is no manual logging
// (owner, 2026-10-31). She is asked once per workout for what the sources cannot supply:
// effort (RPE), and optionally focus and a note.

public enum WorkoutKind: String, CaseIterable, Sendable {
    case strength, walk, run, cycle, swim, yoga, hiit, dance, aerobics, other

    public var label: String {
        switch self {
        case .hiit: "HIIT"
        default: rawValue.capitalized
        }
    }

    public var symbol: String {
        switch self {
        case .strength: "dumbbell"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .hiit: "figure.highintensity.intervaltraining"
        case .dance: "figure.dance"
        case .aerobics: "figure.step.training"
        case .other: "figure.mixed.cardio"
        }
    }
}

public enum WorkoutFocus: String, CaseIterable, Sendable {
    case upper, lower, fullBody, push, pull, legs

    public var label: String { self == .fullBody ? "Full body" : rawValue.capitalized }
}

@Model
public final class Workout {
    public var syncId: UUID = UUID()
    public var updatedAt: Date = Date()
    public var deviceId: String = ""

    /// HealthKit workout UUID, when Health has this session.
    public var healthId: String?
    /// Hevy workout id, when Hevy has this session.
    public var hevyId: String?

    public var kindRaw: String = WorkoutKind.other.rawValue
    @Attribute(.allowsCloudEncryption) public var title: String?
    public var start: Date = Date()
    public var durationSec: Double = 0
    @Attribute(.allowsCloudEncryption) public var activeKcal: Double?
    @Attribute(.allowsCloudEncryption) public var avgHR: Double?

    @Attribute(.allowsCloudEncryption) public var rpe: Int?
    @Attribute(.allowsCloudEncryption) public var focusRaw: String?
    @Attribute(.allowsCloudEncryption) public var note: String?
    public var ratedAt: Date?
    /// Set when she was asked to rate it, so she is never asked twice.
    public var promptedAt: Date?

    /// Strava data is display-only and never feeds analysis (CLAUDE.md #6).
    public var aiEligible: Bool = true

    public init(kind: WorkoutKind, start: Date, durationSec: Double) {
        self.kindRaw = kind.rawValue
        self.start = start
        self.durationSec = durationSec
    }

    public var kind: WorkoutKind {
        get { WorkoutKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    public var focus: WorkoutFocus? {
        get { focusRaw.flatMap(WorkoutFocus.init(rawValue:)) }
        set { focusRaw = newValue?.rawValue }
    }

    public var end: Date { start.addingTimeInterval(durationSec) }
    public var minutes: Int { Int((durationSec / 60).rounded()) }
    public var isRated: Bool { rpe != nil }
}

/// One set from Hevy. Linked by `hevyWorkoutId` (string link; CloudKit-friendly).
@Model
public final class HevySet {
    public var syncId: UUID = UUID()
    public var hevyWorkoutId: String = ""
    public var exerciseIndex: Int = 0
    @Attribute(.allowsCloudEncryption) public var exerciseName: String = ""
    public var setIndex: Int = 0
    public var setType: String = "normal"
    @Attribute(.allowsCloudEncryption) public var weightKg: Double?
    @Attribute(.allowsCloudEncryption) public var reps: Int?
    @Attribute(.allowsCloudEncryption) public var rpe: Double?
    @Attribute(.allowsCloudEncryption) public var distanceM: Double?
    @Attribute(.allowsCloudEncryption) public var durationSec: Double?

    public init(hevyWorkoutId: String, exerciseIndex: Int, exerciseName: String, setIndex: Int) {
        self.hevyWorkoutId = hevyWorkoutId
        self.exerciseIndex = exerciseIndex
        self.exerciseName = exerciseName
        self.setIndex = setIndex
    }
}

public enum WorkoutMatch {
    /// Hevy and Health record the same session with slightly different times.
    public static let tolerance: TimeInterval = 10 * 60

    /// True when two sessions overlap, allowing the tolerance at both ends.
    public static func sameSession(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> Bool {
        a.start <= b.end.addingTimeInterval(tolerance) && b.start <= a.end.addingTimeInterval(tolerance)
    }

    /// Pairs each Hevy session with the best-overlapping Health session not yet taken.
    /// Returns (hevyIndex, healthIndex) pairs.
    public static func pairs(hevy: [(start: Date, end: Date)], health: [(start: Date, end: Date)]) -> [(Int, Int)] {
        var taken = Set<Int>()
        var out: [(Int, Int)] = []
        for (i, h) in hevy.enumerated() {
            let candidates = health.enumerated().filter { !taken.contains($0.offset) && sameSession(h, $0.element) }
            guard let best = candidates.max(by: { overlap(h, $0.element) < overlap(h, $1.element) }) else { continue }
            taken.insert(best.offset)
            out.append((i, best.offset))
        }
        return out
    }

    static func overlap(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> TimeInterval {
        max(0, min(a.end, b.end).timeIntervalSince(max(a.start, b.start)))
    }
}

public enum WorkoutPrompt {
    /// Short sessions (a few minutes of walking picked up by the Watch) are not worth a prompt.
    public static let minDuration: TimeInterval = 10 * 60
    /// Only recent sessions: an old one appearing after a first sync is not a reason to ask.
    public static let maxAge: TimeInterval = 24 * 3600

    public static func shouldAsk(_ w: Workout, now: Date = Date(), enabled: Bool, paused: Bool,
                                 minMinutes: Int = 10, hevyHasEffort: Bool = false, skipIfHevyEffort: Bool = true) -> Bool {
        enabled && !paused && !w.isRated && w.promptedAt == nil && w.aiEligible
            && w.durationSec >= max(Double(minMinutes) * 60, 60)
            && !(skipIfHevyEffort && hevyHasEffort)
            && now.timeIntervalSince(w.end) <= maxAge && w.end <= now
    }

    /// Quick answers from the notification (design: WorkoutRating). Effort on the 1 to 10 scale.
    public static let quickAnswers: [(id: String, title: String, rpe: Int)] = [
        ("light", "Light", 3), ("solid", "Solid", 6), ("hard", "Hard", 8),
    ]

    /// Seconds to wait before asking, counted from when the workout ended.
    public static func delay(_ w: Workout, now: Date = Date(), waitMinutes: Int) -> TimeInterval {
        max(1, w.end.addingTimeInterval(Double(waitMinutes) * 60).timeIntervalSince(now))
    }
}

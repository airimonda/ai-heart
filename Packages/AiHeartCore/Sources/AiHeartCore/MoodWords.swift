import Foundation

/// A point on the pleasant/stirred pad. Both axes are -1...1.
public struct MoodPoint: Equatable, Sendable {
    public var valence: Double
    public var arousal: Double

    public init(valence: Double, arousal: Double) {
        self.valence = MoodPoint.clamp(valence)
        self.arousal = MoodPoint.clamp(arousal)
    }

    public static let center = MoodPoint(valence: 0, arousal: 0)

    static func clamp(_ v: Double) -> Double { min(1, max(-1, v)) }
}

public enum MoodWords {
    /// Where each word sits on the pad. Placement is a starting point; she can drag it.
    public static let placements: [String: MoodPoint] = [
        "Wired": MoodPoint(valence: -0.1, arousal: 0.5),
        "Tense": MoodPoint(valence: -0.55, arousal: 0.55),
        "Restless": MoodPoint(valence: -0.3, arousal: 0.45),
        "Excited": MoodPoint(valence: 0.6, arousal: 0.6),
        "Bright": MoodPoint(valence: 0.5, arousal: 0.3),
        "Okay": MoodPoint(valence: 0.1, arousal: 0),
        "Content": MoodPoint(valence: 0.5, arousal: -0.2),
        "Calm": MoodPoint(valence: 0.55, arousal: -0.5),
        "Tired": MoodPoint(valence: -0.25, arousal: -0.6),
        "Heavy": MoodPoint(valence: -0.45, arousal: -0.4),
        "Low": MoodPoint(valence: -0.6, arousal: -0.6),
        "Flat": MoodPoint(valence: -0.15, arousal: -0.35),
    ]

    /// Offline set used until body data exists (M1). Balanced: includes opposites,
    /// one from each quadrant. Nothing is pre-selected.
    public static let staticSuggestions = ["Wired", "Tense", "Tired", "Calm"]

    /// The longer list behind "Another way to describe it".
    public static let more = ["Excited", "Bright", "Okay", "Content", "Restless", "Heavy", "Low", "Flat"]

    public static func point(for word: String) -> MoodPoint? {
        if let p = placements[word] { return p }
        return placements.first { $0.key.caseInsensitiveCompare(word) == .orderedSame }?.value
    }
}

public enum BodySide: String, CaseIterable, Sendable {
    case front, back
}

/// Body regions, top to bottom. Raw values are stored in entries: never rename one.
public enum BodyRegion: String, CaseIterable, Sendable {
    case head, face, throat, neckBack, shoulders, chest, upperBack, stomach, belly, lowerBack, pelvis, hips,
         arms, hands, legs, knees, feet, wholeBody

    public var label: String {
        switch self {
        case .face: "Face and jaw"
        case .neckBack: "Back of neck"
        case .upperBack: "Upper back"
        case .belly: "Lower belly"
        case .lowerBack: "Lower back"
        case .wholeBody: "Whole body"
        default: rawValue.capitalized
        }
    }

    /// Which views of the figure show this region.
    public var sides: Set<BodySide> {
        switch self {
        case .face, .throat, .chest, .stomach, .belly, .pelvis, .knees: [.front]
        case .neckBack, .upperBack, .lowerBack, .hips: [.back]
        default: [.front, .back]
        }
    }

    public static func regions(on side: BodySide) -> [BodyRegion] {
        allCases.filter { $0.sides.contains(side) }
    }

    /// The side that best shows a selection: back only when nothing picked is front-only.
    public static func bestSide(for regions: Set<BodyRegion>) -> BodySide {
        let backOnly = regions.filter { $0.sides == [.back] }.count
        let frontOnly = regions.filter { $0.sides == [.front] }.count
        return backOnly > frontOnly ? .back : .front
    }

    /// Display label for a stored raw value; falls back to the raw text.
    public static func label(for raw: String) -> String {
        BodyRegion(rawValue: raw)?.label ?? raw.capitalized
    }
}

public struct SensationGroup: Sendable, Identifiable {
    public let name: String
    public let words: [String]
    public var id: String { name }
}

/// Plain body words, not labels for states. Grouped so a long list stays easy to scan.
/// Includes easy sensations too, so the list is not only about discomfort.
public enum Sensations {
    public static let groups: [SensationGroup] = [
        SensationGroup(name: "Pressure", words: ["Tight", "Heavy", "Pressing", "Clenched", "Knotted", "Squeezed", "Full", "Stuck"]),
        SensationGroup(name: "Movement", words: ["Buzzing", "Tingling", "Fluttery", "Shaky", "Jittery", "Pulsing", "Racing", "Restless", "Twitchy"]),
        SensationGroup(name: "Temperature", words: ["Warm", "Hot", "Flushed", "Sweaty", "Cold", "Chilly", "Clammy"]),
        SensationGroup(name: "Empty or far", words: ["Hollow", "Numb", "Floaty", "Drained", "Distant", "Foggy", "Faint", "Weak"]),
        SensationGroup(name: "Discomfort", words: ["Achy", "Sore", "Sharp", "Throbbing", "Stiff", "Burning", "Itchy", "Queasy", "Dizzy", "Cramped"]),
        SensationGroup(name: "Ease", words: ["Light", "Soft", "Loose", "Open", "Settled", "Grounded", "Steady", "Spacious", "Rested"]),
    ]

    /// The few shown first, before "More".
    public static let common = ["Tight", "Heavy", "Buzzing", "Numb", "Warm", "Cold", "Hollow", "Light"]

    public static var all: [String] { groups.flatMap(\.words) }
}

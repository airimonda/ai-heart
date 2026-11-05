import Foundation

/// One day's mood from all of that day's entries (owner, 2026-11-02: several entries a day).
///
/// Daily values (patterns, outlook, calendar color) use the mean of the day's mood points, as is
/// usual for repeated mood ratings. A mean alone hides a day with one hard moment among fine ones,
/// so the lowest and highest are kept too, and a day whose points are far apart is "mixed".
public struct DayMood: Equatable, Sendable {
    public let count: Int
    public let valence: Double
    public let arousal: Double
    public let lowest: MoodPoint
    public let highest: MoodPoint

    /// Points at least this far apart in pleasantness (scale -1 to 1) make a mixed day.
    public static let mixedGap = 0.8

    public var mixed: Bool { count >= 2 && highest.valence - lowest.valence >= Self.mixedGap }

    public init?(_ points: [MoodPoint]) {
        guard !points.isEmpty else { return nil }
        count = points.count
        valence = points.map(\.valence).reduce(0, +) / Double(points.count)
        arousal = points.map(\.arousal).reduce(0, +) / Double(points.count)
        lowest = points.min { $0.valence < $1.valence }!
        highest = points.max { $0.valence < $1.valence }!
    }
}

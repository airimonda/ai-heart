import Foundation

/// The week's media vibe as data (owner, 2026-11-02): three mood words, a pleasant/energy
/// point for coloring, and one line. Written by the on-device model in a fixed form.
public struct MediaVibe: Codable, Sendable, Equatable {
    public var tags: [String]
    public var valence: Double
    public var energy: Double
    public var line: String
    public var weekKey: String

    public init(tags: [String], valence: Double, energy: Double, line: String, weekKey: String) {
        self.tags = tags; self.valence = valence; self.energy = energy; self.line = line; self.weekKey = weekKey
    }

    public static let format = """
    Answer in exactly this form, nothing else:
    tags: <three single mood words, comma separated>
    pleasant=<number from -1 to 1> energy=<number from -1 to 1>
    line: <one short sentence about the media's theme and mood>
    """

    /// Lenient parse of the fixed form. Nil when tags or the line are missing.
    public static func parse(_ raw: String, weekKey: String) -> MediaVibe? {
        var tags: [String] = [], line: String?
        for l in raw.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let low = l.lowercased()
            if low.hasPrefix("tags:") {
                tags = l.dropFirst(5).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased() }
                    .filter { !$0.isEmpty && $0.count <= 18 && $0.split(separator: " ").count <= 2 }
            } else if low.hasPrefix("line:") {
                line = l.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }
        let tone = WordTasks.parseTone(raw)
        guard tags.count >= 2, let line, !line.isEmpty else { return nil }
        return MediaVibe(tags: Array(tags.prefix(3)), valence: tone?.valence ?? 0, energy: tone?.arousal ?? 0, line: line, weekKey: weekKey)
    }
}

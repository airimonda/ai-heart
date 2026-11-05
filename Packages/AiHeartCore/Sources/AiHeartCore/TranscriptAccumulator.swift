import Foundation

/// Joins speech results without losing words.
///
/// Apple's on-device recognizer can silently start a fresh transcript after a pause, inside
/// the same task, without marking the old one final. Taking the latest result as "the text"
/// then throws away everything said before the pause (owner, 2026-11-02: about 28 words kept
/// from 105 seconds). This keeps every finished run and adds the current one.
public struct TranscriptAccumulator: Sendable, Equatable {
    public private(set) var done: [String] = []
    public private(set) var current = ""

    public init() {}

    /// The whole text so far.
    public var text: String { (done + (current.isEmpty ? [] : [current])).joined(separator: " ") }

    /// A new result for the current run. If it does not continue the current text, the current text
    /// was a finished run that the recognizer dropped: keep it, then start the new one.
    public mutating func update(_ result: String) {
        let new = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty else { return }
        if !current.isEmpty, Self.isRestart(previous: current, next: new) { done.append(current) }
        current = new
    }

    /// The recognizer said this run is final, or the task ended.
    public mutating func finishRun() {
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { done.append(c) }
        current = ""
    }

    /// A restart is a result that shares no opening with the previous one and is clearly shorter.
    /// Revisions ("I want to go" to "I wanted to go home") keep the opening, so they replace.
    static func isRestart(previous: String, next: String) -> Bool {
        let p = Array(previous.lowercased()), n = Array(next.lowercased())
        let k = min(6, p.count, n.count)
        guard k > 0 else { return false }
        let sameStart = p.prefix(k) == n.prefix(k)
        if sameStart { return false }
        // A first-word fix ("Wean" to "When") is a revision when the lengths stay close.
        return Double(n.count) < Double(p.count) * 0.7
    }
}

import Foundation
import SwiftData

/// One app open, logged by a Shortcuts personal automation she sets up (owner, 2026-11-02).
/// The supported way to count app opens on iPhone (docs/04, CLAUDE.md #12): no Screen Time
/// workaround. Display only, like other media: never statistics, the outlook or a model.
@Model
public final class AppOpen {
    public var syncId: UUID = UUID()
    @Attribute(.allowsCloudEncryption) public var appName: String = ""
    public var date: Date = Date()
    public var deviceId: String = ""

    public init(appName: String, date: Date = Date(), deviceId: String = "") {
        self.appName = appName; self.date = date; self.deviceId = deviceId
    }
}

public enum AppOpenWeek {
    /// Opens per app in the week starting `weekStart` (anchored days), most first.
    /// Opens within 60 seconds of the previous open of the same app count once.
    public static func counts(_ opens: [(app: String, date: Date)], weekStart: AnchoredDay, dayStartHour: Int,
                              timeZone: TimeZone) -> [(app: String, count: Int)] {
        let end = weekStart.adding(days: 7)
        var last: [String: Date] = [:]
        var tally: [String: Int] = [:]
        for o in opens.sorted(by: { $0.date < $1.date }) {
            let d = DayAnchor.day(for: o.date, timeZone: timeZone, dayStartHour: dayStartHour)
            guard d >= weekStart && d < end else { continue }
            let name = o.app.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let l = last[name.lowercased()], o.date.timeIntervalSince(l) < 60 { continue }
            last[name.lowercased()] = o.date
            tally[name, default: 0] += 1
        }
        return tally.map { ($0.key, $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.app < $1.app }
    }
}

import Foundation

// "When I go quiet" (owner, 2026-11-02; docs/15). If she has not logged, talked or typed for longer
// than her own usual gap, one neutral, non-demanding notification offers Something to try, Who I can
// reach, or "Busy, all good". Brief non-demanding contacts after silence are "caring contacts" in
// the research. It never asks her to log, never repeats within one quiet stretch, never escalates.

public enum QuietCheck {
    public static let defaultDays = 3
    public static let minDays = 2
    public static let maxDays = 7
    /// Gaps needed before her own pattern replaces the default.
    public static let minGaps = 8

    public static let body = "A quiet few days. Nothing to catch up on. If it is hard, one tap is enough."

    /// Days of silence before the check-in: the 90th percentile of the gaps between her active days
    /// in the last 90 days, rounded up, plus one, held between 2 and 7. The default is 3 until she
    /// has 8 gaps. So a person who often skips 3 days is not pinged after 3 days.
    public static func thresholdDays(activity: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let since = now.addingTimeInterval(-90 * 86_400)
        let days = Set(activity.filter { $0 >= since && $0 <= now }.map { calendar.startOfDay(for: $0) }).sorted()
        guard days.count > minGaps else { return defaultDays }
        let gaps = zip(days, days.dropFirst()).map { a, b in
            Double(calendar.dateComponents([.day], from: a, to: b).day ?? 1)
        }.sorted()
        guard gaps.count >= minGaps else { return defaultDays }
        let idx = Int((Double(gaps.count - 1) * 0.9).rounded(.up))
        let p90 = Int(gaps[min(idx, gaps.count - 1)].rounded(.up))
        return min(max(p90 + 1, minDays), maxDays)
    }

    /// When to send the one check-in for the current quiet stretch, or nil for none.
    /// - `lastActivity`: her most recent log of any kind. nil (a new install) means no check-in.
    /// - `alreadySentFor`: the lastActivity of the stretch a check-in was already planned for. If it
    ///   matches and that time has passed, this stretch already had its one check-in.
    /// - `plannedAt`: the time planned for that stretch.
    /// Sent at `hour` local time on the first day the silence reaches the threshold.
    public static func fireDate(lastActivity: Date?, thresholdDays: Int, hour: Int, now: Date,
                                enabled: Bool, paused: Bool, alreadySentFor: Date?, plannedAt: Date?,
                                calendar: Calendar = .current) -> Date? {
        guard enabled, !paused, let last = lastActivity else { return nil }
        if let sent = alreadySentFor, abs(sent.timeIntervalSince(last)) < 1, let p = plannedAt, p <= now { return nil }
        let startDay = calendar.startOfDay(for: last)
        guard let day = calendar.date(byAdding: .day, value: thresholdDays, to: startDay),
              var fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
        // Already past (she opened the app but has not logged): the next day at that hour, once.
        if fire <= now {
            guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  let n = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: next) else { return nil }
            let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)
            fire = (today.map { $0 > now } ?? false) ? today! : n
        }
        return fire
    }
}

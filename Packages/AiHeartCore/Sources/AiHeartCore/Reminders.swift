import Foundation

/// The reminder to write (owner's request). Gentle by design: one neutral line, on days and
/// at a time she chose, skipped on a day she already wrote, silent while paused. Planned a
/// week ahead and renewed whenever the app opens, so if she steps away the reminders stop
/// by themselves instead of piling up.
public enum ReminderPlan {
    public static let horizonDays = 7
    public static let body = "Anything to put down?"

    public static func dates(from now: Date, days: Set<Int>, hour: Int, minute: Int,
                             wroteToday: Bool, skipIfWritten: Bool, paused: Bool,
                             calendar: Calendar = .current) -> [Date] {
        guard !paused, !days.isEmpty else { return [] }
        var out: [Date] = []
        let startOfToday = calendar.startOfDay(for: now)
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  days.contains(calendar.component(.weekday, from: day)),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now else { continue }
            if offset == 0 && wroteToday && skipIfWritten { continue }
            out.append(fire)
        }
        return out
    }
}

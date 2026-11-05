import AiHeartCore
import SwiftData
import SwiftUI
import UserNotifications

/// Plans the reminder to write a week ahead. Called when the app opens, after each save,
/// and when she changes the settings.
@MainActor
enum WriteReminder {
    static let prefix = "write-"

    static func reschedule(context: ModelContext) async {
        // Same moments re-plan the quiet check-in (docs/15).
        await QuietCheckIn.reschedule(context: context)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let s = AiHeartStore.settings(in: context)
        guard s.reminderOn else { return }
        let today = DayAnchor.day(for: .now, timeZone: .current, dayStartHour: s.dayStartHour)
        let since = Date().addingTimeInterval(-36 * 3600)
        let entries = (try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt > since }))) ?? []
        let wroteToday = entries.contains { DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: s.dayStartHour) == today }
        let dates = ReminderPlan.dates(from: .now, days: Set(s.reminderDays), hour: s.reminderHour, minute: s.reminderMinute,
                                       wroteToday: wroteToday, skipIfWritten: s.reminderSkipIfWritten, paused: s.pauseEverything)
        for d in dates {
            let content = UNMutableNotificationContent()
            content.title = "AiHeart"
            content.body = ReminderPlan.body
            content.userInfo = ["open": "now"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            try? await center.add(UNNotificationRequest(identifier: prefix + "\(Int(d.timeIntervalSince1970))", content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

/// Small app-wide router for notification taps.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var openNow = false
    /// Something to try / Who I can reach, from a notification or Siri (docs/15).
    var openHardMoments = false
    var openReach = false
    /// "Open my safety plan" from Siri, Shortcuts or the Action button (docs/17).
    var openSafetyPlan = false
}

struct ReminderCard: View {
    @Bindable var s: AppSettings
    @Environment(\.modelContext) private var context

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0, of: .now) ?? .now },
            set: { d in
                s.reminderHour = Calendar.current.component(.hour, from: d)
                s.reminderMinute = Calendar.current.component(.minute, from: d)
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            RuleToggle(title: "Remind me to write", subtitle: "One quiet line, \"\(ReminderPlan.body)\" No streaks, nothing missed.", isOn: $s.reminderOn)
            if s.reminderOn {
                Divider().overlay(Palette.line).padding(.leading, 18)
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                Divider().overlay(Palette.line).padding(.leading, 18)
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        let on = s.reminderDays.contains(d)
                        Button {
                            if on { s.reminderDays.removeAll { $0 == d } } else { s.reminderDays = (s.reminderDays + [d]).sorted() }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[d - 1])
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(on ? Palette.onAction : Palette.ink)
                                .frame(width: 40, height: 44)
                                .background(on ? Palette.action : Palette.segment, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                Divider().overlay(Palette.line).padding(.leading, 18)
                RuleToggle(title: "Skip days I already wrote", subtitle: "No reminder once something is put down that day.", isOn: $s.reminderSkipIfWritten)
                Text("Planned a week ahead each time you open AiHeart. If you step away, the reminders stop on their own. Paused while Pause everything is on.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 18).padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()
        .onChange(of: s.reminderOn) { _, on in
            Task {
                if on { await WorkoutService.shared.requestNotificationPermission() }
                await apply()
            }
        }
        .onChange(of: s.reminderHour) { Task { await apply() } }
        .onChange(of: s.reminderMinute) { Task { await apply() } }
        .onChange(of: s.reminderDays) { Task { await apply() } }
        .onChange(of: s.reminderSkipIfWritten) { Task { await apply() } }
        .onChange(of: s.pauseEverything) { Task { await apply() } }
    }

    private func apply() async {
        s.updatedAt = .now
        try? context.save()
        await WriteReminder.reschedule(context: context)
    }
}

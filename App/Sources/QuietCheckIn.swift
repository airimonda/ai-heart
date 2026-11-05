import AiHeartCore
import AppIntents
import SwiftData
import SwiftUI
import UserNotifications

/// "When I go quiet" (docs/15). Plans at most one non-demanding check-in per quiet stretch.
/// Re-planned whenever the app opens or something is saved, so any new log starts a new stretch.
@MainActor
enum QuietCheckIn {
    static let prefix = "quiet-"
    nonisolated static let category = "quietCheck"
    nonisolated static let tryAction = "quiet.try"
    nonisolated static let reachAction = "quiet.reach"
    nonisolated static let busyAction = "quiet.busy"
    private static let sentForKey = "quietSentFor"
    private static let plannedKey = "quietPlannedAt"

    nonisolated static var categoryValue: UNNotificationCategory {
        UNNotificationCategory(identifier: category, actions: [
            UNNotificationAction(identifier: tryAction, title: "Something to try", options: [.foreground]),
            UNNotificationAction(identifier: reachAction, title: "Who I can reach", options: [.foreground]),
            UNNotificationAction(identifier: busyAction, title: "Busy, all good", options: []),
        ], intentIdentifiers: [], options: [])
    }

    /// Her logs of any kind: entries, Listen, things she tried, doses, body checks.
    /// Passive data (Health, workouts, media) does not count: being on the move is not being okay.
    static func activity(_ context: ModelContext, since: Date) -> [Date] {
        var out: [Date] = []
        out += ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt > since }))) ?? []).map(\.createdAt)
        out += ((try? context.fetch(FetchDescriptor<ListenSession>(predicate: #Predicate { $0.date > since }))) ?? []).map(\.date)
        out += ((try? context.fetch(FetchDescriptor<TechniqueTry>(predicate: #Predicate { $0.date > since }))) ?? []).map(\.date)
        out += ((try? context.fetch(FetchDescriptor<MedicationLog>(predicate: #Predicate { $0.takenAt > since }))) ?? []).map(\.takenAt)
        out += ((try? context.fetch(FetchDescriptor<BodyCheck>(predicate: #Predicate { $0.updatedAt > since }))) ?? []).map(\.updatedAt)
        return out
    }

    static func thresholdDays(_ context: ModelContext) -> Int {
        QuietCheck.thresholdDays(activity: activity(context, since: .now.addingTimeInterval(-90 * 86_400)), now: .now)
    }

    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let s = AiHeartStore.settings(in: context)
        if DemoData.isOn(context) { return }
        let all = activity(context, since: .now.addingTimeInterval(-90 * 86_400))
        let defaults = UserDefaults.standard
        let fire = QuietCheck.fireDate(
            lastActivity: all.max(), thresholdDays: QuietCheck.thresholdDays(activity: all, now: .now),
            hour: s.reminderOn ? s.reminderHour : 19, now: .now, enabled: s.quietCheckOn, paused: s.pauseEverything,
            alreadySentFor: defaults.object(forKey: sentForKey) as? Date, plannedAt: defaults.object(forKey: plannedKey) as? Date)
        guard let fire, let last = all.max() else { return }
        defaults.set(last, forKey: sentForKey)
        defaults.set(fire, forKey: plannedKey)

        let content = UNMutableNotificationContent()
        content.title = "AiHeart"
        content.body = QuietCheck.body
        content.categoryIdentifier = category
        content.userInfo = ["quiet": true]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: prefix + "\(Int(fire.timeIntervalSince1970))", content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

/// "Something to try" from Siri, Shortcuts, Spotlight or the Action button. No typing needed.
struct SomethingToTryIntent: AppIntent {
    static let title: LocalizedStringResource = "Something to try"
    static let description = IntentDescription("Opens AiHeart's fixed exercises for hard moments: breathing, grounding, body, thoughts, moving.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openHardMoments = true
        return .result()
    }
}

/// "Open my safety plan" from Siri, Shortcuts, Spotlight or the Action button. Shows her plan, read only.
struct OpenSafetyPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my safety plan"
    static let description = IntentDescription("Opens the safety plan you wrote in AiHeart, with the phone numbers you added.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.openSafetyPlan = true
        return .result()
    }
}

/// My rules: "When I go quiet".
struct QuietCheckRow: View {
    @Bindable var s: AppSettings
    @Environment(\.modelContext) private var context
    @State private var days = QuietCheck.defaultDays

    var body: some View {
        RuleToggle(title: "When I go quiet",
                   subtitle: "After about \(days) days without a log, one quiet check-in: Something to try, Who I can reach, or Busy, all good. Once per quiet stretch. It never asks you to log.",
                   isOn: $s.quietCheckOn)
            .task { days = QuietCheckIn.thresholdDays(context) }
            .onChange(of: s.quietCheckOn) { _, on in
                s.updatedAt = .now
                try? context.save()
                Task {
                    if on { await WorkoutService.shared.requestNotificationPermission() }
                    await QuietCheckIn.reschedule(context: context)
                }
            }
    }
}

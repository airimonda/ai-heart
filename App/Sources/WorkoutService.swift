import AiHeartCore
import HealthKit
import Security
import SwiftData
import SwiftUI
import UserNotifications

/// Provider tokens live in the Keychain, never in the store (docs/02), and stay on this device.
enum Keychain {
    static let service = "local.aiheart.app"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Workouts from Apple Health and Hevy, merged per session, plus the one prompt to rate each.
@MainActor @Observable
final class WorkoutService {
    static let shared = WorkoutService()
    static let hevyAccount = "hevy.apiKey"

    private let store = HKHealthStore()
    var syncing = false
    var hevyError: String?
    var lastHevySync: Date? {
        get { UserDefaults.standard.object(forKey: "hevy.lastSync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "hevy.lastSync") }
    }
    /// Set by a notification tap; RootView presents the rating sheet.
    var pendingRating: UUID?

    var hevyConnected: Bool { Keychain.get(Self.hevyAccount) != nil }

    func setHevyKey(_ key: String?) {
        Keychain.set(key?.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.hevyAccount)
        lastHevySync = nil
        hevyError = nil
    }

    func sync(context: ModelContext) async {
        guard !syncing, !DemoData.isOn(context) else { return }
        syncing = true
        defer { syncing = false }
        let device = UIDevice.current.identifierForVendor?.uuidString ?? ""

        if HealthService.shared.asked, HKHealthStore.isHealthDataAvailable() {
            await syncHealth(context: context, device: device)
        }
        if let key = Keychain.get(Self.hevyAccount) {
            await syncHevy(HevyAPI(apiKey: key), context: context, device: device)
        }
        merge(context: context)
        ExerciseFill.run(context: context, dayStartHour: AiHeartStore.settings(in: context).dayStartHour)
        try? context.save()
        await promptIfNeeded(context: context)
    }

    // MARK: Health

    private func syncHealth(context: ModelContext, device: String) async {
        let fullKey = "workouts.fullHistoryRead"
        let since = UserDefaults.standard.bool(forKey: fullKey) ? Date().addingTimeInterval(-30 * 86400) : store.earliestPermittedSampleDate()
        defer { UserDefaults.standard.set(true, forKey: fullKey) }
        guard let samples = try? await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        ).result(for: store) else { return }

        let existing = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var byHealth = Dictionary(existing.compactMap { w in w.healthId.map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
        for s in samples {
            let id = s.uuid.uuidString
            let w = byHealth[id] ?? {
                let n = Workout(kind: Self.kind(s.workoutActivityType), start: s.startDate, durationSec: s.duration)
                n.healthId = id
                n.deviceId = device
                context.insert(n)
                return n
            }()
            byHealth[id] = w
            w.start = s.startDate
            w.durationSec = s.duration
            if w.hevyId == nil { w.kind = Self.kind(s.workoutActivityType) }
            w.activeKcal = s.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            w.avgHR = s.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?
                .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            w.updatedAt = .now
        }
    }

    static func kind(_ t: HKWorkoutActivityType) -> WorkoutKind {
        switch t {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .strength
        case .walking, .hiking: .walk
        case .running: .run
        case .cycling: .cycle
        case .swimming: .swim
        case .yoga, .pilates, .mindAndBody: .yoga
        case .highIntensityIntervalTraining, .crossTraining: .hiit
        case .socialDance, .cardioDance: .dance
        case .mixedCardio, .stepTraining, .jumpRope, .elliptical, .stairs: .aerobics
        default: .other
        }
    }

    // MARK: Hevy

    private func syncHevy(_ api: HevyAPI, context: ModelContext, device: String) async {
        do {
            if let since = lastHevySync {
                for e in try await api.events(since: since.addingTimeInterval(-3600)) {
                    switch e {
                    case .updated(let w): upsert(w, context: context, device: device)
                    case .deleted(let id): removeHevy(id, context: context)
                    }
                }
            } else {
                // First sync: her whole Hevy history.
                for w in try await api.recentWorkouts(pages: 500) { upsert(w, context: context, device: device) }
            }
            lastHevySync = .now
            hevyError = nil
        } catch HevyAPI.HevyError.unauthorized {
            hevyError = "Hevy did not accept the key. Check it at hevy.com/settings?developer."
        } catch {
            hevyError = "Could not reach Hevy just now."
        }
    }

    private func upsert(_ dto: HevyAPI.WorkoutDTO, context: ModelContext, device: String) {
        let id = dto.id
        let found = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.hevyId == id })).first
        let w = found ?? {
            let n = Workout(kind: .strength, start: dto.start_time, durationSec: dto.end_time.timeIntervalSince(dto.start_time))
            n.hevyId = id
            n.deviceId = device
            context.insert(n)
            return n
        }()
        w.title = dto.title
        w.kind = .strength
        if w.healthId == nil {
            w.start = dto.start_time
            w.durationSec = dto.end_time.timeIntervalSince(dto.start_time)
        }
        w.updatedAt = .now
        try? context.delete(model: HevySet.self, where: #Predicate { $0.hevyWorkoutId == id })
        for e in dto.exercises {
            for s in e.sets {
                let row = HevySet(hevyWorkoutId: id, exerciseIndex: e.index, exerciseName: e.title, setIndex: s.index)
                row.setType = s.type ?? "normal"
                row.weightKg = s.weight_kg; row.reps = s.reps; row.rpe = s.rpe
                row.distanceM = s.distance_meters; row.durationSec = s.duration_seconds
                context.insert(row)
            }
        }
    }

    private func removeHevy(_ id: String, context: ModelContext) {
        try? context.delete(model: HevySet.self, where: #Predicate { $0.hevyWorkoutId == id })
        guard let w = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.hevyId == id })).first else { return }
        if w.healthId == nil { context.delete(w) } else { w.hevyId = nil; w.title = nil }
    }

    /// Joins a Hevy-only row with the Health-only row for the same session, keeping both
    /// sources: Hevy supplies sets and the title, Health supplies time, calories and heart rate.
    private func merge(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let hevyOnly = all.filter { $0.hevyId != nil && $0.healthId == nil }
        let healthOnly = all.filter { $0.healthId != nil && $0.hevyId == nil }
        let pairs = WorkoutMatch.pairs(hevy: hevyOnly.map { ($0.start, $0.end) }, health: healthOnly.map { ($0.start, $0.end) })
        for (hi, ki) in pairs {
            let hevy = hevyOnly[hi], health = healthOnly[ki]
            health.hevyId = hevy.hevyId
            health.title = hevy.title
            health.kind = .strength
            health.rpe = health.rpe ?? hevy.rpe
            health.focusRaw = health.focusRaw ?? hevy.focusRaw
            health.note = health.note ?? hevy.note
            health.ratedAt = health.ratedAt ?? hevy.ratedAt
            health.promptedAt = health.promptedAt ?? hevy.promptedAt
            health.updatedAt = .now
            context.delete(hevy)
        }
    }

    // MARK: Prompt

    private var container: ModelContainer?

    /// Effort from a notification action, without opening the app.
    func rateQuickly(_ id: UUID, rpe: Int) {
        guard let container else { return }
        let ctx = ModelContext(container)
        guard let w = try? ctx.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncId == id })).first else { return }
        w.rpe = rpe
        w.ratedAt = .now
        w.updatedAt = .now
        try? ctx.save()
    }

    func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// One prompt per new workout. Neutral text: nothing about the workout or her body
    /// appears on the lock screen (docs/06).
    private func promptIfNeeded(context: ModelContext) async {
        let s = AiHeartStore.settings(in: context)
        let all = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        let sets = (try? context.fetch(FetchDescriptor<HevySet>())) ?? []
        let hevyWithEffort = Set(sets.filter { $0.rpe != nil }.map(\.hevyWorkoutId))
        let due = all.filter {
            WorkoutPrompt.shouldAsk($0, enabled: s.askToRateWorkouts, paused: s.pauseEverything, minMinutes: s.rateMinMinutes,
                                    hevyHasEffort: $0.hevyId.map(hevyWithEffort.contains) ?? false,
                                    skipIfHevyEffort: s.rateSkipIfHevyEffort)
        }
        guard !due.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for w in due {
            let content = UNMutableNotificationContent()
            content.title = "AiHeart"
            content.body = "A workout was saved. Rate it when you like."
            content.userInfo = ["workout": w.syncId.uuidString]
            content.interruptionLevel = .active   // Owner, 2026-11-02: passive never showed a banner, so she never saw it.
            content.categoryIdentifier = NotificationRouter.rateCategory
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: WorkoutPrompt.delay(w, waitMinutes: s.rateWaitMinutes), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "rate-\(w.syncId)", content: content, trigger: trigger))
            w.promptedAt = .now
        }
        try? context.save()
    }

    // MARK: Background

    private var observing = false

    /// Wakes the app when Health gets a new workout, so the prompt can follow soon after.
    func startObserving(container: ModelContainer) {
        self.container = container
        guard !observing, HKHealthStore.isHealthDataAvailable(), HealthService.shared.asked else { return }
        observing = true
        let type = HKWorkoutType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, done, error in
            guard error == nil else { done(); return }
            Task { @MainActor in
                await WorkoutService.shared.sync(context: ModelContext(container))
                done()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }
}

/// Routes a notification tap to the rating sheet.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    static let rateCategory = "rateWorkout"

    /// Light, Solid and Hard right from the notification.
    static func registerCategories() {
        let actions = WorkoutPrompt.quickAnswers.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) }
        let rate = UNNotificationCategory(identifier: rateCategory, actions: actions, intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([rate, QuietCheckIn.categoryValue])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["quiet"] as? Bool == true {
            // "Busy, all good" needs nothing. Tapping the banner itself offers Something to try.
            switch response.actionIdentifier {
            case QuietCheckIn.busyAction: return
            case QuietCheckIn.reachAction: await MainActor.run { AppRouter.shared.openReach = true }
            default: await MainActor.run { AppRouter.shared.openHardMoments = true }
            }
            return
        }
        if response.notification.request.content.userInfo["open"] as? String == "now" {
            await MainActor.run { AppRouter.shared.openNow = true }
            return
        }
        guard let s = response.notification.request.content.userInfo["workout"] as? String, let id = UUID(uuidString: s) else { return }
        if let quick = WorkoutPrompt.quickAnswers.first(where: { $0.id == response.actionIdentifier }) {
            await MainActor.run { WorkoutService.shared.rateQuickly(id, rpe: quick.rpe) }
            return
        }
        await MainActor.run { WorkoutService.shared.pendingRating = id }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

/// Exercise minutes from her workouts (docs/15 note; owner, 2026-11-02). Without an Apple Watch,
/// Apple's exercise minutes are empty, so the day's exercise is the larger of those and the time
/// her workouts covered. Strava rows are display-only (CLAUDE.md #6) and never count.
@MainActor
enum ExerciseFill {
    static func run(context: ModelContext, dayStartHour: Int) {
        let since = Date().addingTimeInterval(-400 * 86_400)
        let rows = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.start > since && $0.aiEligible }))) ?? []
        let byDay = ExerciseTime.minutesByDay(rows.map { ($0.start, $0.durationSec) }, timeZone: .current, dayStartHour: dayStartHour)
        guard !byDay.isEmpty else { return }
        let summaries = (try? context.fetch(FetchDescriptor<DaySummary>())) ?? []
        var byKey: [String: DaySummary] = [:]
        for s in summaries { byKey[s.dayKey] = s }
        for (day, minutes) in byDay {
            let s = byKey[day.key] ?? { let n = DaySummary(day: day); context.insert(n); return n }()
            let value = ExerciseTime.combined(apple: s.exerciseMin, workouts: minutes)
            if s.exerciseMin != value { s.exerciseMin = value; s.updatedAt = .now }
        }
    }
}

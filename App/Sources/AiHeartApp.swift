import AiHeartCore
import LocalAuthentication
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

@main
struct AiHeartApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try AiHeartStore.makeContainer()
            AppData.container = container
            UNUserNotificationCenter.current().delegate = NotificationRouter.shared
            NotificationRouter.registerCategories()
            HangWatch.start()
            // Swiping down on a scrolling screen lowers the keyboard, everywhere.
            UIScrollView.appearance().keyboardDismissMode = .interactive
        } catch {
            // The store is the only irreplaceable data. Fail loudly rather than start empty.
            fatalError("Could not open the AiHeart store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let demo = HardMomentsDemo.requested {
                HardMomentsDemo(screen: demo)
            } else {
                RootView().tint(Palette.action)
            }
            #else
            RootView()
                .tint(Palette.action)
            #endif
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable { case now, journal, insights }

@MainActor @Observable
final class AppLock {
    var locked = false

    func lockIfNeeded(_ enabled: Bool) {
        if enabled { locked = true }
    }

    func unlock(biometrics: Bool = false) {
        let ctx = LAContext()
        var error: NSError?
        let policy: LAPolicy = biometrics && ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode or biometrics on this device: nothing to check against.
            locked = false
            return
        }
        ctx.evaluatePolicy(policy, localizedReason: "Open your journal") { ok, _ in
            Task { @MainActor in if ok { self.locked = false } }
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .now
    @State private var lock = AppLock()
    @State private var settings: AppSettings?
    @State private var opening = true
    @State private var showFirstRun = !UserDefaults.standard.bool(forKey: FirstRunView.doneKey)
        && !ProcessInfo.processInfo.arguments.contains("-skipFirstRun")
    private var workouts = WorkoutService.shared
    private var router = AppRouter.shared

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab("Now", systemImage: "circle.fill", value: AppTab.now) {
                    NowView(tab: $tab)
                }
                Tab("Journal", systemImage: "book.closed.fill", value: AppTab.journal) {
                    JournalView()
                }
                Tab("Insights", systemImage: "chart.bar.fill", value: AppTab.insights) {
                    InsightsView()
                }
            }
            .tint(Palette.action)

            if opening {
                OpeningView().transition(.opacity).zIndex(2)
            }
            if showFirstRun && !opening {
                FirstRunView { withAnimation { showFirstRun = false } }
                    .transition(.opacity).zIndex(1)
            }

            // Hidden in the app switcher, and covered while locked.
            if lock.locked {
                LockedView { biometrics in lock.unlock(biometrics: biometrics) }
                    .transition(.opacity)
            } else if scenePhase != .active {
                PrivacyCover(locked: false) {}
                    .transition(.opacity)
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSamples"), !DemoData.isOn(context) { DemoData.fill(context) }
            if ProcessInfo.processInfo.arguments.contains("-sampleVibe") {
                DemoData.sampleVibe(today: DayAnchor.day(for: .now, timeZone: .current, dayStartHour: 4))
            }
            if ProcessInfo.processInfo.arguments.contains("-openJournal") { tab = .journal }
            if ProcessInfo.processInfo.arguments.contains("-openInsights") { tab = .insights }
            // Demo recordings: a sample safety plan (synthetic words), opened read-only.
            if ProcessInfo.processInfo.arguments.contains("-openSafety") {
                if let s = try? context.fetch(FetchDescriptor<AppSettings>()).first {
                    let sample: [SafetyPlan.Step: String] = [
                        .signs: "[Sample] Not sleeping. Skipping meals. Thinking nobody would notice if I stopped answering.",
                        .coping: "[Sample] A hot shower. A slow walk around the block. My calm playlist.",
                        .places: "[Sample] The café near work. Calling my sister just to talk.",
                        .helpers: "[Sample] My sister. My best friend from college.",
                        .pros: "[Sample] My therapist, weekdays 9 to 5.",
                        .safeSpace: "[Sample] Give the spare medication to my sister to keep.",
                    ]
                    for (step, text) in sample where step.text(in: s).isEmpty { step.set(text, in: s) }
                    try? context.save()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { router.openSafetyPlan = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-rateLatest") {
                let all = (try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []
                workouts.pendingRating = all.first { !$0.isRated }?.syncId
            }
            #endif
            SeedImport.runIfPresent(context)
            LLMService.shared.removeUnusedModelsOnce()
            let s = AiHeartStore.settings(in: context)
            settings = s
            lock.lockIfNeeded(s.faceIDLock)
            if lock.locked { lock.unlock() }
            try? EntryLifecycle.runPurgeJob(in: context)
            RecentlyDeleted.purgeExpired(in: context)
            // A short opening while the first screens build; never longer than needed.
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-holdOpening") { return }
                #endif
                withAnimation(.easeOut(duration: 0.35)) { opening = false }
            }
            Task {
                // First launch: ask for Health once, so history can be read straight away.
                if !HealthService.shared.asked, !DemoData.isOn(context) { await HealthService.shared.requestAccess() }
                HangWatch.label = "health sync"
                await HealthService.shared.sync(context: context, dayStartHour: s.dayStartHour)
                HangWatch.label = "workout sync"
                await workouts.sync(context: context)
                workouts.startObserving(container: context.container)
                HangWatch.label = "idle"
                await WriteReminder.reschedule(context: context)
                // Let the first screens settle before loading 3.5 GB.
                try? await Task.sleep(for: .seconds(4))
                HangWatch.label = "model load"
                if LLMService.shared.isDownloaded {
                    await LLMService.shared.prepare()
                    // Background work waits until she has settled in: with the 8B model, running it
                    // right at open made the app feel slow (owner, 2026-11-04).
                    try? await Task.sleep(for: .seconds(15))
                    await ToneGuesser.run(context)
                    await MediaVibeStore.shared.refresh(context)
                }
                HangWatch.label = "idle"
            }
        }
        .onChange(of: router.openNow) { _, open in
            if open { tab = .now; router.openNow = false }
        }
        .sheet(isPresented: Binding(get: { router.openHardMoments }, set: { router.openHardMoments = $0 })) { HardMomentsView() }
        .sheet(isPresented: Binding(get: { router.openReach }, set: { router.openReach = $0 })) { ListenReachSheet() }
        .sheet(isPresented: Binding(get: { router.openSafetyPlan }, set: { router.openSafetyPlan = $0 })) { SafetyPageView(readOnly: true, keptNote: false) }
        .sheet(item: Binding(get: { pendingWorkout }, set: { if $0 == nil { workouts.pendingRating = nil } })) { w in
            RateWorkoutView(workout: w)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfNeeded(settings?.faceIDLock ?? false)
                // Free about 3.5 GB so iOS does not close AiHeart in the background.
                if LLMService.shared.state == .ready { LLMService.shared.unload() }
            case .active:
                if lock.locked { lock.unlock() }
                try? EntryLifecycle.runPurgeJob(in: context)
                RecentlyDeleted.purgeExpired(in: context)
                Task {
                    await HealthService.shared.sync(context: context, dayStartHour: settings?.dayStartHour ?? 4)
                    await workouts.sync(context: context)
                    await SpotifyService.shared.refresh(context)
                    await WriteReminder.reschedule(context: context)
                    try? await Task.sleep(for: .seconds(4))
                    if LLMService.shared.isDownloaded { await LLMService.shared.prepare(); await ToneGuesser.run(context); await MediaVibeStore.shared.refresh(context) }
                }
            default: break
            }
        }
    }
}

extension RootView {
    var pendingWorkout: Workout? {
        guard let id = workouts.pendingRating else { return nil }
        return try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.syncId == id })).first
    }
}

struct PrivacyCover: View {
    let locked: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Palette.surface.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Palette.action)
                    .accessibilityHidden(true)
                if locked {
                    Button("Open AiHeart", action: unlock)
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(width: 220)
                }
            }
        }
    }
}

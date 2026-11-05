import AiHeartCore
import AppIntents
import SwiftData
import SwiftUI
import UIKit

/// The one store, shared with App Intents so a Shortcuts automation writes to the same place.
@MainActor
enum AppData {
    static var container: ModelContainer?
    static func shared() throws -> ModelContainer {
        if let c = container { return c }
        let c = try AiHeartStore.makeContainer()
        container = c
        return c
    }
}

/// "Log app open" for a Shortcuts personal automation: "When Instagram is opened → Log app
/// open (Instagram)". The supported way to count opens; no Screen Time workaround (CLAUDE.md #12).
struct LogAppOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "Log app open"
    static let description = IntentDescription("Counts one open of an app in AiHeart. Add it to a Shortcuts automation that runs when that app is opened.")
    static let openAppWhenRun = false

    @Parameter(title: "App name", requestValueDialog: "Which app?")
    var app: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(try AppData.shared())
        context.insert(AppOpen(appName: app, date: .now, deviceId: UIDevice.current.identifierForVendor?.uuidString ?? ""))
        try context.save()
        return .result()
    }
}

struct AiHeartShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SomethingToTryIntent(), phrases: ["Something to try in \(.applicationName)", "Open \(.applicationName) something to try"],
                    shortTitle: "Something to try", systemImageName: "leaf")
        AppShortcut(intent: OpenSafetyPlanIntent(), phrases: ["Open my safety plan in \(.applicationName)", "My safety plan in \(.applicationName)"],
                    shortTitle: "My safety plan", systemImageName: "lifepreserver")
        AppShortcut(intent: LogAppOpenIntent(), phrases: ["Log app open in \(.applicationName)"],
                    shortTitle: "Log app open", systemImageName: "app.badge")
    }
}

/// App opens this week, on the Media screen.
struct AppOpensCard: View {
    @Query private var opens: [AppOpen]
    let weekStart: AnchoredDay
    let dayStart: Int

    var body: some View {
        let counts = AppOpenWeek.counts(opens.map { ($0.appName, $0.date) }, weekStart: weekStart, dayStartHour: dayStart, timeZone: .current)
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("App opens").font(.headline).foregroundStyle(Palette.ink)
                ForEach(Array(counts.prefix(8).enumerated()), id: \.offset) { _, c in
                    HStack { Text(c.app).foregroundStyle(Palette.ink); Spacer(); Text("\(c.count)").monospacedDigit().foregroundStyle(Palette.muted) }
                        .font(.subheadline)
                }
                Text("From your Shortcuts automations. Opens within a minute count once.").font(.caption).foregroundStyle(Palette.muted)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        } else {
            // Owner, 2026-11-02: the card was hidden when empty, so she could not find it.
            NavigationLink { SourcesView() } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("App opens").font(.headline).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.muted)
                    }
                    Text(opens.isEmpty
                         ? "None logged yet. iOS does not let apps read Screen Time, so each app needs a one-time Shortcuts automation. Tap to see the 3 steps."
                         : "None this week.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).card()
            }
            .buttonStyle(.plain)
        }
    }
}

/// How to set up the automation, on the Sources screen.
struct AppOpensSetupCard: View {
    @Query private var opens: [AppOpen]
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("App opens").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text(opens.isEmpty ? "Not set up" : "\(opens.count) logged").font(.footnote).foregroundStyle(Palette.muted)
            }
            Text("Counts how often you open apps you choose. Set up once per app in the Shortcuts app:").font(.footnote).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Shortcuts › Automation › New Automation › App.")
                Text("2. Choose the app, \u{201C}Is Opened\u{201D}, and \u{201C}Run Immediately\u{201D}.")
                Text("3. Add the action \u{201C}Log app open\u{201D} (AiHeart) and type the app's name.")
            }
            .font(.footnote).foregroundStyle(Palette.ink)
            if !opens.isEmpty {
                Button("Remove all", role: .destructive) {
                    for o in opens { context.delete(o) }
                    try? context.save()
                }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

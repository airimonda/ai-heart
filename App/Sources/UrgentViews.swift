import AiHeartCore
import SwiftData
import SwiftUI

/// Chips that wrap onto new lines.
struct FlowChips: View {
    let items: [(id: String, title: String)]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.id) { item in
                Chip(title: item.title, selected: selected.contains(item.id)) { toggle(item.id) }
            }
        }
    }
}

/// Shown when what she logged meets a fixed urgent-sign rule (owner, 2026-11-01).
/// Calm colors, plain words, no condition names, one clear action.
struct UrgentSheet: View {
    let findings: [UrgentSigns.Finding]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var number: String { UrgentSigns.emergencyNumber(region: Locale.current.region?.identifier) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.action)
                    .accessibilityHidden(true)
                Text("This may need care now")
                    .font(.journal(.title2).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                ForEach(findings) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.what).font(.headline).foregroundStyle(Palette.ink)
                        Text(f.why).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                Text("AiHeart only checks a few fixed rules. It cannot tell what is happening. If you feel unwell, trust that over this app.")
                    .font(.footnote).foregroundStyle(Palette.muted)
                Button {
                    NSLog("AiHeartUI urgent call tapped")
                    if let url = URL(string: "tel://\(number)") { openURL(url) }
                } label: {
                    Text("Call \(number)")
                        .font(.headline)
                        .foregroundStyle(Palette.onAction)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Palette.action, in: Capsule())
                }
                .buttonStyle(.plain)
                Button("I'm okay for now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(24)
        }
        .background(Palette.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
    }
}

/// Checks today's entries and check-in after something new is logged. Each finding is
/// shown once per day, so it never nags.
enum UrgentWatch {
    static func pending(entries: [Entry], summary: DaySummary?, today: AnchoredDay, dayStart: Int) -> [UrgentSigns.Finding] {
        let sensations = Set(entries
            .filter { $0.status != .released && DayAnchor.day(for: $0.createdAt, timeZone: $0.timeZone, dayStartHour: dayStart) == today }
            .flatMap(\.sensations))
        let input = UrgentSigns.Input(heartRate: summary?.manualHR, systolic: summary?.systolic, diastolic: summary?.diastolic,
                                      signs: Set((summary?.warningSigns ?? []).compactMap(UrgentSigns.Sign.init(rawValue:))),
                                      sensations: sensations)
        let key = "urgent.shown.\(today.key)"
        let shown = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let found = UrgentSigns.check(input)
        guard found.contains(where: { !shown.contains($0.id) }) else { return [] }
        UserDefaults.standard.set(Array(shown.union(found.map(\.id))), forKey: key)
        return found
    }

    /// The check-in shows its own sheet; mark those so Now does not repeat them.
    static func markShown(_ ids: [String], today: AnchoredDay) {
        let key = "urgent.shown.\(today.key)"
        let shown = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        UserDefaults.standard.set(Array(shown.union(ids)), forKey: key)
    }
}

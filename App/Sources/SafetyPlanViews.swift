import AiHeartCore
import Contacts
import ContactsUI
import SwiftData
import SwiftUI

// Her safety plan (docs/17-safety-plan.md): the six steps of the Stanley-Brown Safety Planning
// Intervention, plus "Anything else" (her old safety page). Everything here is written by her and
// shown as she wrote it. Fixed titles and helper lines only. Nothing is generated.

/// Her safety plan. `readOnly` shows it; otherwise it is the editor (My rules).
struct SafetyPageView: View {
    let readOnly: Bool
    /// "This entry stays kept." heads the read view when it opens because an entry was kept.
    var keptNote = true
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsRows: [AppSettings]
    @AppStorage("safety.crisisLines") private var showLines = true

    // The read view opens as a sheet and brings its own NavigationStack. The editor is pushed from
    // My rules, inside that screen's stack, so it must not add a second one (a nested stack crashed).
    @ViewBuilder var body: some View {
        if readOnly {
            NavigationStack {
                page.toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        } else {
            page.keyboardHideButton()
                .onDisappear { saveIfNeeded() }
                .onChange(of: scenePhase) { _, phase in if phase != .active { saveIfNeeded() } }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if readOnly {
                    if keptNote {
                        Text("This entry stays kept.").font(.headline).foregroundStyle(Palette.ink)
                    }
                    SafetyPlanReadBody(settings: settingsRows.first, linesUnderStepFive: showLines,
                                       emptyNote: "Your safety plan is empty. You can write it in My rules.")
                } else if let s = settingsRows.first {
                    SafetyPlanEditor(settings: s, showLines: $showLines)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.surface.ignoresSafeArea())
        .navigationTitle("My safety plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveIfNeeded() {
        guard !readOnly, context.hasChanges else { return }
        try? context.save()
    }
}

/// The seven text boxes, one per step.
private struct SafetyPlanEditor: View {
    @Bindable var settings: AppSettings
    @Binding var showLines: Bool
    /// The step a picked contact is added to.
    @State private var pickingFor: SafetyPlan.Step?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A plan for when things get hard, from the first signs to the people you can call. Written by you, shown as you wrote it. It can help to fill it in with your therapist.")
                .font(.subheadline).foregroundStyle(Palette.muted)
            ForEach(SafetyPlan.Step.allCases, id: \.self) { step in
                VStack(alignment: .leading, spacing: 8) {
                    if step != .other {
                        Text("Step \(step.rawValue) of 6").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Text(step.title).font(.headline).foregroundStyle(Palette.ink)
                    Text(step.helper).font(.subheadline).foregroundStyle(Palette.muted)
                    TextEditor(text: binding(step))
                        .font(.journal(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(step.title)
                    if step == .helpers || step == .pros || step == .places {
                        // Owner, 2026-11-04: "I am allowing the app to read my emergency contacts." iOS does not let
                        // apps read Medical ID emergency contacts, so she picks people here; the app sees only those.
                        Button { pickingFor = step } label: {
                            Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus").frame(minHeight: 44)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.onTint)
                    }
                    if step == .pros {
                        RuleToggle(title: "Show crisis lines", subtitle: "Japan and the Philippines, under this step", isOn: $showLines)
                            .padding(.top, 4)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
        // Apple's picker is presented by UIKit, not as a SwiftUI sheet: it dismisses itself after a pick,
        // and as a sheet's root that fought SwiftUI's own dismissal.
        .background(ContactPicker(step: $pickingFor) { step, contacts in
            let lines = contacts.compactMap(ContactPicker.line)
            guard !lines.isEmpty else { return }
            let current = step.text(in: settings).trimmingCharacters(in: .whitespacesAndNewlines)
            step.set(([current].filter { !$0.isEmpty } + lines).joined(separator: "\n"), in: settings)
            settings.updatedAt = .now
        }
        .frame(width: 0, height: 0))
    }

    private func binding(_ step: SafetyPlan.Step) -> Binding<String> {
        Binding(get: { step.text(in: settings) },
                set: { v in
                    guard step.text(in: settings) != v else { return }
                    step.set(v, in: settings)
                    settings.updatedAt = .now
                })
    }
}

/// Her plan as she wrote it. Steps she left empty are hidden. Phone numbers she wrote are tappable.
/// `linesUnderStepFive` shows the fixed crisis lines under "Professionals I can call".
struct SafetyPlanReadBody: View {
    let settings: AppSettings?
    var linesUnderStepFive = false
    /// Shown when she has written nothing. nil shows nothing.
    var emptyNote: String?

    var body: some View {
        let sections = settings.map { SafetyPlan.sections(from: $0) } ?? []
        VStack(alignment: .leading, spacing: 16) {
            if sections.isEmpty {
                if let emptyNote { Text(emptyNote).font(.subheadline).foregroundStyle(Palette.muted) }
                if linesUnderStepFive { CrisisLines() }
            } else {
                ForEach(SafetyPlan.Step.allCases, id: \.self) { step in
                    let sec = sections.first { $0.step == step }
                    if let sec {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sec.title).font(.headline).foregroundStyle(Palette.ink)
                            Text(SafetyPlan.linkified(sec.text))
                                .font(.journal(.body)).foregroundStyle(Palette.ink)
                                .tint(Palette.onTint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                    } else if step == .pros && linesUnderStepFive {
                        Text(step.title).font(.headline).foregroundStyle(Palette.ink)
                    }
                    if step == .pros && linesUnderStepFive { CrisisLines() }
                }
            }
        }
    }
}

/// Apple's contact picker: she chooses people; the app receives only those (no Contacts permission).
/// A zero-size host presents the picker with UIKit when `step` is set, and clears `step` when it closes.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var step: SafetyPlan.Step?
    let onPick: (SafetyPlan.Step, [CNContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let step, c.openFor == nil else { return }
        c.openFor = step
        DispatchQueue.main.async {
            guard host.view.window != nil, host.presentedViewController == nil else {
                c.close(with: [])
                return
            }
            let p = CNContactPickerViewController()
            p.delegate = c
            p.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            p.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
            host.present(p, animated: true)
        }
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker?
        var openFor: SafetyPlan.Step?

        // The picker dismisses itself after either call.
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { close(with: contacts) }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { close(with: []) }

        func close(with contacts: [CNContact]) {
            let step = openFor
            openFor = nil
            parent?.step = nil
            if let step, !contacts.isEmpty { parent?.onPick(step, contacts) }
        }
    }

    /// "Name: number" for her plan; the number is tappable in the read view. Reads only keys the picker
    /// returned: touching a key that was not fetched raises an Objective-C exception and ends the app.
    static func line(_ c: CNContact) -> String? {
        guard c.isKeyAvailable(CNContactPhoneNumbersKey),
              let number = c.phoneNumbers.first?.value.stringValue else { return nil }
        var name: String?
        if c.areKeysAvailable([CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]) {
            name = CNContactFormatter.string(from: c, style: .fullName)
        }
        if name?.isEmpty ?? true {
            let parts = [CNContactGivenNameKey, CNContactFamilyNameKey].compactMap { key -> String? in
                guard c.isKeyAvailable(key) else { return nil }
                return key == CNContactGivenNameKey ? c.givenName : c.familyName
            }.filter { !$0.isEmpty }
            name = parts.isEmpty ? nil : parts.joined(separator: " ")
        }
        if name == nil, c.isKeyAvailable(CNContactOrganizationNameKey), !c.organizationName.isEmpty {
            name = c.organizationName
        }
        return "\(name ?? "Contact"): \(number)"
    }
}

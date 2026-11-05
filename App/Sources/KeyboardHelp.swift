import SwiftUI
import UIKit

/// A "hide keyboard" button above the keyboard (owner, 2026-11-04: "allow me to minimize the keyboard
/// whenever it pops out"). Swiping down on any scrolling screen also lowers it (set in AiHeartApp.init).
struct KeyboardHideButton: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
    }
}

extension View {
    func keyboardHideButton() -> some View { modifier(KeyboardHideButton()) }
}

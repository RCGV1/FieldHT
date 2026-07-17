import SwiftUI
import UIKit

private struct KeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
        }
    }
}

extension View {
    /// Adds an explicit escape hatch for number pads, which do not include a
    /// return key, while preserving the standard swipe-to-dismiss gesture.
    func fieldHTKeyboardDismissal() -> some View {
        modifier(KeyboardDismissalModifier())
    }
}

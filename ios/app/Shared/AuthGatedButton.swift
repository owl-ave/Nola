import SwiftUI

/// A button that requires Face ID / PIN authentication before executing its action.
struct AuthGatedButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    var body: some View {
        Button { } label: {
            label()
        }
        .protectedAction(perform: action)
    }
}

import SwiftUI

/// A view that gates its content behind Face ID / PIN authentication.
/// Tries biometric silently on appear. Shows PIN numpad inline on failure.
struct AuthGateView<Content: View>: View {
    @EnvironmentObject var authManager: BiometricAuthManager
    @ViewBuilder let content: () -> Content

    @State private var authenticated = false
    @State private var showPIN = false

    var body: some View {
        if authenticated {
            content()
        } else if showPIN {
            LockScreenView(mode: .pinOnly(onCancel: {})) {
                withAnimation { authenticated = true }
            }
        } else {
            Color.clear
                .task {
                    if authManager.isEnabled {
                        let success = await authManager.authenticate()
                        if success {
                            withAnimation { authenticated = true }
                        } else {
                            withAnimation { showPIN = true }
                        }
                    } else {
                        withAnimation { showPIN = true }
                    }
                }
        }
    }
}

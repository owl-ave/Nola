import SwiftUI

/// A view modifier that protects an action behind biometric/PIN authentication.
///
/// Usage:
/// ```
/// Button("Freeze Card") { }
///     .protectedAction {
///         await toggleFreeze(card)
///     }
/// ```
///
/// Flow:
/// 1. User taps the view → biometric fires (system Face ID dialog)
/// 2. If success → executes the action
/// 3. If failure → presents PIN sheet
/// 4. If PIN success → executes the action
/// 5. If cancelled → nothing happens
struct ProtectedActionModifier: ViewModifier {
    @EnvironmentObject var authManager: BiometricAuthManager
    let action: () -> Void

    @State private var showPINSheet = false
    @State private var isAuthenticating = false

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                guard !isAuthenticating else { return }
                isAuthenticating = true
                Task {
                    if authManager.isEnabled {
                        let success = await authManager.authenticate()
                        if success {
                            await MainActor.run {
                                isAuthenticating = false
                                action()
                            }
                            return
                        }
                    }
                    await MainActor.run {
                        isAuthenticating = false
                        showPINSheet = true
                    }
                }
            }
            .sheet(isPresented: $showPINSheet) {
                NavigationStack {
                    LockScreenView(mode: .pinOnly(onCancel: { showPINSheet = false })) {
                        showPINSheet = false
                        action()
                    }
                }
                .environmentObject(authManager)
                .interactiveDismissDisabled()
            }
    }
}

extension View {
    /// Protect an action behind biometric/PIN authentication.
    /// Attach to any tappable view — intercepts tap, authenticates, then executes.
    func protectedAction(perform action: @escaping () -> Void) -> some View {
        modifier(ProtectedActionModifier(action: action))
    }
}

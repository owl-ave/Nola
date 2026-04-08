import SwiftUI

/// Mandatory security setup: Create PIN → Enable Face ID (if available).
/// Presented as a non-dismissable sheet before onboarding or home.
struct SecuritySetupView: View {
    @EnvironmentObject var authManager: BiometricAuthManager
    @EnvironmentObject var gateState: AppGateState
    @Environment(\.dismiss) var dismiss

    @State private var phase: Phase = .createPIN
    @State private var enteredDigits = ""
    @State private var newPIN = ""
    @State private var errorMessage: String?
    @State private var shake = false
    @State private var pinSaved = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private enum Phase {
        case createPIN, confirmPIN, biometric
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                content
                Spacer()
                if phase != .biometric {
                    numpad
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("Secure Your Account"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .createPIN, .confirmPIN:
            pinContent
        case .biometric:
            biometricContent
        }
    }

    // MARK: - PIN Content

    private var pinContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(phase == .createPIN ? "Create a PIN" : "Confirm PIN")
                    .font(.title3.weight(.semibold))
                Text(phase == .createPIN ? "Choose a 4-digit PIN to secure your account" : "Enter your PIN again to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    let filled = index < enteredDigits.count
                    Circle()
                        .fill(filled ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 14, height: 14)
                        .scaleEffect(filled ? 1.0 : 0.8)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: enteredDigits.count)
                }
            }
            .offset(x: shake ? -8 : 0)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 40)
        .animation(.default, value: phase)
        .animation(.default, value: errorMessage)
    }

    // MARK: - Biometric Content

    private var biometricContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: authManager.biometricIcon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("Enable \(authManager.biometricLabel)?")
                    .font(.title3.weight(.semibold))
                Text("Unlock the app quickly with \(authManager.biometricLabel) instead of your PIN")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        _ = await authManager.enable()
                        gateState.hasPIN = true
                        dismiss()
                    }
                } label: {
                    Text("Enable \(authManager.biometricLabel)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button("Not Now") {
                    gateState.hasPIN = true
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Numpad

    private var numpad: some View {
        VStack(spacing: 12) {
            ForEach(numpadRows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { key in
                        numpadButton(key)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 32)
    }

    private var numpadRows: [[String]] {
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "del"]]
    }

    @ViewBuilder
    private func numpadButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 72, height: 52)
        } else if key == "del" {
            Button {
                guard !enteredDigits.isEmpty else { return }
                enteredDigits.removeLast()
                errorMessage = nil
                haptic.impactOccurred()
            } label: {
                Image(systemName: "delete.backward")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 72, height: 52)
            }
        } else {
            Button {
                digitTapped(key)
            } label: {
                Text(key)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 72, height: 52)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Logic

    private func digitTapped(_ digit: String) {
        guard enteredDigits.count < 4 else { return }
        haptic.impactOccurred()
        enteredDigits += digit
        errorMessage = nil

        if enteredDigits.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                handleComplete()
            }
        }
    }

    private func handleComplete() {
        switch phase {
        case .createPIN:
            newPIN = enteredDigits
            enteredDigits = ""
            phase = .confirmPIN

        case .confirmPIN:
            if enteredDigits == newPIN {
                _ = KeychainService.savePin(newPIN)
                pinSaved = true

                if authManager.isAvailable {
                    // Show biometric opt-in
                    withAnimation { phase = .biometric }
                } else {
                    // No biometrics — done
                    gateState.hasPIN = true
                    dismiss()
                }
            } else {
                newPIN = ""
                showError("PINs don't match. Try again.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    phase = .createPIN
                }
            }

        case .biometric:
            break
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        enteredDigits = ""
        let errorHaptic = UINotificationFeedbackGenerator()
        errorHaptic.notificationOccurred(.error)
        withAnimation(.default.speed(3).repeatCount(3, autoreverses: true)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shake = false
        }
    }
}

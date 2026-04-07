import SwiftUI

// MARK: - Lock Screen Mode

enum LockScreenMode {
    case appLock
    case pinOnly(onCancel: () -> Void)
}

// MARK: - Lock Screen View

struct LockScreenView: View {
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(\.dismiss) private var dismiss

    let mode: LockScreenMode
    let onSuccess: () -> Void

    @State private var enteredDigits = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var showForgotConfirm = false

    private let reduceMotion = UIAccessibility.isReduceMotionEnabled
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Group {
            switch mode {
            case .appLock:
                lockContent
            case .pinOnly:
                NavigationStack {
                    lockContent
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    if case .pinOnly(let onCancel) = mode {
                                        onCancel()
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
            }
        }
        .task {
            haptic.prepare()
            if authManager.failedPINAttempts >= 5 { return }

            // For app lock, try biometric silently — numpad is already visible behind the system dialog
            if case .appLock = mode, authManager.isEnabled {
                let success = await authManager.authenticate()
                if success { onSuccess() }
            }
        }
        .accessibilityIdentifier("LockScreenView")
    }

    // MARK: - Main Content

    private var lockContent: some View {
        ZStack {
            // Blur the app content behind
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            if authManager.failedPINAttempts >= 5 {
                lockoutContent
            } else {
                pinContent
            }
        }
        .confirmationDialog(
            "Forgot your PIN?",
            isPresented: $showForgotConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign In Again", role: .destructive) {
                authManager.onForceLogout?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again and set a new PIN. Your funds are safe.")
        }
    }

    // MARK: - PIN Entry

    private var pinContent: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Numpad sizing — proportional with clamps
            let btnSize = clamp(56, width * 0.22, 80)
            let btnGap = clamp(10, btnSize * 0.18, 20)
            let numpadWidth = btnSize * 3 + btnGap * 2
            let sidePadding = (width - numpadWidth) / 2

            // Vertical spacing — proportional with clamps
            let headerToNumpad = clamp(24, height * 0.05, 60)
            let numpadToFooter = clamp(24, height * 0.04, 48)
            let footerToBottom = clamp(12, height * 0.02, 24)

            VStack(spacing: 0) {
                // Upper breathing room — yields when space is tight
                Spacer(minLength: 16)

                // Header
                VStack(spacing: 14) {
                    Image("NolaMark")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Nola")

                    Text("Enter PIN")
                        .font(.title3.weight(.regular))

                    // PIN dots
                    HStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { index in
                            let filled = index < enteredDigits.count
                            Circle()
                                .fill(filled ? Color.primary : .clear)
                                .frame(width: 13, height: 13)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(filled ? 0 : 0.4), lineWidth: 1.5)
                                )
                                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: enteredDigits.count)
                                .accessibilityLabel("Digit \(index + 1) \(filled ? "entered" : "empty")")
                        }
                    }
                    .offset(x: shakeOffset)

                    // Error / attempts
                    VStack(spacing: 4) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .transition(.opacity)
                        }
                        if authManager.failedPINAttempts > 0 {
                            Text("\(5 - authManager.failedPINAttempts) of 5 attempts remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 32)
                    .animation(.default, value: errorMessage)
                }

                Spacer()
                    .frame(minHeight: headerToNumpad * 0.5, idealHeight: headerToNumpad, maxHeight: headerToNumpad)

                // Numpad — 4×3 grid, biometric in bottom-left
                numpad(buttonSize: btnSize, spacing: btnGap)

                // Space between numpad and footer — compresses on tight screens
                Spacer(minLength: 16)

                // Footer
                Button("Forgot PIN?") {
                    showForgotConfirm = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Spacer()
                    .frame(minHeight: footerToBottom, maxHeight: footerToBottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, sidePadding)
        }
    }

    // MARK: - Lockout

    private var lockoutContent: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red.opacity(0.8))
                .accessibilityLabel("Locked out")

            VStack(spacing: 8) {
                Text("Too Many Attempts")
                    .font(.title3.weight(.semibold))

                Text("You've been locked out for security.\nSign in again to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                authManager.onForceLogout?()
            } label: {
                Text("Sign In Again")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Numpad

    private static let numpadRows = [
        ["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["bio", "0", "del"],
    ]

    private func numpad(buttonSize: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Self.numpadRows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { key in
                        numpadButton(key, size: buttonSize)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func numpadButton(_ key: String, size: CGFloat) -> some View {
        if key == "bio" {
            // Biometric button — bottom-left, plain (no glass, like delete)
            if authManager.isEnabled {
                Button {
                    Task {
                        let success = await authManager.authenticate()
                        if success { onSuccess() }
                    }
                } label: {
                    Image(systemName: authManager.biometricIcon)
                        .font(.system(size: size * 0.35, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(authManager.biometricLabel)")
            } else {
                Color.clear
                    .frame(width: size, height: size)
            }
        } else if key == "del" {
            Button {
                guard !enteredDigits.isEmpty else { return }
                enteredDigits.removeLast()
                errorMessage = nil
                haptic.impactOccurred()
            } label: {
                Image(systemName: "delete.backward")
                    .font(.system(size: size * 0.28, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        } else {
            Button {
                digitTapped(key)
            } label: {
                Text(key)
                    .font(.system(size: size * 0.38, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
            }
            .tint(.primary)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel(key)
        }
    }

    // MARK: - Logic

    private func digitTapped(_ digit: String) {
        guard enteredDigits.count < 4 else { return }
        haptic.impactOccurred()
        enteredDigits += digit
        errorMessage = nil

        if enteredDigits.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if authManager.verifyPIN(enteredDigits) {
                    onSuccess()
                } else {
                    triggerShake()
                    if authManager.failedPINAttempts < 5 {
                        errorMessage = "Incorrect PIN"
                    }
                    enteredDigits = ""
                }
            }
        }
    }

    private func triggerShake() {
        let errorHaptic = UINotificationFeedbackGenerator()
        errorHaptic.notificationOccurred(.error)

        guard !reduceMotion else { return }
        withAnimation(.default.speed(4).repeatCount(3, autoreverses: true)) {
            shakeOffset = -10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { shakeOffset = 0 }
        }
    }

    // MARK: - Helpers

    private func clamp(_ min: CGFloat, _ value: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}

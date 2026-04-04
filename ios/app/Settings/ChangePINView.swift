import SwiftUI

struct ChangePINView: View {
    @Environment(\.dismiss) var dismiss

    @State private var step: PINStep = .create
    @State private var enteredDigits = ""
    @State private var newPIN = ""
    @State private var errorMessage: String?
    @State private var shake = false
    @State private var success = false

    @FocusState private var fieldFocused: Bool

    private enum PINStep: String {
        case create, confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            pinContent
            Spacer()
            numpad
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(Text("Change PIN"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: enteredDigits)
        .sensoryFeedback(.success, trigger: success)
        .sensoryFeedback(.error, trigger: errorMessage)
    }

    // MARK: - PIN Content

    private var pinContent: some View {
        VStack(spacing: 24) {
            // Icon
            iconView

            // Title + subtitle
            VStack(spacing: 6) {
                Text(stepTitle)
                    .font(.title3.weight(.semibold))
                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Dots
            dotIndicator
                .offset(x: shake ? -8 : 0)

            // Error
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 40)
        .animation(.default, value: step)
        .animation(.default, value: errorMessage)
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(success ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
                .frame(width: 64, height: 64)

            Image(systemName: success ? "lock.open.fill" : "lock.fill")
                .font(.title2)
                .foregroundStyle(success ? .green : Color.accentColor)
        }
    }

    private var dotIndicator: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < enteredDigits.count ? Color.primary : Color(.tertiarySystemFill))
                    .frame(width: 14, height: 14)
                    .scaleEffect(index < enteredDigits.count ? 1.0 : 0.85)
                    .animation(.easeOut(duration: 0.12), value: enteredDigits.count)
            }
        }
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
        [["1","2","3"], ["4","5","6"], ["7","8","9"], ["","0","del"]]
    }

    @ViewBuilder
    private func numpadButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 72, height: 72)
        } else if key == "del" {
            Button {
                guard !enteredDigits.isEmpty else { return }
                enteredDigits.removeLast()
                errorMessage = nil
            } label: {
                Image(systemName: "delete.backward")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 72, height: 72)
            }
        } else {
            Button {
                digitTapped(key)
            } label: {
                Text(key)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .tint(.primary)
        }
    }

    // MARK: - Logic

    private var stepTitle: String {
        switch step {
        case .create: return "Enter New PIN"
        case .confirm: return "Confirm New PIN"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .create: return "Choose a new 4-digit PIN"
        case .confirm: return "Enter your new PIN again"
        }
    }

    private func digitTapped(_ digit: String) {
        guard enteredDigits.count < 4, !success else { return }
        enteredDigits += digit
        errorMessage = nil

        if enteredDigits.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                handleComplete()
            }
        }
    }

    private func handleComplete() {
        switch step {
        case .create:
            newPIN = enteredDigits
            enteredDigits = ""
            step = .confirm

        case .confirm:
            if enteredDigits == newPIN {
                _ = KeychainService.savePin(newPIN)
                success = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismiss()
                }
            } else {
                newPIN = ""
                showError("PINs don't match. Try again.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    step = .create
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        enteredDigits = ""
        withAnimation(.default.speed(3).repeatCount(3, autoreverses: true)) {
            shake = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shake = false
        }
    }
}

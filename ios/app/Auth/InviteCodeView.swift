import SwiftUI
import PrivySDK

enum InviteScreenState {
    case enterCode
    case validating
    case codeAccepted
    case joiningWaitlist
    case waitlisted
}

struct InviteCodeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gateState: AppGateState

    @State private var screenState: InviteScreenState = .enterCode
    @State private var digits: [String] = Array(repeating: "", count: 5)
    @State private var focusedIndex: Int = 0
    @State private var errorMessage: String?
    @State private var showWaitlistConfirm = false

    // Entrance animations
    @State private var logoVisible = false
    @State private var contentVisible = false
    @State private var footerVisible = false

    private var codeString: String { digits.joined() }
    private var isCodeComplete: Bool { codeString.count == 5 }

    var body: some View {
        NavigationStack {
            Group {
                switch screenState {
                case .enterCode, .validating:
                    enterCodeView
                case .codeAccepted:
                    codeAcceptedView
                case .joiningWaitlist:
                    ProgressView()
                case .waitlisted:
                    waitlistedView
                }
            }
            .navigationTitle(Text("Nola"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await gateState.logout(appState: appState) }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Join Waitlist", isPresented: $showWaitlistConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Join") {
                Task { await joinWaitlist() }
            }
        } message: {
            if let email = userEmail {
                Text("We'll add \(email) to our waitlist and notify you when a spot opens up.")
            } else {
                Text("We'll add you to our waitlist and notify you when a spot opens up.")
            }
        }
        .sensoryFeedback(.error, trigger: errorMessage)
    }

    // MARK: - Enter Code View

    private var enterCodeView: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: geo.size.height * 0.08)

                            // Logo
                            let logoSize: CGFloat = 72
                            Image("NolaMark")
                                .resizable()
                                .frame(width: logoSize, height: logoSize)
                                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25, style: .continuous))
                                .shadow(color: Color.accentColor.opacity(0.2), radius: 24, x: 0, y: 10)
                                .scaleEffect(logoVisible ? 1 : 0.8)
                                .opacity(logoVisible ? 1 : 0)
                                .padding(.bottom, 20)

                            // Title
                            VStack(spacing: 8) {
                                Text("Enter Invite Code")
                                    .font(.title2.weight(.bold))

                                Text("Nola is invite-only. Enter your\n5-character code to get started.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(2)
                            }
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 8)
                            .padding(.bottom, 32)

                            // Code input boxes
                            codeInputBoxes
                                .opacity(contentVisible ? 1 : 0)
                                .offset(y: contentVisible ? 0 : 8)
                                .padding(.horizontal, 32)

                            // Error
                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.top, 12)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Loading indicator during validation
                            if screenState == .validating {
                                ProgressView()
                                    .padding(.top, 24)
                            }

                            Spacer(minLength: 40)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                }

                // Waitlist footer
                VStack(spacing: 6) {
                        Text("Don't have a code?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Join the Waitlist") {
                            showWaitlistConfirm = true
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    }
                    .opacity(footerVisible ? 1 : 0)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { logoVisible = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.15)) { contentVisible = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { footerVisible = true }
        }
    }

    // MARK: - Code Input Boxes

    private var codeInputBoxes: some View {
        HStack(spacing: 10) {
            ForEach(0..<5, id: \.self) { index in
                let isFocused = focusedIndex == index
                let hasValue = index < digits.count && !digits[index].isEmpty

                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isFocused ? Color.accentColor : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .shadow(
                            color: isFocused ? Color.accentColor.opacity(0.15) : .clear,
                            radius: 8, x: 0, y: 2
                        )

                    Text(hasValue ? digits[index] : "")
                        .font(.title2.monospaced().weight(.bold))
                        .foregroundStyle(.primary)
                }
                .frame(height: 56)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
        }
        .overlay {
            // Hidden text field to capture keyboard input
            InviteCodeTextField(
                digits: $digits,
                focusedIndex: $focusedIndex,
                isDisabled: screenState == .validating,
                onComplete: { Task { await submitCode() } }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
        }
    }

    // MARK: - Code Accepted View

    private var codeAcceptedView: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 16) {
                Spacer()

                ZStack {
                    ConfettiView()

                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: screenState)

                        Text("You're In!")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Your invite code has been accepted.\nLet's set up your account.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                }

                Spacer()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            gateState.invited = true
        }
    }

    // MARK: - Waitlisted View

    private var waitlistedView: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 16) {
                Spacer()

                PulsingRingsView(icon: "clock.badge.checkmark.fill", iconSize: 48)
                    .floating()

                Text("You're on the List!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 8)

                if let email = userEmail {
                    Text("We'll notify you at **\(email)** when your spot is ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 32)
                } else {
                    Text("We'll notify you when your spot is ready.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button("Already have a code?") {
                    withAnimation {
                        screenState = .enterCode
                        errorMessage = nil
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Actions

    private func submitCode() async {
        guard isCodeComplete else { return }

        withAnimation { errorMessage = nil }
        screenState = .validating

        do {
            let service = InviteService(tokenProvider: getAccessToken)
            let response = try await service.redeemCode(codeString)

            if response.success {
                withAnimation { screenState = .codeAccepted }
            } else {
                withAnimation { errorMessage = response.message }
                screenState = .enterCode
            }
        } catch {
            withAnimation { errorMessage = error.localizedDescription }
            screenState = .enterCode
        }
    }

    private func joinWaitlist() async {
        guard let email = userEmail else { return }

        screenState = .joiningWaitlist

        do {
            let service = WaitlistService()
            try await service.join(email: email, source: "ios-app")
            withAnimation { screenState = .waitlisted }
        } catch {
            withAnimation { errorMessage = "Failed to join waitlist. Please try again." }
            screenState = .enterCode
        }
    }

    // MARK: - Helpers

    private var userEmail: String? {
        guard let user = appState.privy.user else { return nil }
        for account in user.linkedAccounts {
            if case .email(let emailAccount) = account {
                return emailAccount.email
            }
        }
        return nil
    }

    private func getAccessToken() async throws -> String {
        let authState = await appState.privy.getAuthState()
        switch authState {
        case .authenticated(let user):
            return try await user.getAccessToken()
        default:
            throw InviteError.notAuthenticated
        }
    }
}

// MARK: - Hidden TextField for Code Input

private struct InviteCodeTextField: UIViewRepresentable {
    @Binding var digits: [String]
    @Binding var focusedIndex: Int
    let isDisabled: Bool
    let onComplete: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .asciiCapable
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.textContentType = .oneTimeCode
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        // Auto-focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.isEnabled = !isDisabled
        // Sync the text field with digits state
        let current = digits.joined()
        if uiView.text != current {
            uiView.text = current
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        let parent: InviteCodeTextField

        init(_ parent: InviteCodeTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            // Force uppercase, only allow alphanumeric, max 5
            let raw = field.text ?? ""
            let filtered = String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(5))

            if field.text != filtered {
                field.text = filtered
            }

            // Update digits array
            var newDigits = Array(repeating: "", count: 5)
            for (i, char) in filtered.enumerated() {
                newDigits[i] = String(char)
            }
            parent.digits = newDigits
            parent.focusedIndex = min(filtered.count, 4)

            // Auto-submit when 5 characters entered
            if filtered.count == 5 {
                parent.onComplete()
            }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            let newLength = current.count + string.count - range.length
            return newLength <= 5
        }
    }
}

// MARK: - Error

private enum InviteError: LocalizedError {
    case notAuthenticated
    var errorDescription: String? { "Not authenticated. Please sign in again." }
}

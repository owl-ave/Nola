import SwiftUI
import AuthenticationServices
import PrivySDK

enum LoginStep {
    case email
    case otp(email: String)
    case verifying
}

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gateState: AppGateState

    @State private var step: LoginStep = .email
    @State private var emailInput = ""
    @State private var otpDigits: [String] = Array(repeating: "", count: 6)
    @State private var focusedDigit: Int = 0
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isSendingCode = false
    @State private var oauthProvider: String?

    // Entrance
    @State private var logoVisible = false
    @State private var contentVisible = false
    @State private var footerVisible = false

    @State private var keyboardUp = false
    @State private var legalURL: URL?

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                GeometryReader { geo in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer(minLength: keyboardUp ? 24 : geo.size.height * 0.12)

                            let logoSize: CGFloat = keyboardUp ? 48 : (isOTPStep ? 56 : 80)
                            Image("NolaMark")
                                .resizable()
                                .frame(width: logoSize, height: logoSize)
                                .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25, style: .continuous))
                                .shadow(color: Color.accentColor.opacity(0.2), radius: 24, x: 0, y: 10)
                                .scaleEffect(logoVisible ? 1 : 0.8)
                                .opacity(logoVisible ? 1 : 0)

                            Group {
                                switch step {
                                case .email:
                                    emailView
                                case .otp(let email):
                                    otpView(email: email)
                                case .verifying:
                                    verifyingView
                                }
                            }
                            .padding(.top, keyboardUp ? 16 : 24)
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 12)

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                }

                // Footer — pinned to bottom
                VStack(spacing: 6) {
                    Text("By continuing, you agree to our")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        Button("Terms of Service") {
                            legalURL = URL(string: "https://nl-landing.pages.dev/terms")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor.opacity(0.7))

                        Text("and")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Button("Privacy Policy") {
                            legalURL = URL(string: "https://nl-landing.pages.dev/privacy")
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                }
                .padding(.vertical, 12)
                .opacity(footerVisible ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: keyboardUp)
        .animation(.easeInOut(duration: 0.35), value: isOTPStep)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .onAppear { animateEntrance() }
        .fullScreenCover(isPresented: Binding(
            get: { legalURL != nil },
            set: { if !$0 { legalURL = nil } }
        )) {
            if let url = legalURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sensoryFeedback(.error, trigger: errorMessage)
    }

    private var isOTPStep: Bool {
        if case .otp = step { return true }
        if case .verifying = step { return true }
        return false
    }

    // MARK: - Email Step

    @FocusState private var emailFieldFocused: Bool

    private var emailView: some View {
        VStack(spacing: keyboardUp ? 6 : 10) {
            Text("nola")
                .font(.system(size: keyboardUp ? 24 : 34, weight: .bold, design: .rounded))
                .tracking(4)

            if !keyboardUp {
                Text("Your intelligent\nfinancial account")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(spacing: 12) {
                // Email input + continue button
                HStack(spacing: 0) {
                    TextField("Email address", text: $emailInput)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($emailFieldFocused)
                        .padding(.leading, 16)
                        .padding(.vertical, 14)
                        .onSubmit { Task { await sendCode() } }

                    Button {
                        Task { await sendCode() }
                    } label: {
                        Group {
                            if isSendingCode {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(emailIsValid ? Color.accentColor : Color.accentColor.opacity(0.3))
                        )
                    }
                    .disabled(!emailIsValid || isSendingCode)
                    .padding(.trailing, 6)
                    .animation(.easeInOut(duration: 0.2), value: emailIsValid)
                }
                .background(Color(.systemGray6).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Divider
                HStack {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                    Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                }
                .padding(.top, keyboardUp ? 8 : 20)

                if keyboardUp {
                    // Compact: side-by-side icon buttons
                    HStack(spacing: 12) {
                        // Apple
                        Button {
                            Task { await loginWithOAuth(.apple) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 16, weight: .medium))
                                Text("Apple")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .opacity(oauthProvider != nil ? 0.5 : 1)
                        .disabled(oauthProvider != nil)

                        // Google
                        Button {
                            Task { await loginWithOAuth(.google) }
                        } label: {
                            HStack(spacing: 8) {
                                if oauthProvider == "google" {
                                    ProgressView().tint(.black)
                                } else {
                                    Image("GoogleLogo")
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                Text("Google")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .opacity(oauthProvider != nil ? 0.5 : 1)
                        .disabled(oauthProvider != nil)
                    }
                    .transition(.opacity)
                } else {
                    // Full: stacked buttons
                    SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                        .allowsHitTesting(false)
                        .overlay {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await loginWithOAuth(.apple) }
                                }
                        }
                        .opacity(oauthProvider != nil ? 0.5 : 1)
                        .disabled(oauthProvider != nil)

                    Button {
                        Task { await loginWithOAuth(.google) }
                    } label: {
                        HStack(spacing: 10) {
                            if oauthProvider == "google" {
                                ProgressView().tint(.black)
                            } else {
                                Image("GoogleLogo")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                            }
                            Text("Continue with Google")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    }
                    .opacity(oauthProvider != nil ? 0.5 : 1)
                    .disabled(oauthProvider != nil)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, keyboardUp ? 16 : 32)
        }
        .animation(.easeInOut(duration: 0.3), value: keyboardUp)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                emailFieldFocused = true
            }
        }
    }

    private var emailIsValid: Bool {
        let email = emailInput.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - OTP Step

    private func otpView(email: String) -> some View {
        VStack(spacing: 10) {
            Text("Check your email")
                .font(.title3.weight(.semibold))

            HStack(spacing: 4) {
                Text("Code sent to")
                    .foregroundStyle(.secondary)
                Text(email)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
            }
            .font(.subheadline)

            // 6-digit OTP input
            OTPField(digits: $otpDigits, focusedIndex: $focusedDigit) {
                Task { await verifyCode(email: email) }
            }
            .padding(.top, 20)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .padding(.top, 4)
            }

            // Resend + Change email
            HStack(spacing: 16) {
                Button("Resend code") {
                    Task { await resendCode(email: email) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .disabled(isSendingCode)

                Text("·")
                    .foregroundStyle(.tertiary)

                Button("Change email") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        errorMessage = nil
                        otpDigits = Array(repeating: "", count: 6)
                        focusedDigit = 0
                        step = .email
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Verifying

    private var verifyingView: some View {
        VStack(spacing: 16) {
            BrandedSpinner()
            Text("Signing in...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity)
    }

    // MARK: - Entrance Animation

    private func animateEntrance() {
        withAnimation(.easeOut(duration: 0.6)) {
            logoVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            contentVisible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            footerVisible = true
        }
    }

    // MARK: - Auth Actions

    private func loginWithOAuth(_ provider: OAuthProvider) async {
        let providerName = provider == .apple ? "apple" : "google"
        oauthProvider = providerName
        errorMessage = nil
        do {
            let user = try await appState.privy.oAuth.login(
                with: provider,
                appUrlScheme: "nola"
            )
            _ = try await user.getAccessToken()
            await gateState.resolveState(appState: appState)
        } catch {
            // Don't show error if user cancelled
            let desc = error.localizedDescription
            if !desc.lowercased().contains("cancel") {
                errorMessage = desc
            }
        }
        oauthProvider = nil
    }

    private func sendCode() async {
        guard emailIsValid else {
            errorMessage = "Please enter a valid email address"
            return
        }
        let email = emailInput.trimmingCharacters(in: .whitespaces)
        errorMessage = nil
        isSendingCode = true
        do {
            try await appState.privy.email.sendCode(to: email)
            isSendingCode = false
            otpDigits = Array(repeating: "", count: 6)
            focusedDigit = 0
            withAnimation(.easeInOut(duration: 0.3)) {
                step = .otp(email: email)
            }
        } catch {
            isSendingCode = false
            errorMessage = error.localizedDescription
        }
    }

    private func resendCode(email: String) async {
        isSendingCode = true
        errorMessage = nil
        do {
            try await appState.privy.email.sendCode(to: email)
            isSendingCode = false
        } catch {
            isSendingCode = false
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode(email: String) async {
        let code = otpDigits.joined()
        guard code.count == 6 else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            step = .verifying
        }
        do {
            let user = try await appState.privy.email.loginWithCode(code, sentTo: email)
            _ = try await user.getAccessToken()
            await gateState.resolveState(appState: appState)
        } catch {
            withAnimation(.easeInOut(duration: 0.25)) {
                step = .otp(email: email)
            }
            errorMessage = error.localizedDescription
            otpDigits = Array(repeating: "", count: 6)
            focusedDigit = 0
        }
    }
}

// MARK: - OTP Field (6 individual digit boxes)

struct OTPField: View {
    @Binding var digits: [String]
    @Binding var focusedIndex: Int
    var onComplete: () -> Void

    // Hidden text field to capture keyboard input
    @FocusState private var isFieldFocused: Bool
    @State private var combinedText = ""

    var body: some View {
        ZStack {
            // Hidden input to capture keyboard
            TextField("", text: $combinedText)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFieldFocused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .onChange(of: combinedText) { _, newValue in
                    handleInput(newValue)
                }

            // Visual digit boxes
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(index: index)
                        .onTapGesture {
                            isFieldFocused = true
                        }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFieldFocused = true
            }
        }
    }

    private func digitBox(index: Int) -> some View {
        let hasDigit = !digits[index].isEmpty
        let isActive = index == focusedIndex && isFieldFocused

        return Text(digits[index])
            .font(.title2.weight(.semibold).monospaced())
            .frame(width: 48, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.systemGray6).opacity(hasDigit ? 1 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isActive ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .overlay {
                if isActive && !hasDigit {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 24)
                        .blinking()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: hasDigit)
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private func handleInput(_ text: String) {
        let filtered = String(text.filter { $0.isNumber }.prefix(6))

        // Update digits
        for i in 0..<6 {
            if i < filtered.count {
                digits[i] = String(filtered[filtered.index(filtered.startIndex, offsetBy: i)])
            } else {
                digits[i] = ""
            }
        }

        // Update focus
        focusedIndex = min(filtered.count, 5)

        // Keep combinedText in sync
        if filtered != text {
            combinedText = filtered
        }

        // Auto-submit on 6 digits
        if filtered.count == 6 {
            isFieldFocused = false
            onComplete()
        }
    }
}

// MARK: - Blinking cursor

struct BlinkingModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

extension View {
    func blinking() -> some View {
        modifier(BlinkingModifier())
    }
}

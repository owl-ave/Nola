import Sentry
import SwiftUI
import PrivySDK

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager

    @State private var displayName = ""
    @State private var tokenCopied = false
    @State private var showDisableBiometricAuth = false
    @State private var confirmDisableBiometric = false
    @State private var isLoading = true
    @State private var errorAlert: String?
    @State private var showFeedback = false
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    @State private var showLanguagePicker = false

    var body: some View {
        Form {
            // MARK: - Profile
            Section {
                if isLoading {
                    profileSkeleton
                } else {
                    NavigationLink(value: SettingsDestination.profile) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                Text(initials)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName.isEmpty ? "Nola User" : displayName)
                                    .font(.body.weight(.semibold))
                                if let email = userEmail {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // MARK: - Security
            Section("Security") {
                NavigationLink(value: SettingsDestination.changePIN) {
                    Label { Text("Change PIN") } icon: {
                        SettingsIcon(name: "lock.rectangle", color: .orange)
                    }
                }
                if authManager.isAvailable {
                    Toggle(isOn: Binding(
                        get: { authManager.isEnabled },
                        set: { newValue in
                            if newValue {
                                Task { _ = await authManager.enable() }
                            } else {
                                confirmDisableBiometric = true
                            }
                        }
                    )) {
                        Label { Text(authManager.biometricLabel) } icon: {
                            SettingsIcon(name: authManager.biometricIcon, color: Color.accentColor)
                        }
                    }
                    .tint(Color.accentColor)
                }
                NavigationLink(value: SettingsDestination.exportWallet) {
                    Label { Text("Export Wallet") } icon: {
                        SettingsIcon(name: "key.fill", color: .purple)
                    }
                }
            }

            // MARK: - AI Assistant
            Section("AI Assistant") {
                NavigationLink(value: SettingsDestination.aiPermissions) {
                    Label { Text("AI Permissions") } icon: {
                        SettingsIcon(name: "sparkles", color: Color.accentColor)
                    }
                }
            }

            // MARK: - Card Preferences
            Section("Card Preferences") {
                NavigationLink(value: SettingsDestination.autoEarn) {
                    Label { Text("Auto Earn") } icon: {
                        SettingsIcon(name: "arrow.up.circle", color: .blue)
                    }
                }
            }

            // MARK: - Language
            Section("Language") {
                Button {
                    showLanguagePicker = true
                } label: {
                    Label {
                        HStack {
                            Text("Language")
                            Spacer()
                            Text(languageDisplayName)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        SettingsIcon(name: "globe", color: .indigo)
                    }
                }
                .tint(.primary)
            }

            // MARK: - App
            Section("App") {
                Button {
                    showFeedback = true
                } label: {
                    Label { Text("Report a Bug") } icon: {
                        SettingsIcon(name: "ant", color: .green)
                    }
                }
                .tint(.primary)

                NavigationLink(value: SettingsDestination.support) {
                    Label { Text("Support") } icon: {
                        SettingsIcon(name: "questionmark.bubble", color: .blue)
                    }
                }

                NavigationLink(value: SettingsDestination.notifications) {
                    Label { Text("Notifications") } icon: {
                        SettingsIcon(name: "bell.badge", color: .red)
                    }
                }

                LabeledContent {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } label: {
                    Label { Text("Version") } icon: {
                        SettingsIcon(name: "info.circle", color: .secondary)
                    }
                }

                #if DEBUG
                    Button {
                        Task {
                            if let token = try? await appState.privy.getUser()?.getAccessToken() {
                                UIPasteboard.general.string = token
                                tokenCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    tokenCopied = false
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(tokenCopied ? "Token Copied!" : "Copy Access Token")
                                .foregroundStyle(tokenCopied ? .green : .primary)
                        } icon: {
                            SettingsIcon(
                                name: tokenCopied ? "checkmark.circle.fill" : "key",
                                color: tokenCopied ? .green : .orange
                            )
                        }
                    }
                    .tint(.primary)
                #endif
            }

        }
        .navigationTitle(Text("Settings"))
        .sensoryFeedback(.impact(weight: .medium), trigger: showFeedback)
        .sensoryFeedback(.impact(weight: .medium), trigger: showLanguagePicker)
        .refreshable { await loadProfile() }
        .task {
            await loadProfile()
        }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(userName: displayName.isEmpty ? nil : displayName)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showDisableBiometricAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showDisableBiometricAuth = false })) {
                    showDisableBiometricAuth = false
                    authManager.disable()
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .alert("Disable \(authManager.biometricLabel)?", isPresented: $confirmDisableBiometric) {
            Button("Disable", role: .destructive) {
                Task {
                    if await authManager.authenticate() {
                        authManager.disable()
                    } else {
                        showDisableBiometricAuth = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your PIN to unlock the app and confirm sensitive actions.")
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                selectedLanguage: $preferredLanguage,
                isPresented: $showLanguagePicker
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Profile Skeleton

    private var profileSkeleton: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 60, height: 60)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 16)
                    .shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 160, height: 13)
                    .shimmer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    private var userEmail: String? {
        guard let user = appState.privy.user else { return nil }
        for account in user.linkedAccounts {
            if case .email(let emailAccount) = account {
                return emailAccount.email
            }
        }
        return nil
    }

    private var languageDisplayName: String {
        switch preferredLanguage {
        case "ja": return "日本語"
        case "ar": return "العربية"
        case "de": return "Deutsch"
        default: return "English"
        }
    }

    private func loadProfile() async {
        let isInitialLoad = displayName.isEmpty
        if isInitialLoad { isLoading = true }
        struct ProfileResponse: Decodable {
            let user: UserProfile
        }
        struct UserProfile: Decodable {
            let firstName: String?
            let lastName: String?
        }
        do {
            let response: ProfileResponse = try await appState.apiClient.request("GET", path: "/v1/user/profile")
            displayName = [response.user.firstName, response.user.lastName]
                .compactMap { $0 }
                .joined(separator: " ")
        } catch {
            print("[Settings] profile error: \(error)")
            if isInitialLoad { errorAlert = "Failed to load profile." }
        }
        if isInitialLoad { isLoading = false }
    }
}

// MARK: - Settings Icon

private struct SettingsIcon: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct LanguagePickerSheet: View {
    @Binding var selectedLanguage: String
    @Binding var isPresented: Bool
    @EnvironmentObject var appState: AppState

    private let languages: [(id: String, name: String)] = [
        ("en", "English"),
        ("ja", "日本語"),
        ("ar", "العربية"),
        ("de", "Deutsch"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(languages, id: \.id) { lang in
                    Button {
                        selectedLanguage = lang.id
                        appState.apiClient.language = lang.id
                        syncLanguageToBackend(lang.id)
                        isPresented = false
                    } label: {
                        HStack(spacing: 14) {
                            Text(lang.name)
                                .font(.body)
                            Spacer()
                            if selectedLanguage == lang.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle(Text("Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func syncLanguageToBackend(_ lang: String) {
        Task {
            struct LangUpdate: Encodable { let language: String }
            struct LangResponse: Decodable {}
            do {
                let _: LangResponse = try await appState.apiClient.request(
                    "PATCH", path: "/v1/settings",
                    body: LangUpdate(language: lang)
                )
            } catch {
                print("[Settings] language sync failed: \(error)")
            }
        }
    }
}

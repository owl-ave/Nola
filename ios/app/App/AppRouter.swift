import Combine
import Sentry
import SwiftUI
import UIKit
import PrivySDK
import UserNotifications
import FirebaseAnalytics
import FirebaseMessaging

// MARK: - Gate

enum Gate {
    case language, loading, login, inviteCode, pinSetup, notifications, onboarding, home
}

// MARK: - App Gate State

@MainActor
class AppGateState: ObservableObject {
    @Published var stateResolved = false
    @Published var authenticated = false
    @Published var invited = false
    @Published var hasPIN = false
    @Published var onboardingCompleted = false
    @Published var notificationsPromptDone = false
    @Published var error: String?
    @Published var languageSelected = false

    var activeGate: Gate {
        if !languageSelected { return .language }
        if !stateResolved { return .loading }
        if !authenticated { return .login }
        if !invited { return .inviteCode }
        if !hasPIN { return .pinSetup }
        if !notificationsPromptDone { return .notifications }
        if !onboardingCompleted { return .onboarding }
        return .home
    }

    func resolveState(appState: AppState) async {
        languageSelected = UserDefaults.standard.string(forKey: "preferredLanguage")?.isEmpty == false
        error = nil
        stateResolved = false

        // Check Privy auth
        let authState = await appState.privy.getAuthState()

        switch authState {
        case .authenticated(let user):
            print("[Gate] authenticated, userId=\(user.id)")
            authenticated = true

            // Set user context for per-user Keychain storage
            KeychainService.setCurrentUser(user.id)

            // Link Sentry events to this user
            let sentryUser = Sentry.User(userId: user.id)
            for account in user.linkedAccounts {
                if case .email(let emailAccount) = account {
                    sentryUser.email = emailAccount.email
                    break
                }
            }
            SentrySDK.setUser(sentryUser)

            // Link Firebase Analytics events to this user
            Analytics.setUserID(user.id)

            // Wire up force logout for biometric lockout
            appState.authManager.onForceLogout = { [weak self] in
                Task { @MainActor in
                    if let user = await appState.privy.getUser() {
                        await user.logout()
                    }
                    SentrySDK.setUser(nil)
                    Analytics.setUserID(nil)
                    self?.authenticated = false
                    self?.stateResolved = true
                }
            }

            // Set token provider
            appState.apiClient.tokenProvider = { try await user.getAccessToken() }

            // Verify token
            guard let _ = try? await user.getAccessToken() else {
                print("[Gate] CRITICAL: failed to get access token")
                error = "Failed to get access token"
                return
            }

            // Check Keychain for PIN (setCurrentUser was just called above)
            hasPIN = KeychainService.hasPinSet()

            // Set lock state now that user context is available
            appState.authManager.checkLockState()

            // Verify or register device key
            if hasPIN {
                await ensureDeviceKeyRegistered(userId: user.id, apiClient: appState.apiClient)
            }

            // Fetch profile from backend
            do {
                struct ProfileResponse: Decodable {
                    let user: UserProfile
                }
                struct UserProfile: Decodable {
                    let onboardingStep: String?
                    let invited: Bool?
                }
                let profile: ProfileResponse = try await appState.apiClient.request("GET", path: "/v1/user/profile")
                let step = profile.user.onboardingStep
                invited = profile.user.invited ?? false
                onboardingCompleted = step == "completed"
                // Skip notification gate if user already made a permission decision (authorized or denied)
                notificationsPromptDone = await hasNotificationPermissionDecision()
                print("[Gate] invited=\(invited) onboardingCompleted=\(onboardingCompleted) hasPIN=\(hasPIN) step=\(step ?? "nil")")

                // Sync language preference to backend
                if let lang = UserDefaults.standard.string(forKey: "preferredLanguage"), !lang.isEmpty {
                    Task {
                        struct LangUpdate: Encodable { let language: String }
                        struct LangResponse: Decodable {}
                        do {
                            let _: LangResponse = try await appState.apiClient.request(
                                "PATCH", path: "/v1/settings",
                                body: LangUpdate(language: lang)
                            )
                        } catch {
                            print("[Gate] language sync failed: \(error)")
                        }
                    }
                }

                // Set Firebase Analytics user properties for cohort analysis
                Analytics.setUserProperty(invited ? "true" : "false", forName: "invited")
                Analytics.setUserProperty(step ?? "unknown", forName: "onboarding_step")
            } catch {
                print("[Gate] profile fetch failed: \(error.localizedDescription)")
                self.error = "Failed to load profile. Please try again."
                return
            }

            // Set Firebase Messaging delegate now that auth is ready — token callback will fire
            Messaging.messaging().delegate = UIApplication.shared.delegate as? AppDelegate

            // Re-register push token (token can change between launches)
            let notifSettings = await UNUserNotificationCenter.current().notificationSettings()
            if notifSettings.authorizationStatus == .authorized {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }

            stateResolved = true

        case .unauthenticated, .notReady, .authenticatedUnverified:
            authenticated = false
            stateResolved = true
        @unknown default:
            authenticated = false
            stateResolved = true
        }
    }

    func logout(appState: AppState) async {
        if let user = await appState.privy.getUser() {
            await user.logout()
        }
        SentrySDK.setUser(nil)
        Analytics.setUserID(nil)
        authenticated = false
        invited = false
        onboardingCompleted = false
        notificationsPromptDone = false
        stateResolved = true
    }

    /// Ensure a valid device key is registered with the server.
    /// - If no local key: generate one
    /// - If no keyId stored: register with server
    /// - If keyId stored: verify server still has it, re-register if not
    private func ensureDeviceKeyRegistered(userId: String, apiClient: APIClient) async {
        do {
            // Step 1: Ensure local key exists
            let privateKey: SecKey
            if let existing = DeviceKeyService.getPrivateKey(userId: userId) {
                privateKey = existing
            } else {
                privateKey = try DeviceKeyService.generateKey(userId: userId)
                print("[Auth] Generated new device key")
            }

            // Step 2: Check if server knows about this key AND it matches
            if let keyId = DeviceKeyService.getKeyId(userId: userId),
               let currentPubKey = DeviceKeyService.exportPublicKey(privateKey: privateKey) {
                let encodedKey = currentPubKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                struct VerifyResponse: Decodable { let valid: Bool; let reason: String? }
                let response: VerifyResponse = try await apiClient.request(
                    "GET", path: "/v1/auth/verify-device-key?keyId=\(keyId)&publicKey=\(encodedKey)"
                )
                if response.valid {
                    print("[Auth] Device key verified: \(keyId)")
                    return
                }
                print("[Auth] Device key invalid: \(response.reason ?? "unknown"), re-registering")
            }

            // Step 3: Register (or re-register) with server
            guard let publicKey = DeviceKeyService.exportPublicKey(privateKey: privateKey) else {
                print("[Auth] Failed to export public key")
                return
            }

            struct RegisterKeyRequest: Encodable { let publicKey: String }
            struct RegisterKeyResponse: Decodable { let ok: Bool; let keyId: String? }
            let response: RegisterKeyResponse = try await apiClient.request(
                "POST", path: "/v1/auth/register-device-key",
                body: RegisterKeyRequest(publicKey: publicKey)
            )
            if let keyId = response.keyId {
                DeviceKeyService.storeKeyId(keyId, userId: userId)
                print("[Auth] Device key registered, keyId=\(keyId)")
            }
        } catch {
            print("[Auth] Device key verification/registration failed: \(error)")
        }
    }

    private func hasNotificationPermissionDecision() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus != .notDetermined
    }
}

// MARK: - App Router

struct AppRouter: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @StateObject private var gateState = AppGateState()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"

    var body: some View {
        Group {
            switch gateState.activeGate {
            case .language:
                LanguageGateView {
                    gateState.languageSelected = true
                    appState.apiClient.language = UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"
                }
            case .loading:
                SplashView(status: gateState.error != nil ? "" : "Loading")
                    .overlay {
                        if let error = gateState.error {
                            errorOverlay(error)
                        }
                    }
            case .login:
                LoginView()
            case .inviteCode:
                InviteCodeView()
            case .pinSetup:
                SecuritySetupView()
                    .environmentObject(authManager)
            case .notifications:
                NotificationPermissionView {
                    gateState.notificationsPromptDone = true
                }
                .environmentObject(appState.notificationService)
            case .onboarding:
                ChatOnboardingView()
            case .home:
                MainTabView()
            }
        }
        .environment(\.locale, Locale(identifier: preferredLanguage))
        .environment(\.layoutDirection, Locale.characterDirection(forLanguage: preferredLanguage) == .rightToLeft ? .rightToLeft : .leftToRight)
        .id(preferredLanguage)
        .environmentObject(gateState)
        .overlay {
            // App lock — only on home
            let _ = print("[AppRouter] overlay check: gate=\(gateState.activeGate) isLocked=\(authManager.isLocked)")
            if gateState.activeGate == .home, authManager.isLocked {
                LockScreenView(mode: .appLock) {}
                    .environmentObject(authManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager.isLocked)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, gateState.activeGate == .home {
                authManager.checkLockState()
            }
        }
        .task {
            await gateState.resolveState(appState: appState)
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Something went wrong")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await gateState.resolveState(appState: appState) }
            } label: {
                Text("Retry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .controlSize(.large)
            .padding(.horizontal, 16)

            Button {
                Task { await gateState.logout(appState: appState) }
            } label: {
                Text("Log Out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

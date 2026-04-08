import Combine
import Sentry
import UIKit
import WebKit

import SwiftUI
import PrivySDK
import FirebaseCore
import FirebaseMessaging
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let providerFactory = NolaAppCheckProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)

        FirebaseApp.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Push registration failed: \(error.localizedDescription)")
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("[Firebase] FCM token: \(fcmToken ?? "nil")")
        guard let fcmToken else { return }
        NotificationService.didReceiveFCMToken(fcmToken)
    }
}

class NolaAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

@main
struct NolaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    init() {
        SentrySDK.start { options in
            options.dsn = AppConstants.sentryDSN
            options.sendDefaultPii = true
            options.tracesSampleRate = NSNumber(value: AppConstants.sentryTracesSampleRate)
            options.attachScreenshot = true

            #if DEBUG
            options.debug = false
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif

            options.configureProfiling = {
                $0.sessionSampleRate = 1.0
                $0.lifecycle = .trace
            }

            options.experimental.enableLogs = true

            options.configureUserFeedback = { config in
                config.useShakeGesture = true
                config.configureWidget = { widget in
                    widget.autoInject = false
                }
                config.onSubmitSuccess = { _ in
                    print("[Sentry] Feedback submitted")
                }
                config.onSubmitError = { error in
                    print("[Sentry] Feedback error: \(error)")
                }
            }
        }
    }
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @State private var navigationRouter = NavigationRouter()
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(appState)
                .environmentObject(appState.authManager)
                .environmentObject(appState.notificationService)
                .environment(navigationRouter)
                .environment(\.locale, Locale(identifier: preferredLanguage))
                .environment(\.layoutDirection, Locale.characterDirection(forLanguage: preferredLanguage) == .rightToLeft ? .rightToLeft : .leftToRight)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    print("[NolaApp] scenePhase: \(oldPhase) → \(newPhase)")
                }
                .onOpenURL { url in
                    print("[DeepLink] Received URL: \(url)")
                    if let deepLink = DeepLink.from(url: url) {
                        print("[DeepLink] Parsed: \(deepLink)")
                        navigationRouter.handleDeepLink(deepLink)
                    }
                }
                .onChange(of: preferredLanguage) { _, newValue in
                    appState.apiClient.language = newValue
                }
                .onAppear {
                    appState.apiClient.language = preferredLanguage
                }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    let privy: Privy
    let apiClient: APIClient
    let authManager = BiometricAuthManager()
    let notificationService: NotificationService

    /// Persistent WKWebView for AI chat — survives sheet dismiss/present cycles
    var chatWebView: WKWebView?

    init() {
        let config = PrivyConfig(
            appId: AppConstants.privyAppId,
            appClientId: AppConstants.privyAppClientId
        )
        privy = PrivySdk.initialize(config: config)
        apiClient = APIClient(baseURL: AppConstants.apiBaseURL)
        notificationService = NotificationService(apiClient: apiClient)
        authManager.migrateFromUserDefaults()
    }
}

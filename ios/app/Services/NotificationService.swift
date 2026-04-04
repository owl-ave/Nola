import Combine
import Foundation
import UserNotifications
import UIKit

class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var permissionGranted = false
    @Published var permissionDenied = false

    private static weak var shared: NotificationService?
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        super.init()
        NotificationService.shared = self
        UNUserNotificationCenter.current().delegate = self
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called from AppDelegate when Firebase Messaging produces an FCM token
    static func didReceiveFCMToken(_ fcmToken: String) {
        if let service = shared {
            service.registerFCMToken(fcmToken)
        }
    }

    func checkCurrentStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            permissionGranted = settings.authorizationStatus == .authorized
            permissionDenied = settings.authorizationStatus == .denied
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run {
                permissionGranted = granted
                permissionDenied = !granted
            }
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("[Notifications] Permission request failed: \(error)")
            await MainActor.run {
                permissionDenied = true
            }
            return false
        }
    }

    private func registerFCMToken(_ fcmToken: String) {
        print("[Notifications] FCM token: \(fcmToken)")

        Task {
            do {
                struct TokenRequest: Encodable {
                    let deviceToken: String
                }
                struct TokenResponse: Decodable {
                    let ok: Bool
                }
                let _: TokenResponse = try await apiClient.request(
                    "POST",
                    path: "/v1/user/device-token",
                    body: TokenRequest(deviceToken: fcmToken)
                )
                print("[Notifications] FCM token registered with backend")
            } catch {
                print("[Notifications] Failed to register FCM token: \(error)")
            }
        }
    }
}

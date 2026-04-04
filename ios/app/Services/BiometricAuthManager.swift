import Combine
import Foundation
import LocalAuthentication
import SwiftUI

enum BiometricType {
    case faceID, touchID, none
}

@MainActor
class BiometricAuthManager: ObservableObject {
    @Published var isLocked = false
    @Published private(set) var failedPINAttempts: Int = 0

    private(set) var lastAuthenticatedAt: Date?

    private let lockTimeoutSeconds: TimeInterval = 30

    // Keychain keys for biometric preference and failed attempts
    private let biometricEnabledKey = "com.nola.money.biometricEnabled"
    private let failedAttemptsKey = "com.nola.money.failedPINAttempts"

    /// Callback set by AppRouter to handle forced logout
    var onForceLogout: (() -> Void)?

    init() {
        failedPINAttempts = loadFailedAttempts()
    }

    // MARK: - Device Capability

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    var isAvailable: Bool { biometricType != .none }

    var biometricLabel: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }

    var biometricIcon: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "person.badge.key.fill"
        }
    }

    // MARK: - Biometric Preference (Keychain)

    var isEnabled: Bool {
        loadKeychainBool(biometricEnabledKey)
    }

    func enable() async -> Bool {
        let success = await authenticate()
        if success {
            saveKeychainBool(biometricEnabledKey, value: true)
        }
        return success
    }

    func disable() {
        saveKeychainBool(biometricEnabledKey, value: false)
    }

    // MARK: - Authentication

    func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Nola"
            )
            if success {
                recordAuthentication()
            }
            return success
        } catch {
            return false
        }
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard KeychainService.verifyPin(pin) else {
            failedPINAttempts += 1
            saveFailedAttempts(failedPINAttempts)
            if failedPINAttempts >= 5 {
                forceLogout()
            }
            return false
        }
        // Success — reset counter
        failedPINAttempts = 0
        saveFailedAttempts(0)
        recordAuthentication()
        return true
    }

    func recordAuthentication() {
        lastAuthenticatedAt = Date()
        isLocked = false
    }

    // MARK: - Lock State

    func checkLockState() {
        let hasPin = KeychainService.hasPinSet()
        print("[Lock] checkLockState: hasPin=\(hasPin) lastAuth=\(String(describing: lastAuthenticatedAt)) isLocked=\(isLocked)")
        guard hasPin else {
            print("[Lock] No PIN set, not locking")
            isLocked = false
            return
        }
        guard let lastAuth = lastAuthenticatedAt else {
            // Fresh launch — lock immediately
            print("[Lock] No lastAuth (fresh launch), locking")
            isLocked = true
            return
        }
        let elapsed = Date().timeIntervalSince(lastAuth)
        print("[Lock] Elapsed since last auth: \(elapsed)s (timeout: \(lockTimeoutSeconds)s)")
        if elapsed > lockTimeoutSeconds {
            isLocked = true
        }
    }

    // MARK: - Force Logout

    private func forceLogout() {
        failedPINAttempts = 0
        saveFailedAttempts(0)
        isLocked = false
        KeychainService.deletePin()
        disable()
        onForceLogout?()
    }

    // MARK: - Migration

    func migrateFromUserDefaults() {
        let key = "com.nola.money.faceIdEnabled"
        let wasEnabled = UserDefaults.standard.bool(forKey: key)
        if wasEnabled {
            saveKeychainBool(biometricEnabledKey, value: true)
            UserDefaults.standard.removeObject(forKey: key)
        }
        // Legacy migrations removed — per-user PIN keys only
    }

    // MARK: - Keychain Helpers (Bool)

    private func loadKeychainBool(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return false }
        return str == "1"
    }

    private func saveKeychainBool(_ key: String, value: Bool) {
        let data = (value ? "1" : "0").data(using: .utf8)!
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Keychain Helpers (Int)

    private func loadFailedAttempts() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: failedAttemptsKey,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              let count = Int(str)
        else { return 0 }
        return count
    }

    private func saveFailedAttempts(_ count: Int) {
        let data = "\(count)".data(using: .utf8)!
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: failedAttemptsKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: failedAttemptsKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
}

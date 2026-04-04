import CryptoKit
import Foundation
import Security

class KeychainService {
    private static let pinKeyPrefix = "com.nola.money.pin"
    private static var currentUserId: String?

    static func setCurrentUser(_ userId: String) {
        currentUserId = userId
    }

    private static var pinKey: String? {
        guard let userId = currentUserId else { return nil }
        return "\(pinKeyPrefix).\(userId)"
    }

    // MARK: - PIN Storage (SHA-256 hashed)

    static func savePin(_ pin: String) -> Bool {
        guard let pinKey else { return false }
        let hashed = sha256(pin)
        guard let data = hashed.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func verifyPin(_ pin: String) -> Bool {
        guard let pinKey else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let storedHash = String(data: data, encoding: .utf8)
        else { return false }

        let inputHash = sha256(pin)
        guard storedHash.count == inputHash.count else { return false }
        var mismatch = 0
        for (a, b) in zip(storedHash.utf8, inputHash.utf8) {
            mismatch |= Int(a ^ b)
        }
        return mismatch == 0
    }

    static func deletePin() {
        guard let pinKey else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasPinSet() -> Bool {
        guard let pinKey else {
            print("[Keychain] hasPinSet: no pinKey (currentUserId=\(currentUserId ?? "nil"))")
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKey,
        ]
        let result = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        print("[Keychain] hasPinSet: key=\(pinKey) result=\(result)")
        return result
    }

    // MARK: - Hashing

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

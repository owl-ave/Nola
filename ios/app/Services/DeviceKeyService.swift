import Foundation
import Security

class DeviceKeyService {
    private static func tag(for userId: String) -> String {
        "com.nola.money.device-key.\(userId)"
    }

    /// Generate P-256 key pair in Secure Enclave
    static func generateKey(userId: String) throws -> SecKey {
        let tag = tag(for: userId).data(using: .utf8)!
        let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage, nil
        )!
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return privateKey
    }

    /// Get existing private key from Secure Enclave
    static func getPrivateKey(userId: String) -> SecKey? {
        let tag = tag(for: userId).data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as! SecKey
    }

    /// Check if device key exists for user
    static func hasKey(userId: String) -> Bool {
        getPrivateKey(userId: userId) != nil
    }

    /// Export public key as base64 SPKI DER
    static func exportPublicKey(privateKey: SecKey) -> String? {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return nil }
        let spki = wrapInSPKI(rawKey: data)
        return spki.base64EncodedString()
    }

    /// Sign data with Secure Enclave private key (ECDSA P-256 SHA-256)
    static func sign(data: Data, privateKey: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) else {
            print("[DeviceKey] Signing failed: \(error!.takeRetainedValue())")
            return nil
        }
        return signature as Data
    }

    /// Wrap raw X9.62 uncompressed public key (65 bytes) in SPKI DER encoding
    /// Required because iOS exports raw format but server needs SPKI for Web Crypto API
    private static func wrapInSPKI(rawKey: Data) -> Data {
        // SPKI header for P-256: OID 1.2.840.10045.2.1 (EC) + OID 1.2.840.10045.3.1.7 (P-256)
        let spkiHeader: [UInt8] = [
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86,
            0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
            0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
            0x42, 0x00,
        ]
        var spki = Data(spkiHeader)
        spki.append(rawKey)
        return spki
    }

    // MARK: - Key ID Storage (per-user, in UserDefaults)

    private static func keyIdKey(for userId: String) -> String {
        "com.nola.money.device-key-id.\(userId)"
    }

    static func storeKeyId(_ keyId: String, userId: String) {
        UserDefaults.standard.set(keyId, forKey: keyIdKey(for: userId))
    }

    static func getKeyId(userId: String) -> String? {
        UserDefaults.standard.string(forKey: keyIdKey(for: userId))
    }
}

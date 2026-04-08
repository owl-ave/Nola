import Foundation

class ProtectedActionService {
    private let apiClient: APIClient
    private let userId: String  // internal DB user ID (for DeviceKeyService key lookup)

    init(apiClient: APIClient, userId: String) {
        self.apiClient = apiClient
        self.userId = userId
    }

    struct ActionResult {
        let success: Bool
        let result: [String: Any]?
        let error: String?
    }

    func execute(action: String, params: [String: Any]) async -> ActionResult {
        print("[ProtectedAction] execute: action=\(action) userId=\(userId)")
        do {
            // Step 1: Create challenge
            let challengeResponse = try await createChallenge(action: action, params: params)
            guard let challengeId = challengeResponse["challengeId"] as? String,
                  let payloadBase64 = challengeResponse["payload"] as? String,
                  let payloadData = Data(base64Encoded: payloadBase64) else {
                print("[ProtectedAction] Invalid challenge response: \(challengeResponse)")
                return ActionResult(success: false, result: nil, error: "Invalid challenge response")
            }
            print("[ProtectedAction] Challenge created: \(challengeId) payloadLen=\(payloadData.count)")

            // Step 2: Sign with Secure Enclave
            guard let privateKey = DeviceKeyService.getPrivateKey(userId: userId) else {
                print("[ProtectedAction] No device key found for userId=\(userId)")
                return ActionResult(success: false, result: nil, error: "No device key found. Please re-setup your PIN.")
            }
            guard let signature = DeviceKeyService.sign(data: payloadData, privateKey: privateKey) else {
                print("[ProtectedAction] Signing failed for userId=\(userId)")
                return ActionResult(success: false, result: nil, error: "Signing failed")
            }

            let keyId = DeviceKeyService.getKeyId(userId: userId)
            print("[ProtectedAction] Signed: sigLen=\(signature.count) keyId=\(keyId ?? "none")")

            // Step 3: Execute with signature
            let executeResponse = try await executeWithSignature(
                challengeId: challengeId,
                signature: signature.base64EncodedString()
            )

            if let success = executeResponse["success"] as? Bool, success {
                print("[ProtectedAction] Success: action=\(action)")
                return ActionResult(success: true, result: executeResponse["result"] as? [String: Any], error: nil)
            } else {
                let error = executeResponse["error"] as? String ?? "Execution failed"
                print("[ProtectedAction] Failed: action=\(action) error=\(error)")
                return ActionResult(success: false, result: nil, error: error)
            }
        } catch {
            print("[ProtectedAction] Error: action=\(action) \(error.localizedDescription)")
            return ActionResult(success: false, result: nil, error: error.localizedDescription)
        }
    }

    private func createChallenge(action: String, params: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["action": action, "params": params])
        return try await requestJSON("POST", path: "/v1/auth/challenge", body: body)
    }

    private func executeWithSignature(challengeId: String, signature: String) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "challengeId": challengeId,
            "signature": signature,
        ]
        // Include keyId so backend can look up the specific device key
        if let keyId = DeviceKeyService.getKeyId(userId: userId) {
            payload["keyId"] = keyId
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await requestJSON("POST", path: "/v1/auth/execute", body: body)
    }

    /// Make an authenticated JSON request, returning raw dictionary
    private func requestJSON(_ method: String, path: String, body: Data) async throws -> [String: Any] {
        guard let tokenProvider = apiClient.tokenProvider else {
            throw NSError(domain: "ProtectedAction", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let token = try await tokenProvider()

        guard let url = URL(string: path, relativeTo: apiClient.baseURL) else {
            throw NSError(domain: "ProtectedAction", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NSError(domain: "ProtectedAction", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProtectedAction", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if httpResponse.statusCode >= 400 {
            let error = json["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "ProtectedAction", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: error])
        }

        return json
    }
}

import Foundation

struct InviteRedeemResponse: Decodable {
    let success: Bool
    let message: String
    let type: String?
    let referralCode: String?
}

class InviteService {
    private let client: APIClient

    init(tokenProvider: @escaping () async throws -> String) {
        self.client = APIClient(baseURL: AppConstants.inviteApiBaseURL)
        self.client.tokenProvider = tokenProvider
    }

    func redeemCode(_ code: String) async throws -> InviteRedeemResponse {
        struct RedeemBody: Encodable {
            let code: String
        }
        return try await client.request("POST", path: "/wl/invite/redeem", body: RedeemBody(code: code))
    }
}

class WaitlistService {
    private let client: APIClient

    init() {
        self.client = APIClient(baseURL: AppConstants.inviteApiBaseURL)
    }

    func join(email: String, source: String = "ios-app") async throws {
        struct JoinBody: Encodable {
            let email: String
            let source: String
        }
        struct JoinResponse: Decodable {
            let success: Bool
            let message: String
        }
        let _: JoinResponse = try await client.request("POST", path: "/wl/waitlist", body: JoinBody(email: email, source: source))
    }
}

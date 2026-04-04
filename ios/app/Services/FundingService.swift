import Foundation

struct FundingSessionResponse: Decodable {
    let token: String
    let url: String
}

class FundingService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func createSession() async throws -> FundingSessionResponse {
        try await client.request("POST", path: "/v1/funding/create-session")
    }
}

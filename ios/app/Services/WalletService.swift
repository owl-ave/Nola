import Foundation

struct WalletsResponse: Decodable {
    let wallets: [WalletInfo]
}

struct TransferToVaultResponse: Decodable {
    let success: Bool?
    let txHashes: [String]?
}

class WalletService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchWallets() async throws -> [WalletInfo] {
        let response: WalletsResponse = try await client.request("GET", path: "/v1/wallet/wallets")
        return response.wallets
    }

    func transferToVault(walletId: String, amountRaw: String) async throws -> TransferToVaultResponse {
        struct Body: Encodable {
            let walletId: String
            let amountRaw: String
        }
        return try await client.request("POST", path: "/v1/wallet/transfer-to-vault", body: Body(walletId: walletId, amountRaw: amountRaw))
    }
}

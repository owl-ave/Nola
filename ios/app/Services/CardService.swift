import Foundation

struct CardBalanceResponse: Decodable {
    let balance: String
    let currency: String
    let pendingCharges: String?
}

struct CardSecretsResponse: Decodable {
    let cardNumber: String
    let cvv: String
    let expiry: String
}

struct WalletInfo: Decodable, Identifiable {
    let id: String
    let address: String
    let usdcBalance: String
    let delegated: Bool
}

struct CardTopupResponse: Decodable {
    let success: Bool?
    let txHash: String?
    let error: String?
    let vaultBalance: String?
    let wallets: [WalletInfo]?
}

struct IssueCardResponse: Decodable {
    let card: CardListItem?
    let fee: Double?
    let error: String?
}

struct CardFreezeResponse: Decodable {
    let success: Bool
    let frozen: Bool
}

struct CardTransactionsResponse: Decodable {
    let transactions: [TransactionItem]
    let nextCursor: String?
}

class CardService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchCards() async throws -> [CardListItem] {
        try await client.request("GET", path: "/v1/card/details")
    }

    func fetchBalance() async throws -> CardBalanceResponse {
        try await client.request("GET", path: "/v1/card/balance")
    }

    func fetchSecrets(cardId: String) async throws -> CardSecretsResponse {
        try await client.request("GET", path: "/v1/card/secrets?cardId=\(cardId)")
    }

    func topUp(amountRaw: String) async throws -> CardTopupResponse {
        struct Body: Encodable { let amountRaw: String }
        return try await client.request("POST", path: "/v1/card/topup", body: Body(amountRaw: amountRaw))
    }

    func updateLimit(cardId: String, amount: Int?, frequency: String?) async throws {
        struct Body: Encodable { let cardId: String; let amount: Int?; let frequency: String? }
        let _: [String: Bool] = try await client.request("POST", path: "/v1/card/update-limit", body: Body(cardId: cardId, amount: amount, frequency: frequency))
    }

    func issueCard(displayName: String? = nil, limitAmount: Double? = nil, limitFrequency: String? = nil) async throws -> IssueCardResponse {
        struct Body: Encodable { let displayName: String?; let limitAmount: Double?; let limitFrequency: String? }
        return try await client.request("POST", path: "/v1/card/issue", body: Body(displayName: displayName, limitAmount: limitAmount, limitFrequency: limitFrequency))
    }

    func setFrozen(cardId: String, _ frozen: Bool) async throws -> CardFreezeResponse {
        struct Body: Encodable { let cardId: String; let frozen: Bool }
        return try await client.request("POST", path: "/v1/card/freeze", body: Body(cardId: cardId, frozen: frozen))
    }

    func fetchTransactions(cardId: String? = nil, cursor: String? = nil, limit: Int = 20) async throws -> CardTransactionsResponse {
        var path = "/v1/card/transactions?limit=\(limit)"
        if let cardId { path += "&cardId=\(cardId)" }
        if let cursor { path += "&cursor=\(cursor)" }
        return try await client.request("GET", path: path)
    }
}

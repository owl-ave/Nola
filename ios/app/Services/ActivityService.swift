import Foundation

struct TransactionsResponse: Decodable {
    let transactions: [TransactionItem]
    let nextCursor: String?
}

struct ChainDetailResponse: Decodable {
    let blockNumber: Int
    let blockTimestamp: String
    let confirmations: Int
    let gasUsed: String
    let status: String
}

class ActivityService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchTransactions(
        cursor: String? = nil,
        limit: Int = 20,
        cardId: String? = nil,
        types: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        minAmount: Double? = nil,
        maxAmount: Double? = nil
    ) async throws -> TransactionsResponse {
        var path = "/v1/transactions?limit=\(limit)"
        if let cursor { path += "&cursor=\(cursor)" }
        if let cardId { path += "&cardId=\(cardId)" }
        if let types { path += "&type=\(types)" }
        if let startDate { path += "&startDate=\(ISO8601DateFormatter().string(from: startDate))" }
        if let endDate { path += "&endDate=\(ISO8601DateFormatter().string(from: endDate))" }
        if let minAmount { path += "&minAmount=\(String(format: "%.2f", minAmount))" }
        if let maxAmount { path += "&maxAmount=\(String(format: "%.2f", maxAmount))" }
        return try await client.request("GET", path: path)
    }

    func fetchChainDetail(transactionId: String) async throws -> ChainDetailResponse {
        try await client.request("GET", path: "/v1/transactions/\(transactionId)/chain-detail")
    }
}

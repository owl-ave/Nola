import Foundation
import SwiftUI

struct DashboardData: Decodable {
    let totalBalance: String
    let walletBalance: String
    let cardBalance: String
    let vaultBalance: String
    let yieldEarned: String
    let apy: String
    let recentTransactions: [TransactionItem]
    let allocationPending: Bool?
}

struct TransactionItem: Decodable, Identifiable {
    let id: String
    let type: String
    let typeLabel: String?
    let source: String?
    let status: String?
    let amount: String
    let description: String
    let txHash: String?
    let fromAddress: String?
    let toAddress: String?
    let rainTransactionId: String?
    let cardId: String?
    let merchantName: String?
    let merchantIcon: String?
    let merchantCategory: String?
    let rainType: String?
    let createdAt: String?
    let timestamp: Int?  // Legacy — dashboard still sends this
}

extension TransactionItem {
    var icon: String {
        switch type {
        case "card_spend": return "creditcard"
        case "card_refund": return "arrow.uturn.left"
        case "deposit", "deposit_rain": return "arrow.down.circle"
        case "withdraw": return "arrow.up.circle"
        case "topup", "auto_topup": return "creditcard.and.123"
        case "card_payment": return "banknote"
        case "transfer_in": return "arrow.down.left"
        case "send": return "arrow.up.right"
        case "fee": return "doc.text"
        case "transfer_rain": return "arrow.left.arrow.right"
        case "yield": return "chart.line.uptrend.xyaxis"
        default: return "circle"
        }
    }

    var iconColor: Color {
        switch type {
        case "card_spend": return Color(red: 0.61, green: 0.52, blue: 0.92)
        case "card_refund", "deposit", "deposit_rain", "transfer_in", "yield": return Color.accentColor
        case "withdraw": return .orange
        case "topup", "auto_topup", "card_payment": return .blue
        case "send": return .red
        case "fee": return .orange
        case "transfer_rain": return .purple
        default: return .secondary
        }
    }

    var isCredit: Bool {
        ["deposit", "deposit_rain", "transfer_in", "card_refund", "yield"].contains(type)
    }

    var isPending: Bool { status == "pending" }
    var isFailed: Bool { status == "failed" }

    var statusLabel: String {
        switch status {
        case "pending": return "Pending"
        case "confirmed": return "Confirmed"
        case "failed": return "Failed"
        case "settled": return "Settled"
        default: return status?.capitalized ?? "Unknown"
        }
    }

    var sourceLabel: String {
        switch source {
        case "chain": return "On-chain"
        case "rain": return "Card Network"
        default: return source ?? "Unknown"
        }
    }

    var formattedAmount: String {
        let dollars = Double(amount) ?? 0
        let sign = isCredit ? "+" : "-"
        return CurrencyFormatter.format(dollars, sign: sign)
    }

    var transactionDate: Date? {
        if let createdAt {
            // Try with fractional seconds first (.000Z), then without
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = fmt.date(from: createdAt) { return parsed }
            fmt.formatOptions = [.withInternetDateTime]
            if let parsed = fmt.date(from: createdAt) { return parsed }
        }
        if let ts = timestamp {
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }
        return nil
    }

    var formattedTime: String {
        guard let date = transactionDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var formattedDate: String {
        guard let date = transactionDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var explorerUrl: URL? {
        guard let hash = txHash else { return nil }
        return AppConstants.blockExplorerURL.appendingPathComponent("tx/\(hash)")
    }
}

class DashboardService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchDashboard() async throws -> DashboardData {
        try await client.request("GET", path: "/v1/dashboard")
    }
}

import Foundation

struct CardLimit: Decodable {
    let amount: Int
    let frequency: String

    var formattedAmount: String {
        CurrencyFormatter.format(Double(amount) / 100)
    }

    var frequencyLabel: String {
        switch frequency {
        case "per24HourPeriod": return "per day"
        case "per7DayPeriod": return "per week"
        case "per30DayPeriod": return "per month"
        case "perYearPeriod": return "per year"
        case "allTime": return "total"
        case "perAuthorization": return "per transaction"
        default: return frequency
        }
    }
}

struct CardListItem: Decodable, Identifiable {
    let id: String
    let type: String
    let status: String
    let last4: String
    let expirationMonth: String?
    let expirationYear: String?
    let limit: CardLimit?

    var displayName: String {
        "Card"
    }

    var isFrozen: Bool {
        status == "locked"
    }

    var isCanceled: Bool {
        status == "canceled"
    }

    var expiry: String? {
        guard let month = expirationMonth, let year = expirationYear else { return nil }
        return "\(month)/\(year)"
    }
}

struct UserProfileResponse: Decodable {
    let user: UserProfileData
}

struct UserProfileData: Decodable {
    let firstName: String?
    let lastName: String?
    let autoTopupAmount: Int?
    let autoTopupThreshold: Int?
    let cardVaultSplit: String?
}

struct SplitConfig: Decodable {
    let cardAmount: Int
    let vaultAmount: Int
    let percentage: Int
}

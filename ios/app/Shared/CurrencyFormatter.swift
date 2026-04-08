import Foundation

enum CurrencyFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// Format a string amount (e.g. "1234.56") as "$1,234.56"
    static func format(_ amount: String) -> String {
        guard let value = Double(amount) else { return "$0.00" }
        return format(value)
    }

    /// Format a Double as "$1,234.56"
    static func format(_ amount: Double) -> String {
        formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// Format with a sign prefix: "+$1,234.56" or "-$1,234.56"
    static func format(_ amount: Double, sign: String) -> String {
        "\(sign)\(format(abs(amount)))"
    }

}

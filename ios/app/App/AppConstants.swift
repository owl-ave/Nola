import Foundation

private func config(_ key: String) -> String {
    guard let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty else {
        fatalError("Missing config key: \(key) — check xcconfig files")
    }
    return value
}

enum AppConstants {
    // MARK: - API
    static let apiBaseURL = URL(string: config("NL_API_BASE_URL"))!
    static let inviteApiBaseURL = URL(string: config("NL_INVITE_API_BASE_URL"))!
    static let chatBaseURL = URL(string: config("NL_CHAT_BASE_URL"))!
    static let exportWalletURL = URL(string: config("NL_EXPORT_WALLET_URL"))!

    // MARK: - Privy
    static let privyAppId = config("NL_PRIVY_APP_ID")
    static let privyAppClientId = config("NL_PRIVY_APP_CLIENT_ID")

    // MARK: - Blockchain
    static let chainId = Int(config("NL_CHAIN_ID"))!
    static let usdcAddress = config("NL_USDC_ADDRESS")
    static let blockExplorerURL = URL(string: config("NL_BLOCK_EXPLORER_URL"))!

    // MARK: - Sentry
    static let sentryDSN = config("NL_SENTRY_DSN")
    static let sentryTracesSampleRate = Double(config("NL_SENTRY_TRACES_SAMPLE_RATE"))!
}

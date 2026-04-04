import Foundation

enum DeepLink: Equatable {
    case tab(Tab)
    case card(String)
    case activityFiltered(ActivityFilter)
    case transaction(String)
    case support
    case supportTicket(String)
    case chat
    case chatNew
    case settingsSubpage(SettingsPage)

    enum Tab: Int {
        case home = 0
        case activity = 1
        case card = 2
        case settings = 3
    }

    enum SettingsPage: String {
        case autoEarn = "auto-earn"
        case profile = "profile"
    }

    static func from(url: URL) -> DeepLink? {
        guard url.scheme == "nola" else { return nil }
        let host = url.host() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let queryParam = { (name: String) -> String? in queryItems?.first(where: { $0.name == name })?.value }

        switch host {
        case "home": return .tab(.home)
        case "activity":
            let filter = ActivityFilter(
                cardId: queryParam("cardId"),
                types: queryParam("type")
            )
            if filter != ActivityFilter() { return .activityFiltered(filter) }
            return .tab(.activity)
        case "card":
            if let cardId = pathComponents.first { return .card(cardId) }
            return .tab(.card)
        case "settings":
            if let sub = pathComponents.first, let page = SettingsPage(rawValue: sub) {
                return .settingsSubpage(page)
            }
            return .tab(.settings)
        case "support":
            if let ticketId = pathComponents.first { return .supportTicket(ticketId) }
            return .support
        case "chat":
            if pathComponents.first == "new" { return .chatNew }
            return .chat
        case "transaction":
            if let id = pathComponents.first { return .transaction(id) }
            return nil
        default:
            return nil
        }
    }
}

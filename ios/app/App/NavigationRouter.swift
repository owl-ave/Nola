import SwiftUI

// MARK: - Tab

enum AppTab: Int, Hashable {
    case home = 0
    case activity = 1
    case card = 2
    case settings = 3
}

// MARK: - Destination Enums

enum HomeDestination: Hashable {
    case transactionDetail(String)
}

enum ActivityDestination: Hashable {
    case transactionDetail(String)
}

enum CardDestination: Hashable {
    case cardDetail(String)
}

enum SettingsDestination: Hashable {
    case autoEarn
    case profile
    case editProfile(firstName: String, lastName: String)
    case aiPermissions
    case notifications
    case exportWallet
    case changePIN
    case support
    case supportTicket(String)
}

// MARK: - Activity Filter

struct ActivityFilter: Equatable {
    var cardId: String?
    var types: String?
    var startDate: Date?
    var endDate: Date?
    var minAmount: Double?
    var maxAmount: Double?

    var activeCount: Int {
        var count = 0
        if types != nil { count += 1 }
        if startDate != nil || endDate != nil { count += 1 }
        if minAmount != nil || maxAmount != nil { count += 1 }
        if cardId != nil { count += 1 }
        return count
    }

    var isEmpty: Bool { activeCount == 0 }
}

// MARK: - Router

@Observable
class NavigationRouter {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var activityPath = NavigationPath()
    var cardPath = NavigationPath()
    var settingsPath = NavigationPath()
    var showChat = false
    var showSessionList = false
    var pendingChatPrompt: String?
    var suggestionSeed: Int = 0
    var pendingChatLink: DeepLink?
    var activityFilter: ActivityFilter?
    var pendingCardId: String?

    func handleDeepLink(_ link: DeepLink) {
        resetAllPaths()

        switch link {
        case .tab(let tab):
            selectedTab = AppTab(rawValue: tab.rawValue) ?? .home
        case .card(let id):
            selectedTab = .card
            pendingCardId = id
        case .activityFiltered(let filter):
            showActivity(filter: filter)
        case .transaction(let id):
            selectedTab = .activity
            activityPath.append(ActivityDestination.transactionDetail(id))
        case .support:
            selectedTab = .settings
            settingsPath.append(SettingsDestination.support)
        case .supportTicket(let id):
            selectedTab = .settings
            settingsPath.append(SettingsDestination.support)
            settingsPath.append(SettingsDestination.supportTicket(id))
        case .chat:
            pendingChatLink = .chat
        case .chatNew:
            pendingChatLink = .chatNew
        case .settingsSubpage(let page):
            selectedTab = .settings
            switch page {
            case .autoEarn:
                settingsPath.append(SettingsDestination.autoEarn)
            case .profile:
                settingsPath.append(SettingsDestination.profile)
            }
        }
    }

    func showActivity(filter: ActivityFilter) {
        selectedTab = .activity
        activityFilter = filter
    }

    func resetAllPaths() {
        homePath = NavigationPath()
        activityPath = NavigationPath()
        cardPath = NavigationPath()
        settingsPath = NavigationPath()
    }
}

import SwiftUI

struct MainTabView: View {
    @Environment(NavigationRouter.self) var router

    /// Int binding for child views that still use Int-based tab switching (e.g. HomeView).
    /// Will be removed once those views are refactored in later tasks.
    private var selectedTabInt: Binding<Int> {
        Binding(
            get: { router.selectedTab.rawValue },
            set: { router.selectedTab = AppTab(rawValue: $0) ?? .home }
        )
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView(switchToTab: selectedTabInt)
                        .navigationDestination(for: HomeDestination.self) { dest in
                            switch dest {
                            case .transactionDetail(let id):
                                // TODO: resolve TransactionItem from id once HomeView stops using its own NavigationStack
                                Text("Transaction \(id)")
                            }
                        }
                }
            }
            Tab("Activity", systemImage: "list.bullet.rectangle", value: AppTab.activity) {
                NavigationStack(path: $router.activityPath) {
                    ActivityView()
                        .navigationDestination(for: ActivityDestination.self) { dest in
                            switch dest {
                            case .transactionDetail(let id):
                                // TODO: resolve TransactionItem from id once ActivityView stops using its own NavigationStack
                                Text("Transaction \(id)")
                            }
                        }
                }
            }
            Tab("Card", systemImage: "creditcard.fill", value: AppTab.card) {
                NavigationStack(path: $router.cardPath) {
                    CardView()
                        .navigationDestination(for: CardDestination.self) { dest in
                            switch dest {
                            case .cardDetail:
                                EmptyView() // TODO: card detail view
                            }
                        }
                }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack(path: $router.settingsPath) {
                    SettingsView()
                        .navigationDestination(for: SettingsDestination.self) { dest in
                            switch dest {
                            case .autoEarn: AutoTopUpSettingsView()
                            case .profile: ProfileView()
                            case .editProfile(let first, let last): EditProfileView(firstName: first, lastName: last)
                            case .aiPermissions: AIPermissionsSettingsView()
                            case .notifications: NotificationSettingsView()
                            case .exportWallet: ExportWalletView()
                            case .changePIN: AuthGateView { ChangePINView() }
                            case .support: SupportView()
                            case .supportTicket(let id): SupportTicketDetailView(ticketId: Int(id) ?? 0)
                            }
                        }
                }
            }
        }
        .tabViewBottomAccessory { NolaAIBar() }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: router.selectedTab)
        .sensoryFeedback(.impact(weight: .medium), trigger: router.showChat)
        .fullScreenCover(isPresented: $router.showChat) {
            NolaChatScreen()
        }
    }
}

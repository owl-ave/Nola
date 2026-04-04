import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var switchToTab: Int

    @State private var dashboard: DashboardData?
    @State private var isLoading = true
    @State private var errorAlert: String?
    @State private var showAddFunds = false
    @State private var showTopUp = false
    @State private var showAutoSave = false
    @State private var isVisible = false
    @State private var comingSoonFeature: String?
    @State private var showWithdraw = false
    @State private var showVaultDetail = false
    @State private var previousWalletBalance: String = "0"

    private var service: DashboardService {
        DashboardService(client: appState.apiClient)
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    if isLoading && dashboard == nil {
                        // MARK: - Shimmer Skeletons
                        balanceHeroSkeleton
                            .padding(.top, 8)

                        pocketCardsSkeleton
                            .padding(.top, 24)

                        quickActionsSkeleton
                            .padding(.top, 28)

                        activitySkeleton
                            .padding(.top, 28)
                    } else {
                        // MARK: - Total Balance Hero
                        balanceHero
                            .padding(.top, 8)

                        // MARK: - Allocate Banner
                        if let walletBal = dashboard?.walletBalance,
                           let walletVal = Double(walletBal), walletVal > 0.5 {
                            if dashboard?.allocationPending == true {
                                allocationPendingBanner(balance: walletBal)
                                    .padding(.top, 20)
                                    .padding(.horizontal, 20)
                            } else {
                                allocateBanner(balance: walletBal)
                                    .padding(.top, 20)
                                    .padding(.horizontal, 20)
                            }
                        }

                        // MARK: - Pockets
                        pocketCards
                            .padding(.top, 24)

                        // MARK: - Quick Actions
                        quickActions
                            .padding(.top, 28)

                        // MARK: - Yield Banner
                        if let earned = dashboard?.yieldEarned, earned != "0" {
                            yieldBanner(earned: earned)
                                .padding(.top, 20)
                                .padding(.horizontal, 20)
                        }

                        // MARK: - Recent Activity
                        activitySection
                            .padding(.top, 28)
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeOut(duration: 0.3), value: isLoading)
            }
            .background(Color(.systemGroupedBackground))
            .sensoryFeedback(.impact(weight: .medium), trigger: showAddFunds)
            .sensoryFeedback(.impact(weight: .medium), trigger: showTopUp)
            .sensoryFeedback(.impact(weight: .medium), trigger: showAutoSave)
            .sensoryFeedback(.impact(weight: .medium), trigger: showWithdraw)
            .sensoryFeedback(.impact(weight: .medium), trigger: showVaultDetail)
            .refreshable { await loadDashboard() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("NolaMarkSmall")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        .task { await loadDashboard() }
        .sheet(isPresented: $showAddFunds, onDismiss: {
            Task { await loadDashboard() }
        }) {
            FundUSDCSheet()
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTopUp) {
            TopUpSheetView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAutoSave) {
            NavigationStack {
                AutoTopUpSettingsView()
            }
            .environmentObject(appState)
            .environmentObject(appState.authManager)
        }
        .sheet(isPresented: $showWithdraw, onDismiss: {
            Task { await loadDashboard() }
        }) {
            WithdrawSheet(vaultBalance: dashboard?.vaultBalance ?? "0")
                .environmentObject(appState)
        }
        .sheet(isPresented: $showVaultDetail) {
            VaultDetailSheet(
                balance: dashboard?.vaultBalance ?? "0",
                apy: dashboard?.apy ?? "0",
                yieldEarned: dashboard?.yieldEarned ?? "0",
                onWithdraw: {
                    showVaultDetail = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showWithdraw = true
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .alert("Coming Soon", isPresented: Binding(get: { comingSoonFeature != nil }, set: { if !$0 { comingSoonFeature = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(comingSoonFeature ?? "") is coming soon. Stay tuned!")
        }
    }

    // MARK: - Balance Hero

    private var balanceHero: some View {
        VStack(spacing: 6) {
            Text("TOTAL BALANCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            Text(CurrencyFormatter.format(dashboard?.totalBalance ?? "0.00"))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.5), value: dashboard?.totalBalance)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
    }

    // MARK: - Pocket Cards

    private var pocketCards: some View {
        HStack(spacing: 12) {
            Button { showVaultDetail = true } label: {
                PocketCard(
                    icon: "building.columns",
                    label: "Vault",
                    balance: dashboard?.vaultBalance ?? "0",
                    accentColor: Color(red: 0.23, green: 0.51, blue: 0.96),
                    badge: dashboard.map { "\($0.apy)% APY" }
                )
            }
            .buttonStyle(.plain)

            Button { switchToTab = 2 } label: {
                PocketCard(
                    icon: "creditcard",
                    label: "Card",
                    balance: dashboard?.cardBalance ?? "0",
                    accentColor: Color(red: 0.61, green: 0.52, blue: 0.92)
                )
            }
            .buttonStyle(.plain)
        }
        .tint(.primary)
        .padding(.horizontal, 20)
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 0) {
            QuickActionButton(icon: "plus", label: "Add") {
                previousWalletBalance = dashboard?.walletBalance ?? "0"
                showAddFunds = true
            }

            QuickActionButton(icon: "arrow.up.forward", label: "Withdraw") {
                showWithdraw = true
            }

            QuickActionButton(icon: "creditcard", label: "Use") {
                showTopUp = true
            }

            QuickActionButton(icon: "arrow.triangle.2.circlepath", label: "Auto Earn") {
                showAutoSave = true
            }
        }
        .tint(.primary)
        .padding(.horizontal, 20)
    }

    // MARK: - Allocate Banner

    private func allocationPendingBanner(balance: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Allocating \(CurrencyFormatter.format(balance))")
                    .font(.subheadline.weight(.medium))
                Text("Moving to your vault & card")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func allocateBanner(balance: String) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(CurrencyFormatter.format(balance)) ready to allocate")
                        .font(.subheadline.weight(.medium))
                    Text("Move to your vault & card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                Task { await requestAllocation() }
            } label: {
                Text("Allocate Now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Yield Banner

    private func requestAllocation() async {
        struct AllocateResponse: Decodable {
            let status: String
        }
        do {
            let _: AllocateResponse = try await appState.apiClient.request(
                "POST", path: "/v1/wallet/allocate"
            )
            await loadDashboard()
        } catch {
            print("[Home] allocate error: \(error)")
        }
    }

    private func yieldBanner(earned: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Yield Earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("+\(CurrencyFormatter.format(earned))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Text("\(dashboard?.apy ?? "0")% APY")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(16)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                Spacer()
                if let txs = dashboard?.recentTransactions, !txs.isEmpty {
                    Button("See All") {
                        switchToTab = 1
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if let txs = dashboard?.recentTransactions, !txs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(txs.prefix(5).enumerated()), id: \.element.id) { index, tx in
                        NavigationLink {
                            TransactionDetailView(transaction: tx)
                        } label: {
                            TransactionRow(transaction: tx)
                        }
                        .buttonStyle(.plain)

                        if index < min(txs.count, 5) - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 4)
                .tint(.primary)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            } else if !isLoading {
                NolaEmptyStateView(
                    icon: "tray",
                    title: "No Activity Yet",
                    description: "Your transactions will appear here"
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom, 80)
            }
        }
    }

    // MARK: - Shimmer Skeletons

    private var balanceHeroSkeleton: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 12)
                .shimmer()

            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 180, height: 44)
                .shimmer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var pocketCardsSkeleton: some View {
        HStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 32, height: 32)
                        .shimmer()

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 17)
                        .shimmer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 10)
                        .shimmer()
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .frame(height: 110)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 20)
    }

    private var quickActionsSkeleton: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 48, height: 48)
                        .shimmer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 10)
                        .shimmer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
    }

    private var activitySkeleton: some View {
        VStack(spacing: 0) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 16)
                    .shimmer()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(width: 120, height: 14)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(width: 80, height: 10)
                        }

                        Spacer()

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: 50, height: 14)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < 2 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .shimmer()
        }
    }

    // MARK: - Data Loading

    private func loadDashboard() async {
        // Only show loading skeleton on initial load, not pull-to-refresh.
        // Setting isLoading during refresh causes a view re-render that cancels the request.
        let isInitialLoad = dashboard == nil
        if isInitialLoad { isLoading = true }
        do {
            dashboard = try await service.fetchDashboard()
        } catch {
            print("[Home] dashboard error: \(error)")
            if isInitialLoad {
                errorAlert = "Failed to load dashboard. Pull to refresh."
            }
        }
        if isInitialLoad { isLoading = false }
    }
}

// MARK: - Pocket Card

private struct PocketCard: View {
    let icon: String
    let label: String
    let balance: String
    let accentColor: Color
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 32, height: 32)
                .background(accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            // Balance
            Text(CurrencyFormatter.format(balance))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.5), value: balance)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Label + optional badge
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(height: 110)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: .circle)

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: TransactionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(transaction.formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.formattedAmount)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(transaction.isCredit ? .green : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch transaction.type {
        case "card_spend": return Color(red: 0.61, green: 0.52, blue: 0.92)
        case "deposit": return Color.accentColor
        case "yield": return Color.accentColor
        case "card_topup": return .orange
        default: return .secondary
        }
    }
}

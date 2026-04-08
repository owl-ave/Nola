import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var appState: AppState
    @Environment(NavigationRouter.self) var router

    @State private var filter = ActivityFilter()
    @State private var transactions: [TransactionItem] = []
    @State private var nextCursor: String?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorAlert: String?
    @State private var initialLoadDone = false
    @State private var isVisible = false
    @State private var showFilterSheet = false

    private var activityService: ActivityService { ActivityService(client: appState.apiClient) }

    private var displayedTransactions: [TransactionItem] {
        if searchText.isEmpty { return transactions }
        return transactions.filter {
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedByDate: [(key: String, transactions: [TransactionItem])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        let grouped = Dictionary(grouping: displayedTransactions) { tx -> String in
            guard let date = tx.transactionDate else { return "Unknown" }
            if calendar.isDateInToday(date) { return "Today" }
            if calendar.isDateInYesterday(date) { return "Yesterday" }
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: date)
        }
        return grouped
            .sorted { lhs, rhs in
                let lDate = lhs.value.first?.transactionDate ?? .distantPast
                let rDate = rhs.value.first?.transactionDate ?? .distantPast
                return lDate > rDate
            }
            .map { (key: $0.key, transactions: $0.value) }
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    // Active filter chips
                    if !filter.isEmpty {
                        ActiveFilterChips(filter: $filter) {
                            Task { await loadTransactions(refresh: true) }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }

                    if isLoading && !initialLoadDone {
                        activityShimmer
                    } else if displayedTransactions.isEmpty && !isLoading {
                        NolaEmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: "No Transactions",
                            description: "Your transaction history will appear here"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        .padding(.bottom, 80)
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(groupedByDate.enumerated()), id: \.element.key) { sectionIndex, group in
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(group.key)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("\(group.transactions.count)")
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)

                                    VStack(spacing: 0) {
                                        ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, tx in
                                            NavigationLink {
                                                TransactionDetailView(transaction: tx)
                                                    .environmentObject(appState)
                                            } label: {
                                                ActivityRow(transaction: tx)
                                            }
                                            .buttonStyle(.plain)

                                            if index < group.transactions.count - 1 {
                                                Divider().padding(.leading, 64)
                                            }
                                        }
                                    }
                                    .tint(.primary)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal, 20)
                                }
                                .opacity(isVisible ? 1 : 0)
                                .offset(y: isVisible ? 0 : 12)
                                .animation(
                                    .easeOut(duration: 0.4).delay(Double(sectionIndex) * 0.08),
                                    value: isVisible
                                )
                            }
                        }
                        .padding(.top, 4)

                        if nextCursor != nil {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await loadMore() } }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.easeOut(duration: 0.3), value: initialLoadDone)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("Activity"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilterSheet = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .overlay(alignment: .topTrailing) {
                                if filter.activeCount > 0 {
                                    Text("\(filter.activeCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 14, height: 14)
                                        .background(Color.accentColor)
                                        .clipShape(Circle())
                                        .offset(x: 6, y: -6)
                                }
                            }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search transactions")
            .refreshable { await loadTransactions(refresh: true) }
        .task { await loadTransactions(refresh: true) }
        .onChange(of: router.activityFilter) { _, newFilter in
            if let newFilter {
                filter = newFilter
                router.activityFilter = nil
                Task { await loadTransactions(refresh: true) }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            TransactionFilterSheet(filter: $filter) {
                Task { await loadTransactions(refresh: true) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showFilterSheet)
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
    }

    private func loadTransactions(refresh: Bool) async {
        let isInitialLoad = !initialLoadDone
        if isInitialLoad { isLoading = true }
        do {
            let result = try await activityService.fetchTransactions(
                cursor: refresh ? nil : nextCursor,
                cardId: filter.cardId,
                types: filter.types,
                startDate: filter.startDate,
                endDate: filter.endDate,
                minAmount: filter.minAmount,
                maxAmount: filter.maxAmount
            )
            if refresh {
                transactions = result.transactions
            } else {
                transactions.append(contentsOf: result.transactions)
            }
            nextCursor = result.nextCursor
        } catch {
            print("[Activity] error: \(error)")
            if isInitialLoad {
                errorAlert = "Failed to load transactions. Pull to refresh."
            }
        }
        if isInitialLoad { isLoading = false }
        initialLoadDone = true
        withAnimation(.easeOut(duration: 0.4)) { isVisible = true }
    }

    private func loadMore() async {
        guard !isLoadingMore, nextCursor != nil else { return }
        isLoadingMore = true
        await loadTransactions(refresh: false)
        isLoadingMore = false
    }

    // MARK: - Shimmer (keep existing shimmer from old file)

    private var activityShimmer: some View {
        VStack(spacing: 20) {
            ForEach(0..<3, id: \.self) { sectionIndex in
                VStack(spacing: 0) {
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(width: sectionIndex == 0 ? 40 : 90, height: 12)
                            .shimmer()
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        ForEach(0..<(sectionIndex == 0 ? 4 : 3), id: \.self) { index in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: CGFloat.random(in: 100...160), height: 14)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 60, height: 10)
                                }
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 50, height: 14)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            if index < (sectionIndex == 0 ? 3 : 2) {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .shimmer()
                }
            }
        }
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let transaction: TransactionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(transaction.iconColor)
                .frame(width: 36, height: 36)
                .background(transaction.iconColor.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(transaction.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if transaction.isPending {
                        StatusBadge(text: "Pending", color: .yellow)
                    } else if transaction.isFailed {
                        StatusBadge(text: "Failed", color: .red)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text(transaction.formattedAmount)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(transaction.isCredit ? Color.accentColor : .primary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

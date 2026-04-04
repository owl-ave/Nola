import SwiftUI
import PrivySDK

struct CardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(NavigationRouter.self) var router

    @State private var cards: [CardListItem] = []
    @State private var selectedCardId: String?
    @State private var isLoading = true
    @State private var userName = "Nola User"
    @State private var errorAlert: String?
    @State private var issuedMessage: String?

    // Sheets
    @State private var showTopUp = false
    @State private var showNewCard = false
    @State private var showCardDetails = false
    @State private var showLimitEditor = false
    @State private var showFreezeConfirm = false
    @State private var showUnfreezeConfirm = false
    @State private var showFreezeAuth = false
    @State private var showCancelConfirm = false
    @State private var showCancelAuth = false

    // Loading states
    @State private var isFreezing = false
    @State private var isIssuingCard = false
    @State private var isCanceling = false
    @State private var cardTransactions: [TransactionItem] = []
    @State private var cardTxLoading = false
    @State private var showCanceled = false
    @State private var canceledMessage: String?

    private var cardService: CardService { CardService(client: appState.apiClient) }
    private var activityService: ActivityService { ActivityService(client: appState.apiClient) }

    private var visibleCards: [CardListItem] {
        showCanceled ? cards : cards.filter { !$0.isCanceled }
    }

    private var selectedCard: CardListItem? {
        visibleCards.first(where: { $0.id == selectedCardId }) ?? visibleCards.first
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            content
                .padding(.vertical, 16)
                .animation(.easeOut(duration: 0.3), value: isLoading)
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.impact(weight: .medium), trigger: showTopUp)
        .sensoryFeedback(.impact(weight: .medium), trigger: showNewCard)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCardDetails)
        .sensoryFeedback(.impact(weight: .medium), trigger: showLimitEditor)
        .navigationTitle(Text("Card"))
        .toolbar { toolbarContent }
        .refreshable { await loadCardData() }
        .task { await loadCardData() }
        .onChange(of: selectedCardId) { _, newId in
            guard let cardId = newId else { return }
            Task { await loadCardTransactions(cardId: cardId) }
        }
        .onChange(of: showCanceled) { _, _ in
            if !visibleCards.contains(where: { $0.id == selectedCardId }) {
                selectedCardId = visibleCards.first?.id
            }
        }
        .onChange(of: router.pendingCardId) { _, pending in
            if let pending {
                selectedCardId = pending
                router.pendingCardId = nil
            }
        }
        .sheet(isPresented: $showTopUp) {
            TopUpSheetView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewCard) {
            NewCardSheet(
                isIssuing: $isIssuingCard,
                activeCardCount: cards.filter({ !$0.isCanceled }).count
            ) { displayName, limitAmount, limitFrequency in
                Task { await issueNewCard(displayName: displayName, limitAmount: limitAmount, limitFrequency: limitFrequency) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showLimitEditor) {
            if let card = selectedCard {
                LimitEditorSheet(card: card, cardService: cardService) {
                    Task { await loadCardData() }
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showCardDetails) {
            CardDetailsSheetWrapper(card: selectedCard, userName: userName, appState: appState, dismiss: { showCardDetails = false })
        }
        .sheet(isPresented: $showFreezeAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showFreezeAuth = false })) {
                    showFreezeAuth = false
                    guard let card = selectedCard else { return }
                    Task { await toggleFreeze(card) }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .alert("Freeze Card", isPresented: $showFreezeConfirm) {
            Button("Freeze", role: .destructive) {
                Task {
                    if await authManager.authenticate() {
                        guard let card = selectedCard else { return }
                        await toggleFreeze(card)
                    } else {
                        showFreezeAuth = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your card will be temporarily disabled. You can unfreeze it at any time.")
        }
        .alert("Unfreeze Card", isPresented: $showUnfreezeConfirm) {
            Button("Unfreeze") {
                Task {
                    if await authManager.authenticate() {
                        guard let card = selectedCard else { return }
                        await toggleFreeze(card)
                    } else {
                        showFreezeAuth = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your card will be reactivated and ready to use.")
        }
        .alert("Cancel Card", isPresented: $showCancelConfirm) {
            Button("Cancel Card", role: .destructive) {
                Task {
                    if await authManager.authenticate() {
                        guard let card = selectedCard else { return }
                        await cancelCard(card)
                    } else {
                        showCancelAuth = true
                    }
                }
            }
            Button("Keep Card", role: .cancel) {}
        } message: {
            if let card = selectedCard {
                Text("Card •••• \(card.last4) will be permanently deactivated. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showCancelAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showCancelAuth = false })) {
                    showCancelAuth = false
                    guard let card = selectedCard else { return }
                    Task { await cancelCard(card) }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .alert("Card Canceled", isPresented: Binding(get: { canceledMessage != nil }, set: { if !$0 { canceledMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(canceledMessage ?? "")
        }
        .alert("Card Issued", isPresented: Binding(get: { issuedMessage != nil }, set: { if !$0 { issuedMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(issuedMessage ?? "")
        }
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        if isLoading && cards.isEmpty {
            CardSkeletonView()
        } else if visibleCards.isEmpty {
            NolaEmptyStateView(
                icon: "creditcard.trianglebadge.exclamationmark",
                title: cards.isEmpty ? "No Cards" : "No Active Cards",
                description: cards.isEmpty ? "Tap + to issue your first card." : "All your cards have been canceled."
            )
            .padding(.top, 60)
        } else if let card = selectedCard {
            VStack(spacing: 20) {
                CardCarousel(cards: visibleCards, selectedCardId: $selectedCardId, userName: userName)
                LimitStrip(card: card, onEditLimit: { showLimitEditor = true })
                CardActions(
                    card: card,
                    isFreezing: isFreezing,
                    onTopUp: { showTopUp = true },
                    onFreeze: {
                        if card.isFrozen { showUnfreezeConfirm = true } else { showFreezeConfirm = true }
                    },
                    onDetails: { showCardDetails = true }
                )
                CardTransactionsSection(
                    transactions: cardTransactions,
                    isLoading: cardTxLoading,
                    cardId: selectedCardId
                )
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                Button { showNewCard = true } label: {
                    Image(systemName: "plus")
                }
                Menu {
                    if let card = selectedCard, !card.isCanceled {
                        Button(role: .destructive) {
                            showCancelConfirm = true
                        } label: {
                            Label("Cancel Card", systemImage: "xmark.circle")
                        }
                    }
                    if cards.contains(where: { $0.isCanceled }) {
                        Toggle(isOn: $showCanceled) {
                            Label("Show Canceled", systemImage: "eye.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadCardData() async {
        let isInitialLoad = cards.isEmpty
        if isInitialLoad { isLoading = true }
        do {
            let fetchedCards = try await cardService.fetchCards()
            cards = fetchedCards
            if selectedCardId == nil { selectedCardId = fetchedCards.first?.id }

            let profile: UserProfileResponse = try await appState.apiClient.request("GET", path: "/v1/user/profile")
            userName = [profile.user.firstName, profile.user.lastName].compactMap { $0 }.joined(separator: " ")

            if let cardId = selectedCard?.id {
                await loadCardTransactions(cardId: cardId)
            }
        } catch {
            print("[Card] load error: \(error)")
            if isInitialLoad { errorAlert = "Failed to load card data. Pull to refresh." }
        }
        if isInitialLoad { isLoading = false }
    }

    private func loadCardTransactions(cardId: String) async {
        cardTxLoading = true
        do {
            let response = try await activityService.fetchTransactions(limit: 10, cardId: cardId)
            cardTransactions = response.transactions
        } catch {
            cardTransactions = []
        }
        cardTxLoading = false
    }

    private func toggleFreeze(_ card: CardListItem) async {
        isFreezing = true
        do {
            let result = try await cardService.setFrozen(cardId: card.id, !card.isFrozen)
            if result.frozen != card.isFrozen { cards = try await cardService.fetchCards() }
        } catch {
            errorAlert = card.isFrozen ? "Failed to unfreeze card." : "Failed to freeze card."
        }
        isFreezing = false
    }

    private func cancelCard(_ card: CardListItem) async {
        isCanceling = true
        do {
            let privyUser = await appState.privy.getUser()
            let userId = privyUser?.id ?? ""
            let service = ProtectedActionService(apiClient: appState.apiClient, userId: userId)
            let result = await service.execute(action: "cancel_card", params: ["cardId": card.id])
            if result.success {
                canceledMessage = "Card •••• \(card.last4) has been canceled."
                await loadCardData()
                // Select next active card
                selectedCardId = visibleCards.first(where: { !$0.isCanceled })?.id
            } else {
                errorAlert = result.error ?? "Failed to cancel card"
            }
        } catch {
            errorAlert = "Failed to cancel card: \(error.localizedDescription)"
        }
        isCanceling = false
    }

    private func issueNewCard(displayName: String?, limitAmount: Double?, limitFrequency: String?) async {
        isIssuingCard = true
        do {
            let response = try await cardService.issueCard(displayName: displayName, limitAmount: limitAmount, limitFrequency: limitFrequency)
            if let error = response.error {
                errorAlert = error
            } else {
                showNewCard = false
                await loadCardData()
                if let card = response.card {
                    let feeText = (response.fee ?? 0) > 0 ? " A $0.20 fee was charged." : ""
                    issuedMessage = "Card •••• \(card.last4) is ready to use.\(feeText)"
                    selectedCardId = card.id
                }
            }
        } catch {
            errorAlert = "Failed to issue card: \(error.localizedDescription)"
        }
        isIssuingCard = false
    }
}

// MARK: - Card Carousel

private struct CardCarousel: View {
    let cards: [CardListItem]
    @Binding var selectedCardId: String?
    let userName: String

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cards) { card in
                        NolaCardVisual(
                            last4: card.last4,
                            cardholderName: userName,
                            expiry: card.expiry,
                            isFrozen: card.isFrozen,
                            type: card.type,
                            isCanceled: card.isCanceled
                        )
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 12)
                        .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: Binding(
                get: { selectedCardId },
                set: { if let id = $0 { selectedCardId = id } }
            ))
            .contentMargins(.horizontal, 20, for: .scrollContent)

            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(cards) { card in
                        Circle()
                            .fill(card.id == selectedCardId ? Color.accentColor : Color(.systemGray4))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: selectedCardId)
                    }
                }
            }
        }
    }
}

// MARK: - Limit + Status Strip

private struct LimitStrip: View {
    let card: CardListItem
    let onEditLimit: () -> Void

    var body: some View {
        HStack {
            // Limit
            Button(action: onEditLimit) {
                HStack(spacing: 6) {
                    if let limit = card.limit {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("\(limit.formattedAmount) \(limit.frequencyLabel)")
                            .font(.caption.weight(.medium))
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("No limit")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: "plus")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .tint(.primary)
            .buttonStyle(.plain)

            Spacer()

            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(card.isFrozen ? Color.red : card.isCanceled ? Color(.systemGray4) : Color.green)
                    .frame(width: 6, height: 6)
                Text(card.status.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Card Actions

private struct CardActions: View {
    let card: CardListItem
    let isFreezing: Bool
    let onTopUp: () -> Void
    let onFreeze: () -> Void
    let onDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ActionButton(title: "Top Up", icon: "arrow.up.circle.fill", color: .accentColor, action: onTopUp)
            ActionButton(
                title: isFreezing ? "..." : (card.isFrozen ? "Unfreeze" : "Freeze"),
                icon: card.isFrozen ? "lock.open.fill" : "lock.fill",
                color: card.isFrozen ? .green : .red,
                action: { guard !isFreezing else { return }; onFreeze() }
            )
            ActionButton(title: "Details", icon: "eye.fill", color: .secondary, action: onDetails)
        }
        .padding(.horizontal, 20)
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
        }
        .tint(.primary)
        .buttonStyle(.plain)
    }
}

// MARK: - Card Transactions Section

private struct CardTransactionsSection: View {
    @Environment(NavigationRouter.self) var router
    let transactions: [TransactionItem]
    let isLoading: Bool
    let cardId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !transactions.isEmpty, let cardId {
                    Button {
                        router.showActivity(filter: ActivityFilter(cardId: cardId))
                    } label: {
                        Text("See All").font(.caption).foregroundStyle(Color.accentColor)
                    }
                }
            }

            if isLoading {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray5))
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(width: CGFloat.random(in: 80...140), height: 12)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray6))
                                    .frame(width: 50, height: 9)
                            }
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(width: 60, height: 14)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if i < 2 { Divider().padding(.leading, 60) }
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .shimmer()
            } else if transactions.isEmpty {
                Text("No transactions yet")
                    .font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { tx in
                        NavigationLink { TransactionDetailView(transaction: tx) } label: {
                            TransactionRow(transaction: tx)
                        }
                        .tint(.primary)
                        if tx.id != transactions.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .tint(.primary)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct TransactionRow: View {
    let transaction: TransactionItem

    var body: some View {
        HStack(spacing: 12) {
            if let iconUrl = transaction.merchantIcon, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: transaction.icon)
                        .foregroundStyle(transaction.iconColor)
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: transaction.icon)
                    .font(.body)
                    .foregroundStyle(transaction.iconColor)
                    .frame(width: 32, height: 32)
                    .background(transaction.iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.subheadline).lineLimit(1)
                Text(transaction.formattedTime).font(.caption2).foregroundStyle(.tertiary)
            }

            Spacer()

            Text(transaction.formattedAmount)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(transaction.isCredit ? .green : .primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Loading Skeleton

private struct CardSkeletonView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6))
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)).frame(width: 28, height: 28)
                        Spacer()
                        RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)).frame(width: 56, height: 16)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 200, height: 18).padding(.bottom, 16)
                    HStack {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 100, height: 12)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(width: 60, height: 12)
                    }
                }
                .padding(20)
            }
            .aspectRatio(1.586, contentMode: .fit)
            .shimmer()
            .padding(.horizontal, 20)

            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).frame(height: 60).shimmer()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Card Details Sheet Wrapper

private struct CardDetailsSheetWrapper: View {
    let card: CardListItem?
    let userName: String
    let appState: AppState
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            AuthGateView {
                if let card {
                    CardDetailsContent(card: card, cardholderName: userName, appState: appState)
                }
            }
            .navigationTitle(Text("Card Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - New Card Sheet

private struct NewCardSheet: View {
    @Binding var isIssuing: Bool
    let activeCardCount: Int
    let onIssue: (_ displayName: String?, _ limitAmount: Double?, _ limitFrequency: String?) -> Void
    @State private var displayName = ""
    @State private var limitEnabled = false
    @State private var limitAmount = ""
    @State private var limitFrequency = "allTime"

    private var hasFee: Bool { activeCardCount >= 4 }

    private var parsedLimitDollars: Double? {
        guard limitEnabled, let dollars = Double(limitAmount), dollars > 0 else { return nil }
        return dollars
    }

    var body: some View {
        NavigationStack {
            Form {
                if hasFee {
                    Section {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                            Text("A $0.20 fee applies for additional cards beyond your first 4.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Name on Card")
                        Spacer()
                        TextField("Your name", text: $displayName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } header: { Text("Personalization") }
                  footer: { Text("Max 26 characters. Defaults to your full name if empty.") }

                Section {
                    Toggle("Set Spending Limit", isOn: $limitEnabled)
                    if limitEnabled {
                        HStack {
                            Text("Amount")
                            Spacer()
                            TextField("$0.00", text: $limitAmount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        Picker("Frequency", selection: $limitFrequency) {
                            Text("Per Transaction").tag("perAuthorization")
                            Text("Per 24 Hours").tag("per24HourPeriod")
                            Text("Per 7 Days").tag("per7DayPeriod")
                            Text("Per 30 Days").tag("per30DayPeriod")
                            Text("Per Year").tag("perYearPeriod")
                            Text("All Time").tag("allTime")
                        }
                    }
                } header: { Text("Spending Limit") }

                Section {
                    Button {
                        onIssue(
                            displayName.isEmpty ? nil : displayName,
                            parsedLimitDollars,
                            limitEnabled ? limitFrequency : nil
                        )
                    } label: {
                        HStack {
                            Spacer()
                            if isIssuing { ProgressView().tint(.white).padding(.trailing, 8) }
                            Text(isIssuing ? "Issuing..." : hasFee ? "Issue Card — $0.20" : "Issue Card")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(isIssuing)
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                } footer: {
                    if hasFee {
                        Text("Fee will be charged to your card balance.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(Text("New Card"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Limit Editor Sheet

private struct LimitEditorSheet: View {
    let card: CardListItem
    let cardService: CardService
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var limitEnabled: Bool
    @State private var amount: String
    @State private var frequency: String
    @State private var isSaving = false
    @State private var error: String?

    init(card: CardListItem, cardService: CardService, onSaved: @escaping () -> Void) {
        self.card = card; self.cardService = cardService; self.onSaved = onSaved
        _limitEnabled = State(initialValue: card.limit != nil)
        _amount = State(initialValue: card.limit.map { String(format: "%.2f", Double($0.amount) / 100) } ?? "")
        _frequency = State(initialValue: card.limit?.frequency ?? "allTime")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Spending Limit", isOn: $limitEnabled)
                } footer: { Text("Limit spending on card •••• \(card.last4)") }

                if limitEnabled {
                    Section("Limit") {
                        HStack {
                            Text("Amount"); Spacer()
                            TextField("$0.00", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                        }
                        Picker("Frequency", selection: $frequency) {
                            Text("Per Transaction").tag("perAuthorization")
                            Text("Per 24 Hours").tag("per24HourPeriod")
                            Text("Per 7 Days").tag("per7DayPeriod")
                            Text("Per 30 Days").tag("per30DayPeriod")
                            Text("Per Year").tag("perYearPeriod")
                            Text("All Time").tag("allTime")
                        }
                    }
                }

                if let error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            }
            .navigationTitle(Text("Spending Limit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button { Task { await save() } } label: {
                            Image(systemName: "checkmark")
                        }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true; error = nil
        do {
            if limitEnabled {
                guard let cents = Double(amount).map({ Int($0 * 100) }), cents > 0 else {
                    error = "Enter a valid amount"; isSaving = false; return
                }
                try await cardService.updateLimit(cardId: card.id, amount: cents, frequency: frequency)
            } else {
                try await cardService.updateLimit(cardId: card.id, amount: nil, frequency: nil)
            }
            onSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
        isSaving = false
    }
}

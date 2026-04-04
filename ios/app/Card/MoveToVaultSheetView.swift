import SwiftUI

struct MoveToVaultSheetView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var wallets: [WalletInfo] = []
    @State private var selectedWallet: WalletInfo?
    @State private var amountText = ""
    @State private var isLoading = true
    @State private var isTransferring = false
    @State private var statusText: String?
    @State private var error: String?
    @State private var success = false
    @State private var showTransferAuth = false

    @FocusState private var amountFocused: Bool

    private var walletService: WalletService { WalletService(client: appState.apiClient) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Move to Vault")
                        .font(.title2.weight(.bold))

                    Text("Transfer USDC from your wallet into the vault to earn yield")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if wallets.isEmpty {
                        NolaEmptyStateView(
                            icon: "wallet.bifold",
                            title: "No Wallets",
                            description: "No wallets with USDC found."
                        )
                        .padding(.top, 20)
                    } else {
                        walletPicker
                        amountInput

                        if let error {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let statusText {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if success {
                            Label("Transfer successful!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        transferButton
                    }

                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await loadWallets() }
        .sensoryFeedback(.success, trigger: success)
        .sensoryFeedback(.error, trigger: error)
        .sheet(isPresented: $showTransferAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showTransferAuth = false })) {
                    showTransferAuth = false
                    Task { await transfer() }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Wallet Picker

    @ViewBuilder
    private var walletPicker: some View {
        if wallets.count == 1, let wallet = wallets.first {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(shortAddress(wallet.address))
                        .font(.subheadline.monospaced())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(wallet.usdcBalance))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Wallet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                ForEach(wallets) { wallet in
                    let isSelected = selectedWallet?.id == wallet.id
                    Button {
                        selectedWallet = wallet
                    } label: {
                        HStack {
                            Text(shortAddress(wallet.address))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(CurrencyFormatter.format(wallet.usdcBalance))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(16)
                        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Amount Input

    private var amountInput: some View {
        VStack(spacing: 8) {
            TextField("Amount (USDC)", text: $amountText)
                .font(.title.monospaced())
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if let wallet = activeWallet, let balance = Double(wallet.usdcBalance), balance > 0 {
                Button("Max: \(CurrencyFormatter.format(wallet.usdcBalance))") {
                    amountText = wallet.usdcBalance
                    amountFocused = false
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Transfer Button

    private var transferButton: some View {
        Button {
            amountFocused = false
            Task {
                if await authManager.authenticate() {
                    await transfer()
                } else {
                    showTransferAuth = true
                }
            }
        } label: {
            if isTransferring {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Move to Vault")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
        .controlSize(.large)
        .disabled(amountText.isEmpty || activeWallet == nil || isTransferring)
    }

    // MARK: - Helpers

    private var activeWallet: WalletInfo? {
        wallets.count == 1 ? wallets.first : selectedWallet
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    // MARK: - API

    private func loadWallets() async {
        isLoading = true
        do {
            wallets = try await walletService.fetchWallets()
            if wallets.count == 1 {
                selectedWallet = wallets.first
            }
        } catch {
            print("[MoveToVault] load error: \(error)")
            self.error = "Failed to load wallets. Please try again."
        }
        isLoading = false
    }

    private func transfer() async {
        guard let wallet = activeWallet else { return }
        guard let dollars = Double(amountText) else {
            error = "Enter a valid amount"
            return
        }
        let rawAmount = String(Int(dollars * 1_000_000))
        isTransferring = true
        error = nil
        statusText = nil

        do {
            statusText = "Processing transfer..."
            let result = try await walletService.transferToVault(
                walletId: wallet.id, amountRaw: rawAmount
            )
            if result.success == true {
                success = true
            }
        } catch let APIError.httpError(_, body) {
            error = body
        } catch {
            self.error = error.localizedDescription
        }

        statusText = nil
        isTransferring = false
    }

}

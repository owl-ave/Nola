import SwiftUI

struct TopUpSheetView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false
    @State private var vaultBalance: String?
    @State private var wallets: [WalletInfo]?
    @State private var showMoveToVault = false
    @State private var showTopUpAuth = false
    @FocusState private var amountFocused: Bool

    private var cardService: CardService { CardService(client: appState.apiClient) }

    private var parsedAmount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canTopUp: Bool {
        guard let amount = parsedAmount, amount > 0 else { return false }
        return !isLoading && !success
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: - Amount Input
                VStack(spacing: 8) {
                    Text("Top Up Card")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(amountText.isEmpty ? "$0" : "$\(amountText)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(amountText.isEmpty ? Color(.tertiaryLabel) : .primary)
                        .contentTransition(.numericText())
                        .animation(.default, value: amountText)
                        .frame(maxWidth: .infinity)
                        .onTapGesture { amountFocused = true }

                    // Hidden TextField to capture keyboard input
                    TextField("", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                // MARK: - Vault Balance
                if let vaultBalance {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "building.columns.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                            Text("Vault")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.format(vaultBalance))
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // MARK: - Move to Vault Prompt
                if let wallets, !wallets.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("USDC in wallet")
                                .font(.caption.weight(.medium))
                            Text("Move to vault before topping up")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            showMoveToVault = true
                        } label: {
                            Text("Move")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                // MARK: - Error
                if let error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // MARK: - Success
                if success {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Top-up successful!")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // MARK: - Top Up Button
                Button {
                    Task {
                        if await authManager.authenticate() {
                            await topUp()
                        } else {
                            showTopUpAuth = true
                        }
                    }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else if success {
                            Label("Done", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text(parsedAmount != nil ? "Top Up \(CurrencyFormatter.format(parsedAmount!))" : "Top Up")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canTopUp ? Color.accentColor : Color.accentColor.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canTopUp)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .animation(.default, value: error)
            .animation(.spring(response: 0.35), value: success)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { amountFocused = true }
        }
        .task { await loadVaultBalance() }
        .sheet(isPresented: $showMoveToVault, onDismiss: {
            Task { await loadVaultBalance() }
        }) {
            MoveToVaultSheetView()
        }
        .sheet(isPresented: $showTopUpAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showTopUpAuth = false })) {
                    showTopUpAuth = false
                    Task { await topUp() }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .sensoryFeedback(.success, trigger: success)
        .sensoryFeedback(.error, trigger: error)
    }

    // MARK: - API

    private func loadVaultBalance() async {
        struct VaultResponse: Decodable {
            let vaultBalance: String
        }
        do {
            let response: VaultResponse = try await appState.apiClient.request("GET", path: "/v1/wallet/vault-balance")
            vaultBalance = response.vaultBalance
            wallets = nil
            error = nil
        } catch {
            print("[TopUp] vault balance error: \(error)")
            self.error = "Failed to load vault balance."
        }
    }

    private func topUp() async {
        guard let dollars = parsedAmount else {
            error = "Enter a valid amount"
            return
        }
        let rawAmount = String(Int(dollars * 1_000_000))
        isLoading = true
        error = nil
        wallets = nil
        do {
            let result = try await cardService.topUp(amountRaw: rawAmount)
            if result.success == true {
                success = true
                amountFocused = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            } else if let msg = result.error {
                error = msg
                vaultBalance = result.vaultBalance ?? vaultBalance
                wallets = result.wallets
            }
        } catch let APIError.httpError(_, body) {
            if let data = body.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CardTopupResponse.self, from: data) {
                error = decoded.error
                vaultBalance = decoded.vaultBalance ?? vaultBalance
                wallets = decoded.wallets
            } else {
                error = body
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

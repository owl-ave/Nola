import SwiftUI

struct FundUSDCSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showSafari = false
    @State private var safariURL: URL?
    @State private var showTransfer = false
    @State private var isLoadingSession = false
    @State private var error: String?

    private var fundingService: FundingService {
        FundingService(client: appState.apiClient)
    }

    var body: some View {
        fundingContent
    }

    private var fundingContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Fund Your Wallet")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                Text("Get USDC on Base")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)

                VStack(spacing: 0) {
                    // Buy with Card
                    FundingMethodRow(
                        icon: "creditcard.fill",
                        iconColor: .green,
                        title: "Buy with Card",
                        subtitle: "Credit card or Apple Pay",
                        isLoading: isLoadingSession
                    ) {
                        await buyWithCard()
                    }

                    Divider().padding(.leading, 56)

                    // Pay with Venmo & more (Peer)
                    FundingMethodRow(
                        icon: "banknote",
                        iconColor: .green,
                        title: "Pay with Venmo & more",
                        subtitle: "Low fees via peer-to-peer • No KYC",
                        isLoading: false
                    ) {
                        if let url = URL(string: "https://www.peer.xyz/swap?tab=buy") {
                            await MainActor.run {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    Divider().padding(.leading, 56)

                    // Transfer from Wallet
                    FundingMethodRow(
                        icon: "qrcode",
                        iconColor: .blue,
                        title: "Transfer from Wallet",
                        subtitle: "Send USDC from another wallet",
                        isLoading: false
                    ) {
                        showTransfer = true
                    }

                    Divider().padding(.leading, 56)

                    // Swap & Bridge (Li.Fi)
                    FundingMethodRow(
                        icon: "arrow.triangle.swap",
                        iconColor: .purple,
                        title: "Send using Crypto",
                        subtitle: "Swap any token from any chain",
                        isLoading: isLoadingSession
                    ) {
                        await openSwapPage()
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showTransfer) {
            AddFundsSheetView()
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showSafari) {
            if let url = safariURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    private func buyWithCard() async {
        isLoadingSession = true
        error = nil
        do {
            let session = try await fundingService.createSession()
            if let url = URL(string: session.url) {
                safariURL = url
                showSafari = true
            }
        } catch {
            self.error = "Failed to start purchase. Try again."
            print("[Funding] create-session error: \(error)")
        }
        isLoadingSession = false
    }

    private func openSwapPage() async {
        isLoadingSession = true
        error = nil
        do {
            let session = try await fundingService.createSession()
            // Replace /fund with /swap in the URL
            let swapUrl = session.url.replacingOccurrences(of: "/fund?", with: "/swap?")
            if let url = URL(string: swapUrl) {
                safariURL = url
                showSafari = true
            }
        } catch {
            self.error = "Failed to start swap. Try again."
            print("[Funding] create-session error: \(error)")
        }
        isLoadingSession = false
    }
}

// MARK: - Funding Method Row

private struct FundingMethodRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var isLoading: Bool = false
    var comingSoon: Bool = false
    var action: (() async -> Void)?

    var body: some View {
        Button {
            if let action, !comingSoon {
                Task { await action() }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(comingSoon ? Color(.systemGray3) : iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(comingSoon ? .secondary : .primary)
                        if comingSoon {
                            Text("Soon")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !comingSoon {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(comingSoon)
    }
}

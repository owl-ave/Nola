import SwiftUI
import CoreImage.CIFilterBuiltins

struct AddFundsSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var wallets: [WalletInfo] = []
    @State private var selectedWallet: WalletInfo?
    @State private var isLoading = true
    @State private var copied = false
    @State private var error: String?
    @State private var appeared = false
    @State private var sheetDetent: PresentationDetent = .medium

    private var walletService: WalletService { WalletService(client: appState.apiClient) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if isLoading {
                        loadingState
                    } else if let error {
                        errorState(error)
                    } else if wallets.isEmpty {
                        NolaEmptyStateView(
                            icon: "wallet.bifold",
                            title: "No Wallets",
                            description: "No wallets found. Complete onboarding first."
                        )
                        .padding(.top, 40)
                    } else {
                        // Network badge
                        networkBadge
                            .padding(.top, 8)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)

                        // Wallet picker (only if multiple)
                        if wallets.count > 1 {
                            walletPicker
                                .padding(.top, 20)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 8)
                        }

                        // QR hero
                        if let wallet = activeWallet {
                            qrHero(address: wallet.address)
                                .padding(.top, 24)
                                .opacity(appeared ? 1 : 0)
                                .scaleEffect(appeared ? 1 : 0.92)

                            // Address + actions
                            addressSection(wallet.address)
                                .padding(.top, 20)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 12)

                            // Balance context
                            if let balance = Double(wallet.usdcBalance), balance > 0 {
                                balancePill(wallet.usdcBalance)
                                    .padding(.top, 16)
                                    .opacity(appeared ? 1 : 0)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("Add Funds"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .sensoryFeedback(.success, trigger: copied)
        .sensoryFeedback(.error, trigger: error)
        .task {
            await loadWallets()
            // Auto-expand if QR is visible immediately (single wallet)
            if wallets.count == 1 {
                withAnimation { sheetDetent = .large }
            }
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Network Badge

    private var networkBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.25, green: 0.52, blue: 0.96))
                .frame(width: 8, height: 8)

            Text("Base")
                .font(.caption2.weight(.semibold))

            Text("·")
                .foregroundStyle(.tertiary)

            Image(systemName: "dollarsign.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)

            Text("USDC")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    // MARK: - Wallet Picker

    private var walletPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELECT WALLET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(1)
                .padding(.leading, 4)

            ForEach(wallets) { wallet in
                let isSelected = selectedWallet?.id == wallet.id
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedWallet = wallet
                        copied = false
                        sheetDetent = .large
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Wallet icon
                        Image(systemName: "wallet.bifold")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.12)
                                    : Color(.systemGray5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortAddress(wallet.address))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.primary)
                            Text("\(CurrencyFormatter.format(wallet.usdcBalance)) USDC")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.5) : .clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - QR Hero

    private func qrHero(address: String) -> some View {
        VStack(spacing: 0) {
            ZStack {
                // Outer glow
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.accentColor.opacity(0.06))
                    .padding(-6)

                // Card background
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemGroupedBackground))

                // QR code — plain address (best wallet compatibility)
                VStack(spacing: 0) {
                    if let qrImage = generateQRCode(from: address) {
                        ZStack {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            // Branded center overlay
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentColor)
                                .background(
                                    Circle()
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .frame(width: 38, height: 38)
                                )
                        }
                        .padding(24)
                    }
                }

                // Accent border
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.4),
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.3),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .frame(maxWidth: 260)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Address Section

    private func addressSection(_ address: String) -> some View {
        VStack(spacing: 14) {
            Text(shortAddress(address))
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = address
                    withAnimation(.spring(duration: 0.3)) {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? "Copied!" : "Copy")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        copied
                            ? Color.accentColor.opacity(0.12)
                            : Color(.secondarySystemGroupedBackground)
                    )
                    .foregroundStyle(copied ? Color.accentColor : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(copied ? Color.accentColor.opacity(0.3) : Color(.separator).opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: address) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                        Text("Share")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Balance Pill

    private func balancePill(_ balance: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wallet.bifold")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Current balance:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.format(balance))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    // MARK: - Loading & Error States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading wallets...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                error = nil
                Task { await loadWallets() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.top, 40)
    }

    // MARK: - Helpers

    private var activeWallet: WalletInfo? {
        wallets.count == 1 ? wallets.first : selectedWallet
    }

    private func shortAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    /// EIP-681 payment request URI: pre-selects USDC on Base Sepolia when scanned
    /// Format: ethereum:<usdc_contract>@<chainId>/transfer?address=<recipient>
    private func eip681URI(for recipientAddress: String) -> String {
        return "ethereum:\(AppConstants.usdcAddress)@\(AppConstants.chainId)/transfer?address=\(recipientAddress)"
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
            print("[AddFunds] load error: \(error)")
            self.error = "Failed to load wallets. Please try again."
        }
        isLoading = false
    }

    // MARK: - QR Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H" // High correction for center overlay
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

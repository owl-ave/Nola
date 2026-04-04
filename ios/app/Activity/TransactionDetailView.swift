import SwiftUI

struct TransactionDetailView: View {
    @EnvironmentObject var appState: AppState
    let transaction: TransactionItem

    @State private var chainDetail: ChainDetailResponse?
    @State private var isLoadingChainDetail = false
    @State private var copied: String?
    @State private var isVisible = false

    private var activityService: ActivityService { ActivityService(client: appState.apiClient) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                detailsCard
                addressesCard

                if transaction.source == "chain" {
                    chainDetailsCard
                }

                if let url = transaction.explorerUrl {
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on Basescan")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: isVisible)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Transaction"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { isVisible = true }
        }
        .task {
            if transaction.source == "chain" && transaction.txHash != nil {
                await loadChainDetail()
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            // Merchant icon or system icon
            if let iconUrl = transaction.merchantIcon, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: transaction.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(transaction.iconColor)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1)
                )
            } else {
                Image(systemName: transaction.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(transaction.iconColor)
                    .frame(width: 56, height: 56)
                    .background(transaction.iconColor.opacity(0.1))
                    .clipShape(Circle())
            }

            Text(transaction.formattedAmount)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(transaction.isCredit ? Color.accentColor : .primary)

            // Description + badges
            VStack(spacing: 8) {
                Text(transaction.description)
                    .font(.headline)

                HStack(spacing: 8) {
                    if let category = transaction.merchantCategory {
                        badge(category, color: transaction.iconColor)
                    }

                    statusBadge

                    badge(transaction.sourceLabel, color: .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch transaction.status {
        case "pending":
            badge("Pending", color: .yellow)
        case "failed":
            badge("Failed", color: .red)
        case "confirmed":
            if let detail = chainDetail {
                badge("\(detail.confirmations) confirmations", color: .green)
            } else {
                badge("Confirmed", color: .green)
            }
        case "settled":
            badge("Settled", color: .green)
        default:
            EmptyView()
        }
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(spacing: 0) {
            DetailRow(label: "Type", value: transaction.typeLabel ?? transaction.description)

            if let merchant = transaction.merchantName, merchant != transaction.description {
                Divider().padding(.leading, 16)
                DetailRow(label: "Merchant", value: merchant)
            }

            Divider().padding(.leading, 16)
            DetailRow(label: "Status", value: transaction.statusLabel)

            Divider().padding(.leading, 16)
            DetailRow(label: "Date", value: transaction.formattedDate)

            Divider().padding(.leading, 16)
            DetailRow(label: "Source", value: transaction.sourceLabel)

            if let cardId = transaction.cardId {
                Divider().padding(.leading, 16)
                DetailRow(label: "Card", value: "•••• \(String(cardId.suffix(4)))")
            }

            if let rainType = transaction.rainType {
                Divider().padding(.leading, 16)
                DetailRow(label: "Rain Type", value: rainType)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: isVisible)
    }

    // MARK: - Addresses & IDs Card

    @ViewBuilder
    private var addressesCard: some View {
        let hasContent = transaction.txHash != nil
            || transaction.rainTransactionId != nil
            || transaction.fromAddress != nil
            || transaction.toAddress != nil

        if hasContent {
            VStack(spacing: 0) {
                if transaction.source == "rain", let rainId = transaction.rainTransactionId {
                    copyableRow(label: "Transaction ID", value: rainId, truncate: true)
                }

                if let hash = transaction.txHash {
                    if transaction.rainTransactionId != nil { Divider().padding(.leading, 16) }
                    copyableRow(label: "Transaction Hash", value: hash, truncate: true)
                }

                if let from = transaction.fromAddress {
                    Divider().padding(.leading, 16)
                    copyableRow(label: "From", value: from, truncate: true)
                }

                if let to = transaction.toAddress {
                    Divider().padding(.leading, 16)
                    copyableRow(label: "To", value: to, truncate: true)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
            .animation(.easeOut(duration: 0.4).delay(0.15), value: isVisible)
        }
    }

    // MARK: - Chain Details Card (Live)

    private var chainDetailsCard: some View {
        Group {
            if isLoadingChainDetail {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            } else if let detail = chainDetail {
                VStack(spacing: 0) {
                    DetailRow(label: "Block", value: "#\(detail.blockNumber)")
                    Divider().padding(.leading, 16)
                    DetailRow(label: "Block Time", value: formatBlockTimestamp(detail.blockTimestamp))
                    Divider().padding(.leading, 16)
                    DetailRow(label: "Gas Used", value: detail.gasUsed)
                    Divider().padding(.leading, 16)
                    DetailRow(label: "Confirmations", value: "\(detail.confirmations)")
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: isVisible)
    }

    // MARK: - Helpers

    private func loadChainDetail() async {
        isLoadingChainDetail = true
        do {
            chainDetail = try await activityService.fetchChainDetail(transactionId: transaction.id)
        } catch {
            print("[ChainDetail] error: \(error)")
        }
        isLoadingChainDetail = false
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func copyableRow(label: String, value: String, truncate: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(truncate ? truncatedValue(value) : value)
                    .font(.subheadline.monospaced())
                    .lineLimit(1)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
                withAnimation(.easeInOut(duration: 0.2)) { copied = value }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { if copied == value { copied = nil } }
                }
            } label: {
                Image(systemName: copied == value ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(copied == value ? .green : Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func truncatedValue(_ value: String) -> String {
        guard value.count > 16 else { return value }
        return "\(value.prefix(10))...\(value.suffix(6))"
    }

    private func formatBlockTimestamp(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

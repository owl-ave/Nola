import SwiftUI

struct CardDetailsSheet: View {
    @Environment(\.dismiss) var dismiss

    let card: CardListItem
    let secrets: CardSecretsResponse
    let cardholderName: String

    @State private var copied: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Visual card with full number
                    NolaCardVisual(
                        last4: card.last4,
                        cardholderName: cardholderName,
                        expiry: card.expiry ?? secrets.expiry,
                        isFrozen: card.isFrozen,
                        type: card.type,
                        fullCardNumber: secrets.cardNumber
                    )
                    .padding(.horizontal, 20)

                    // Card info
                    VStack(spacing: 0) {
                        DetailRow(label: "Status", showDivider: true) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(card.isFrozen ? Color.red : Color.green)
                                    .frame(width: 8, height: 8)
                                Text(card.isFrozen ? "Frozen" : "Active")
                                    .font(.subheadline)
                            }
                        }

                        DetailRow(label: "Card Type", showDivider: true) {
                            Text(card.type.capitalized)
                                .font(.subheadline)
                        }

                        DetailRow(label: "Display Name", showDivider: false) {
                            Text(card.displayName)
                                .font(.subheadline)
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Sensitive details
                    VStack(spacing: 0) {
                        CopyableDetailRow(
                            label: "Card Number",
                            value: formatCardNumber(secrets.cardNumber),
                            rawValue: secrets.cardNumber,
                            copied: copied == "number",
                            showDivider: true
                        ) {
                            copyToClipboard(secrets.cardNumber, key: "number")
                        }

                        CopyableDetailRow(
                            label: "Expiry",
                            value: secrets.expiry,
                            rawValue: secrets.expiry,
                            copied: copied == "expiry",
                            showDivider: true
                        ) {
                            copyToClipboard(secrets.expiry, key: "expiry")
                        }

                        CopyableDetailRow(
                            label: "CVV",
                            value: secrets.cvv,
                            rawValue: secrets.cvv,
                            copied: copied == "cvv",
                            showDivider: false
                        ) {
                            copyToClipboard(secrets.cvv, key: "cvv")
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(Text("Card Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: copied)
        }
    }

    private func formatCardNumber(_ number: String) -> String {
        stride(from: 0, to: number.count, by: 4).map { i in
            let start = number.index(number.startIndex, offsetBy: i)
            let end = number.index(start, offsetBy: min(4, number.count - i))
            return String(number[start..<end])
        }.joined(separator: " ")
    }

    private func copyToClipboard(_ value: String, key: String) {
        UIPasteboard.general.string = value
        copied = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copied == key { copied = nil }
        }
    }
}

// MARK: - Detail Row

private struct DetailRow<Content: View>: View {
    let label: String
    let showDivider: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

// MARK: - Copyable Detail Row

private struct CopyableDetailRow: View {
    let label: String
    let value: String
    let rawValue: String
    let copied: Bool
    let showDivider: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline.monospaced())
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

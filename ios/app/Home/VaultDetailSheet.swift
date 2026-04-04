import SwiftUI

struct VaultDetailSheet: View {
    let balance: String
    let apy: String
    let yieldEarned: String
    let onWithdraw: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // MARK: - Balance
                VStack(spacing: 6) {
                    Text("VAULT BALANCE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)

                    Text(CurrencyFormatter.format(balance))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                }
                .padding(.top, 8)

                // MARK: - Stats
                HStack(spacing: 16) {
                    statCard(label: "APY", value: "\(apy)%", color: Color(red: 0.23, green: 0.51, blue: 0.96))
                    statCard(label: "Yield Earned", value: "+\(CurrencyFormatter.format(yieldEarned))", color: Color.accentColor)
                }
                .padding(.horizontal, 20)

                // MARK: - Info
                VStack(alignment: .leading, spacing: 12) {
                    infoRow(icon: "shield.checkmark", text: "Secured by Aave V3 on Base")
                    infoRow(icon: "clock.arrow.circlepath", text: "Yield accrues automatically")
                    infoRow(icon: "arrow.up.circle", text: "Withdraw anytime, no lock-up")
                }
                .padding(.horizontal, 24)

                Spacer()

                // MARK: - Withdraw Button
                Button(action: onWithdraw) {
                    Text("Withdraw")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.23, green: 0.51, blue: 0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .navigationTitle(Text("Vault"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

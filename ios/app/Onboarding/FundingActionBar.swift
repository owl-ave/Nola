import SwiftUI

struct FundingActionBar: View {
    let balance: String
    let isPolling: Bool
    let showContinue: Bool
    let onFundWallet: () -> Void
    let onContinue: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 14) {
                // Balance
                VStack(spacing: 2) {
                    Text("$\(balance)")
                        .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.5), value: balance)
                    Text("USDC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Polling status
                if isPolling {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                            .modifier(PulseModifier())
                        Text("Checking for deposits...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Buttons
                HStack(spacing: 12) {
                    Button(action: onFundWallet) {
                        Label("Fund Wallet", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    if showContinue {
                        Button(action: onContinue) {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

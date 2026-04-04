import SwiftUI

struct KycActionBar: View {
    let onExplore: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {} label: {
                    Text("Complete KYC")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(true)

                Button(action: onExplore) {
                    Label("Explore", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

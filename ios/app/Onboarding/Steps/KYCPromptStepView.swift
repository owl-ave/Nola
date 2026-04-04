import SwiftUI

struct KYCPromptStepView: View {
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready to verify your identity?")
                .font(.headline)

            VStack(spacing: 8) {
                Button {
                    // KYC disabled for now
                } label: {
                    Text("Complete KYC")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .disabled(true)

                Button {
                    onChoice(false)
                } label: {
                    Text("Explore")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
            }

            Text("KYC coming soon. Explore your account for now!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
}

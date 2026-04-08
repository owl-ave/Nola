import SwiftUI

struct SplitConfigActionBar: View {
    let onAccept: () -> Void
    let onChange: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Text("Sounds Good")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button(action: onChange) {
                    Text("Change")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

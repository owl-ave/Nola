import SwiftUI

struct FaceIDStepView: View {
    let biometricLabel: String
    let biometricIcon: String
    let onChoice: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: biometricIcon)
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Enable \(biometricLabel)?")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Yes") { onChoice(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)

                Button("No thanks") { onChoice(false) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}

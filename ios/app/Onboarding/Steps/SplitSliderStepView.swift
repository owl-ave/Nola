import SwiftUI

struct SplitSliderStepView: View {
    let total: Double
    let onConfirm: (Double) -> Void

    @State private var cardPercent: Double = 50

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(cardAmount))
                        .font(.title3.bold())
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Vault")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(vaultAmount))
                        .font(.title3.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }

            Slider(value: $cardPercent, in: 0...100, step: 1)
                .tint(Color.accentColor)

            HStack {
                Text("\(Int(cardPercent))% card")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(100 - Int(cardPercent))% vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Confirm Split") {
                onConfirm(cardPercent)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
        .padding(.vertical, 8)
    }

    private var cardAmount: Double {
        total * cardPercent / 100
    }

    private var vaultAmount: Double {
        total * (100 - cardPercent) / 100
    }
}

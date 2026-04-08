import SwiftUI

struct TopupChipsStepView: View {
    let suggestions: [Int]
    let max: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(suggestions, id: \.self) { amount in
                    Button(CurrencyFormatter.format(Double(amount))) {
                        onSelect(amount)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                }
            }

            Text("Or type a custom amount below")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

import SwiftUI

struct NolaCardVisual: View {
    let last4: String
    let cardholderName: String
    let expiry: String?
    let isFrozen: Bool
    let type: String
    var isCanceled: Bool = false
    var fullCardNumber: String? = nil

    private var formattedCardNumber: String {
        if let full = fullCardNumber {
            return stride(from: 0, to: full.count, by: 4).map { i in
                let start = full.index(full.startIndex, offsetBy: i)
                let end = full.index(start, offsetBy: min(4, full.count - i))
                return String(full[start..<end])
            }.joined(separator: " ")
        }
        return "•••• •••• •••• \(last4)"
    }

    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.08, blue: 0.09),
                            Color(red: 0.13, green: 0.13, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Subtle emerald glow
            Circle()
                .fill(Color.accentColor.opacity(0.06))
                .frame(width: 220, height: 220)
                .offset(x: 90, y: -70)
                .blur(radius: 50)

            // Border
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Top: Logo + type badge
                HStack(alignment: .top) {
                    Image("NolaMarkSmall")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    Text(type == "physical" ? "PHYSICAL" : "VIRTUAL")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.06))
                        .clipShape(Capsule())
                }

                Spacer()

                // Chip
                ChipGraphic()
                    .padding(.bottom, 16)

                // Card number
                Text(formattedCardNumber)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 16)

                // Bottom: Cardholder + Expiry
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARDHOLDER")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                        Text(cardholderName.uppercased())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    if let expiry {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("EXPIRES")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                            Text(expiry)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
            }
            .padding(20)

            // Frozen overlay
            if isFrozen {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title)
                    Text("FROZEN")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.secondary)
            }

            // Canceled overlay
            if isCanceled {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                    Text("CANCELED")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Chip Graphic

private struct ChipGraphic: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.82, green: 0.74, blue: 0.50).opacity(0.25))
                .frame(width: 40, height: 30)

            // Chip lines
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(red: 0.82, green: 0.74, blue: 0.50).opacity(0.5))
                        .frame(width: 24, height: 1)
                }
            }

            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.74, blue: 0.50).opacity(0.4))
                    .frame(width: 1, height: 18)
                Rectangle()
                    .fill(Color(red: 0.82, green: 0.74, blue: 0.50).opacity(0.4))
                    .frame(width: 1, height: 18)
            }
        }
    }
}

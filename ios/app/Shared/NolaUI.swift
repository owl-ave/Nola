import SwiftUI

// MARK: - Animated Gradient Background

struct AnimatedGradientBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Color(.systemBackground)

            // Emerald glow orbs that drift slowly
            Circle()
                .fill(Color.accentColor.opacity(0.07))
                .frame(width: 300, height: 300)
                .offset(
                    x: 80 * cos(phase),
                    y: 60 * sin(phase * 0.7)
                )
                .blur(radius: 80)

            Circle()
                .fill(Color.accentColor.opacity(0.05))
                .frame(width: 200, height: 200)
                .offset(
                    x: -60 * cos(phase * 0.8),
                    y: -80 * sin(phase)
                )
                .blur(radius: 60)

            Circle()
                .fill(Color.accentColor.opacity(0.03))
                .frame(width: 250, height: 250)
                .offset(
                    x: 40 * sin(phase * 1.2),
                    y: 100 * cos(phase * 0.5)
                )
                .blur(radius: 70)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Branded Spinner

struct BrandedSpinner: View {
    @State private var isRotating = false

    var body: some View {
        Image("NolaMarkSmall")
            .resizable()
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .opacity(isRotating ? 1 : 0.6)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
            }
    }
}

// MARK: - Confetti Effect

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: isAnimating ? particle.endX : 0,
                        y: isAnimating ? particle.endY : 0
                    )
                    .opacity(isAnimating ? 0 : 1)
            }
        }
        .onAppear {
            particles = (0..<24).map { _ in ConfettiParticle() }
            withAnimation(.easeOut(duration: 1.2)) {
                isAnimating = true
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    let endX: CGFloat
    let endY: CGFloat

    init() {
        let colors: [Color] = [
            .accentColor,
            .accentColor.opacity(0.7),
            Color(red: 0.42, green: 0.91, blue: 0.72), // lighter emerald
            Color(red: 0.06, green: 0.52, blue: 0.38), // darker emerald
            .white.opacity(0.5),
        ]
        color = colors.randomElement()!
        size = CGFloat.random(in: 4...8)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let distance = CGFloat.random(in: 60...140)
        endX = cos(angle) * distance
        endY = sin(angle) * distance - 30
    }
}

// MARK: - Pulsing Rings

struct PulsingRingsView: View {
    let icon: String
    let iconSize: CGFloat
    @State private var isAnimating = false

    init(icon: String, iconSize: CGFloat = 40) {
        self.icon = icon
        self.iconSize = iconSize
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color.accentColor.opacity(0.06), lineWidth: 1.5)
                .frame(width: 140, height: 140)
                .scaleEffect(isAnimating ? 1.08 : 1.0)

            // Middle ring
            Circle()
                .stroke(Color.accentColor.opacity(0.1), lineWidth: 1.5)
                .frame(width: 100, height: 100)
                .scaleEffect(isAnimating ? 1.05 : 0.98)

            // Inner filled circle
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 72, height: 72)

            // Icon
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(Color.accentColor)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Empty State View

struct NolaEmptyStateView: View {
    let icon: String
    let title: String
    let description: String

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 20) {
            PulsingRingsView(icon: icon, iconSize: 32)
                .scaleEffect(isVisible ? 1 : 0.8)
                .opacity(isVisible ? 1 : 0)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Coming Soon View

struct ComingSoonView: View {
    let icon: String
    let title: String
    let description: String

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 24) {
            PulsingRingsView(icon: icon, iconSize: 36)
                .scaleEffect(isVisible ? 1 : 0.8)
                .opacity(isVisible ? 1 : 0)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)

            Text("Coming Soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Capsule())
                .opacity(isVisible ? 1 : 0)
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Floating Modifier

struct FloatingModifier: ViewModifier {
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                    offset = -8
                }
            }
    }
}

extension View {
    func floating() -> some View {
        modifier(FloatingModifier())
    }
}

import SwiftUI

struct SplashView: View {
    var status: String = "Loading"

    @State private var logoVisible = false
    @State private var textVisible = false
    @State private var glowPhase: CGFloat = 0
    @State private var dotPhase = 0

    var body: some View {
        ZStack {
            // Deep dark canvas
            Color(red: 0.04, green: 0.04, blue: 0.05)
                .ignoresSafeArea()

            // Breathing emerald glow — large, diffused, behind logo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.15),
                            Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.04),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .scaleEffect(glowPhase == 1 ? 1.15 : 0.9)
                .opacity(glowPhase == 1 ? 1 : 0.6)

            // Secondary subtle glow offset slightly up-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.06),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .offset(x: 60, y: -80)
                .scaleEffect(glowPhase == 1 ? 1.0 : 1.2)

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Image("NolaMark")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.4), radius: 24, x: 0, y: 8)
                    .scaleEffect(logoVisible ? 1.0 : 0.8)
                    .opacity(logoVisible ? 1 : 0)

                // App name
                Text("nola")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(6)
                    .padding(.top, 20)
                    .opacity(textVisible ? 1 : 0)
                    .offset(y: textVisible ? 0 : 8)

                Spacer()

                // Loading indicator — three breathing dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color(red: 0.063, green: 0.725, blue: 0.506))
                            .frame(width: 6, height: 6)
                            .opacity(dotPhase == index ? 1.0 : 0.25)
                            .scaleEffect(dotPhase == index ? 1.3 : 1.0)
                    }
                }
                .padding(.bottom, 12)

                // Status text
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
                    .animation(.easeInOut(duration: 0.3), value: status)
                    .contentTransition(.opacity)

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                logoVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textVisible = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                glowPhase = 1
            }
            startDotAnimation()
        }
        .accessibilityIdentifier("SplashView")
    }

    private func startDotAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                dotPhase = (dotPhase + 1) % 3
            }
        }
    }
}

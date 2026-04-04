import SwiftUI

struct RecordingInputBar: View {
    var recorder: AudioRecorderManager
    let onSend: (String) -> Void
    let onStop: (String) -> Void
    let onCancel: () -> Void

    private var timeString: String {
        let m = recorder.elapsedSeconds / 60
        let s = recorder.elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Recording indicator + Cancel
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .pulsingGlow(color: .red)

                    Text(timeString)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    recorder.cancelRecording()
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // MARK: - Transcript (the hero)
            Group {
                if recorder.transcript.isEmpty {
                    HStack(spacing: 0) {
                        Text("Listening")
                            .foregroundStyle(.tertiary)
                        TypingCursor()
                    }
                } else {
                    Text(recorder.transcript)
                        .foregroundStyle(.primary)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

            // MARK: - Waveform strip
            WaveformStrip(levels: recorder.audioLevels)
                .frame(height: 48)

            // MARK: - Actions
            HStack {
                Button {
                    let text = recorder.stopRecording()
                    onStop(text)
                } label: {
                    Text("Edit")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                Button {
                    let text = recorder.stopRecording()
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend(text)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Send")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        .padding(20)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Waveform Strip

private struct WaveformStrip: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let count = max(Int(geo.size.width / (barWidth + spacing)), 1)

            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let level = level(at: index, barCount: count)
                    Capsule()
                        .fill(Color.accentColor.opacity(max(level, 0.2)))
                        .frame(width: barWidth, height: max(level * geo.size.height, 3))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func level(at index: Int, barCount: Int) -> CGFloat {
        let count = levels.count
        guard count > 0 else { return 0 }
        let levelIndex = index * count / barCount
        return levelIndex < count ? levels[levelIndex] : 0
    }
}

// MARK: - Pulsing Glow

private struct PulsingGlow: ViewModifier {
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.6 : 0), radius: isPulsing ? 6 : 0)
            .scaleEffect(isPulsing ? 1.2 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func pulsingGlow(color: Color) -> some View {
        modifier(PulsingGlow(color: color))
    }
}

// MARK: - Typing Cursor

private struct TypingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("...")
            .foregroundStyle(.tertiary)
            .opacity(visible ? 1 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

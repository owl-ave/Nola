import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.sender == .bot {
                Image("NolaMarkSmall")
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .padding(.top, 6)
            }

            if message.sender == .user { Spacer(minLength: 60) }

            bubbleContent

            if message.sender == .bot { Spacer(minLength: 40) }
        }
        .padding(.leading, message.sender == .bot ? 14 : 16)
        .padding(.trailing, message.sender == .user ? 14 : 16)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if let text = message.text {
            if message.sender == .user {
                // User: clean right-aligned text on glass
                Text(.init(text))
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                // Bot: frosted glass bubble
                Text(.init(text))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else if let interactive = message.interactive {
            interactiveView(for: interactive)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private func interactiveView(for content: InteractiveContent) -> some View {
        switch content {
        case .txProgress(let steps):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(steps) { step in
                    HStack(spacing: 8) {
                        stepIndicator(step.status)
                            .frame(width: 16, height: 16)
                        Text(step.label)
                            .font(.subheadline)
                            .foregroundStyle(step.status == .completed ? .primary : .secondary)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func stepIndicator(_ status: TxStepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)
        case .inProgress:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

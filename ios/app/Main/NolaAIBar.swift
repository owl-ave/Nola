import SwiftUI

// MARK: - Tab Accessory (recreated freely — no state, reads router)

struct NolaAIBar: View {
    @Environment(NavigationRouter.self) var router

    @AppStorage("preferredLanguage") private var preferredLanguage = "en"

    private var suggestion: (text: String, prompt: String) {
        let options = TabSuggestions.forTab(router.selectedTab, locale: preferredLanguage)
        guard !options.isEmpty else { return ("Ask anything", "Hello") }
        let index = abs(router.suggestionSeed) % options.count
        return options[index]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Suggestion — sends prompt + opens chat
            Button {
                router.pendingChatPrompt = suggestion.prompt
                router.showChat = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TypingText(text: suggestion.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Divider
            Capsule()
                .fill(.quaternary)
                .frame(width: 1, height: 16)

            // Open chat
            Button {
                router.showChat = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Ask Nola")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.primary)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            router.suggestionSeed = Int.random(in: 0..<1000)
        }
    }

}

// MARK: - Typing Animation Text

private struct TypingText: View {
    let text: String
    @State private var visibleCount = 0

    var body: some View {
        Text(String(text.prefix(visibleCount)))
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .onAppear {
                visibleCount = 0
                animateTyping()
            }
            .onChange(of: text) {
                visibleCount = 0
                animateTyping()
            }
    }

    private func animateTyping() {
        let chars = text.count
        for i in 1...chars {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                withAnimation(.easeOut(duration: 0.05)) {
                    visibleCount = i
                }
            }
        }
    }
}

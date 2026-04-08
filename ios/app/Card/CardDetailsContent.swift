import SwiftUI

/// Fetches and displays card secrets after authentication.
/// Used inside AuthGateView — only renders after auth succeeds.
struct CardDetailsContent: View {
    let card: CardListItem
    let cardholderName: String
    let appState: AppState

    @State private var secrets: CardSecretsResponse?
    @State private var isLoading = true
    @State private var error: String?

    private var cardService: CardService { CardService(client: appState.apiClient) }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading card details...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let secrets {
                CardDetailsSheet(card: card, secrets: secrets, cardholderName: cardholderName)
                    .navigationBarHidden(true)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error ?? "Failed to load card details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadSecrets() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadSecrets() }
    }

    private func loadSecrets() async {
        isLoading = true
        error = nil
        do {
            secrets = try await cardService.fetchSecrets(cardId: card.id)
        } catch {
            self.error = "Failed to load card details. Please try again."
            print("[Card] secrets error: \(error)")
        }
        isLoading = false
    }
}

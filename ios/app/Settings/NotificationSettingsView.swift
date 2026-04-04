import SwiftUI

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var notificationsEnabled = true
    @State private var loading = true

    var body: some View {
        List {
            Section {
                Toggle("Transaction Notifications", isOn: $notificationsEnabled)
                    .disabled(loading)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        guard !loading else { return }
                        Task { await updateSetting(newValue) }
                    }
            } footer: {
                Text("Receive push notifications for deposits, withdrawals, card spending, and top-ups.")
            }
        }
        .navigationTitle(Text("Notifications"))
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        do {
            struct SettingsResponse: Decodable {
                let notificationsEnabled: Int
            }
            let settings: SettingsResponse = try await appState.apiClient.request("GET", path: "/v1/settings")
            notificationsEnabled = settings.notificationsEnabled == 1
            loading = false
        } catch {
            print("[Settings] Failed to load notification settings: \(error)")
            loading = false
        }
    }

    private func updateSetting(_ enabled: Bool) async {
        do {
            struct SettingsUpdate: Encodable {
                let notificationsEnabled: Int
            }
            struct SettingsResponse: Decodable {
                let notificationsEnabled: Int
            }
            let _: SettingsResponse = try await appState.apiClient.request(
                "PATCH",
                path: "/v1/settings",
                body: SettingsUpdate(notificationsEnabled: enabled ? 1 : 0)
            )
        } catch {
            print("[Settings] Failed to update notification settings: \(error)")
            notificationsEnabled = !enabled // revert on failure
        }
    }
}

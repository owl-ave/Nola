import SwiftUI

struct AIPermissionsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var canViewBalance = false
    @State private var canViewTransactions = false
    @State private var canFreezeCard = false
    @State private var canInitiateTransfers = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError = false
    @State private var saveError = false

    var body: some View {
        content
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(Text("AI Permissions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await loadPermissions() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadError {
            errorState
        } else {
            permissionsForm
        }
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Couldn't load permissions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await loadPermissions() }
            }
            .buttonStyle(.bordered)
            .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionsForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                permissionsList
                caption
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("NolaMarkSmall")
                .resizable()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Nola AI")
                    .font(.subheadline.weight(.semibold))
                Text("Choose what your assistant can access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsList: some View {
        VStack(spacing: 0) {
            permissionRow(
                icon: "eye",
                color: Color.accentColor,
                title: "View Balance & Cards",
                subtitle: "Check balances and card details",
                isGranted: $canViewBalance
            )
            rowDivider
            permissionRow(
                icon: "list.bullet.rectangle",
                color: .blue,
                title: "View Transactions",
                subtitle: "Read transaction history",
                isGranted: $canViewTransactions
            )
            rowDivider
            permissionRow(
                icon: "lock.shield",
                color: .orange,
                title: "Freeze & Unfreeze Cards",
                subtitle: "Lock or unlock your cards",
                isGranted: $canFreezeCard
            )
            rowDivider
            permissionRow(
                icon: "arrow.left.arrow.right",
                color: .purple,
                title: "Initiate Transfers",
                subtitle: "Move funds between accounts",
                isGranted: $canInitiateTransfers
            )
        }
        .padding(.vertical, 4)
        .tint(.primary)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }

    private func permissionRow(icon: String, color: Color, title: String, subtitle: String, isGranted: Binding<Bool>) -> some View {
        Button {
            isGranted.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isGranted.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isGranted.wrappedValue ? Color.accentColor : Color(UIColor.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.15), value: isGranted.wrappedValue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 56)
    }

    @ViewBuilder
    private var caption: some View {
        if saveError {
            Text("Failed to save. Please try again.")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.leading, 4)
        } else {
            Text("These permissions only affect what Nola AI can do when you chat. You can change them anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(loadError)
            }
        }
    }

    // MARK: - API

    private func loadPermissions() async {
        isLoading = true
        loadError = false
        struct PermissionsResponse: Decodable {
            let permissions: [String: Int]
        }
        do {
            let response: PermissionsResponse = try await appState.apiClient.request("GET", path: "/v1/user/agent-permissions")
            canViewBalance = response.permissions["setting_agentCanViewBalance"] == 1
            canViewTransactions = response.permissions["setting_agentCanViewTransactions"] == 1
            canFreezeCard = response.permissions["setting_agentCanFreezeCard"] == 1
            canInitiateTransfers = response.permissions["setting_agentCanInitiateTransfers"] == 1
        } catch {
            loadError = true
            print("[AIPermissions] load error: \(error)")
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        saveError = false
        let body: [String: Int] = [
            "setting_agentCanViewBalance": canViewBalance ? 1 : 0,
            "setting_agentCanViewTransactions": canViewTransactions ? 1 : 0,
            "setting_agentCanFreezeCard": canFreezeCard ? 1 : 0,
            "setting_agentCanInitiateTransfers": canInitiateTransfers ? 1 : 0,
        ]
        struct PermissionsResponse: Decodable { let permissions: [String: Int] }
        do {
            let _: PermissionsResponse = try await appState.apiClient.request("PATCH", path: "/v1/user/agent-permissions", body: body)
            dismiss()
        } catch {
            saveError = true
            print("[AIPermissions] save error: \(error)")
        }
        isSaving = false
    }
}

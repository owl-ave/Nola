import SwiftUI
import PrivySDK

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gateState: AppGateState
    @EnvironmentObject var authManager: BiometricAuthManager

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var walletAddress: String?
    @State private var createdAtString: String?
    @State private var isLoading = true
    @State private var errorAlert: String?
    @State private var addressCopied = false
    @State private var showLogoutConfirm = false
    @State private var showLogoutAuth = false

    var body: some View {
        Form {
            // MARK: - Hero
            Section {
                VStack(spacing: 12) {
                    if isLoading {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .shimmer()

                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(width: 120, height: 20)
                                .shimmer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(width: 160, height: 15)
                                .shimmer()
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Text(initials)
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(spacing: 4) {
                            Text(fullName)
                                .font(.title2.weight(.semibold))
                            if let email = userEmail {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // MARK: - Wallet
            if let address = walletAddress {
                Section("Wallet") {
                    Button {
                        UIPasteboard.general.string = address
                        addressCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            addressCopied = false
                        }
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(truncateAddress(address))
                                    .font(.subheadline.monospaced())
                                Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(addressCopied ? .green : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Text("Address")
                        }
                    }
                    .tint(.primary)
                }
            }

            // MARK: - Account
            if let date = memberSinceDate {
                Section("Account") {
                    LabeledContent("Member Since") {
                        Text(date, format: .dateTime.month(.wide).year())
                    }
                }
            }
        }
        .navigationTitle(Text("Profile"))
        .toolbar {
            if !isLoading {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink(value: SettingsDestination.editProfile(
                            firstName: firstName,
                            lastName: lastName
                        )) {
                            Label("Edit Profile", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task { await loadProfile() }
        .confirmationDialog("Are you sure you want to log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task {
                    if await authManager.authenticate() {
                        await gateState.logout(appState: appState)
                    } else {
                        showLogoutAuth = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showLogoutAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showLogoutAuth = false })) {
                    showLogoutAuth = false
                    Task { await gateState.logout(appState: appState) }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
    }

    // MARK: - Helpers

    private var fullName: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Nola User" : name
    }

    private var initials: String {
        let parts = [firstName, lastName].filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    private var userEmail: String? {
        guard let user = appState.privy.user else { return nil }
        for account in user.linkedAccounts {
            if case .email(let emailAccount) = account {
                return emailAccount.email
            }
        }
        return nil
    }

    private var memberSinceDate: Date? {
        guard let str = createdAtString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str)
    }

    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    // MARK: - API

    private struct ProfileResponse: Decodable {
        let user: ProfileData
    }

    private struct ProfileData: Decodable {
        let firstName: String?
        let lastName: String?
        let privyWalletAddress: String?
        let createdAt: String?
    }

    private func loadProfile() async {
        do {
            let response: ProfileResponse = try await appState.apiClient.request("GET", path: "/v1/user/profile")
            firstName = response.user.firstName ?? ""
            lastName = response.user.lastName ?? ""
            walletAddress = response.user.privyWalletAddress
            createdAtString = response.user.createdAt
        } catch {
            errorAlert = "Failed to load profile."
        }
        isLoading = false
    }
}

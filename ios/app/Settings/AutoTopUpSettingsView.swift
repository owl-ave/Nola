import SwiftUI

struct AutoTopUpSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: BiometricAuthManager
    @Environment(\.dismiss) var dismiss
    var onSaved: (() -> Void)?

    @State private var isEnabled = true
    @State private var targetText = "100"
    @State private var thresholdValue: Double = 75
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorAlert: String?
    @State private var showSaveAuth = false

    @FocusState private var focusedField: Bool

    private let suggestedAmounts = [50, 100, 250, 500]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    shimmerContent
                } else {
                    enableToggle
                    if isEnabled {
                        targetSection
                        thresholdSection
                    }
                }
            }
            .padding(20)
            .animation(.easeOut(duration: 0.3), value: isLoading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("Auto Earn"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        focusedField = false
                        Task {
                            if await authManager.authenticate() {
                                await save()
                            } else {
                                showSaveAuth = true
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || isLoading)
                }
            }
        }
        .task { await loadSettings() }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.error, trigger: errorAlert)
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .sheet(isPresented: $showSaveAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: { showSaveAuth = false })) {
                    showSaveAuth = false
                    Task { await save() }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Shimmer Loading

    private var shimmerContent: some View {
        VStack(spacing: 24) {
            // Toggle skeleton
            HStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(.systemGray5))
                    .frame(width: 28, height: 28)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 30)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shimmer()

            // Target section skeleton
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 52)

                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray5))
                            .frame(width: 70, height: 32)
                    }
                }
            }
            .shimmer()

            // Threshold section skeleton
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 14)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 40, height: 20)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 28)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 32)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shimmer()
        }
    }

    // MARK: - Sections

    private var enableToggle: some View {
        HStack {
            Label {
                Text("Auto Earn")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(Color.accentColor)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spend Limit")
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 4)

            targetField

            chipRow

            Text("When you add funds, this amount goes to your card. The rest earns yield in your vault.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            if targetCents == nil && !targetText.isEmpty {
                Text("Enter a value between $10 and $1,000")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 4)
            }
        }
    }

    private var targetField: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("100", text: $targetText)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .keyboardType(.numberPad)
                .focused($focusedField, equals: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(suggestedAmounts, id: \.self) { amount in
                let isSelected = Int(targetText) == amount
                Button {
                    targetText = "\(amount)"
                    focusedField = false
                } label: {
                    Text(CurrencyFormatter.format(Double(amount)))
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .tint(.primary)
            }
        }
    }

    private var thresholdSection: some View {
        let maxThreshold = max(Double(Int(targetText) ?? 100), 10)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Refill Threshold")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(CurrencyFormatter.format(thresholdValue))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.leading, 4)

            Slider(
                value: $thresholdValue,
                in: 1...maxThreshold,
                step: 1
            )
            .tint(Color.accentColor)

            HStack {
                Text(CurrencyFormatter.format(1))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Spacer()
                Text(CurrencyFormatter.format(maxThreshold))
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 2)

            Text("When your card drops below \(CurrencyFormatter.format(thresholdValue)), funds move from vault to card automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Validation

    private var targetCents: Int? {
        guard let val = Int(targetText), val >= 10, val <= 1000 else { return nil }
        return val * 100
    }

    private var thresholdCents: Int {
        Int(thresholdValue) * 100
    }

    private var isValid: Bool {
        targetCents != nil
    }

    // MARK: - API

    private func loadSettings() async {
        struct SettingsResponse: Decodable {
            let cardTargetAmount: Int?
            let autoTopupThresholdPct: Int?
            let autoTopupEnabled: Int?
        }
        do {
            let response: SettingsResponse = try await appState.apiClient.request("GET", path: "/v1/settings")
            let cents = response.cardTargetAmount ?? 10000
            targetText = "\(cents / 100)"
            let thresholdCentsVal = response.autoTopupThresholdPct ?? 7500
            thresholdValue = Double(thresholdCentsVal / 100)
            isEnabled = (response.autoTopupEnabled ?? 1) == 1
        } catch {
            print("[AutoTopUp] load error: \(error)")
            errorAlert = "Failed to load settings."
        }
        isLoading = false
    }

    private func save() async {
        guard let cents = targetCents else { return }
        let thrCents = thresholdCents
        isSaving = true
        struct SaveBody: Encodable {
            let cardTargetAmount: Int
            let autoTopupThresholdPct: Int
            let autoTopupEnabled: Bool
        }
        struct SaveResponse: Decodable {
            let cardTargetAmount: Int
            let autoTopupThresholdPct: Int
            let autoTopupEnabled: Bool
        }
        do {
            let _: SaveResponse = try await appState.apiClient.request(
                "POST",
                path: "/v1/card/auto-topup",
                body: SaveBody(
                    cardTargetAmount: cents,
                    autoTopupThresholdPct: thrCents,
                    autoTopupEnabled: isEnabled
                )
            )
            saved = true
            onSaved?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
        } catch {
            print("[AutoTopUp] save error: \(error)")
            errorAlert = "Failed to save settings. Please try again."
        }
        isSaving = false
    }
}

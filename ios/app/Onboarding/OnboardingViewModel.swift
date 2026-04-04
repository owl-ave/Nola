import Combine
import Sentry
import SwiftUI
import UIKit

enum OnboardingStep: String {
    case name, fundWallet, splitConfig, transaction, kyc, completed
}

enum InteractionAction {
    case nameSubmitted(firstName: String, lastName: String)
    case splitConfigChoice(accepted: Bool)
    case kycChoice(complete: Bool)
}

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentStep: OnboardingStep = .name
    @Published var inputMode: InputMode = .text
    @Published var isProcessing = false
    @Published var txFailed = false
    @Published var walletBalance: String = "0.00"
    @Published var isPolling = false
    @Published var pollingTimedOut = false

    let apiClient: APIClient
    private var firstName = ""
    private var lastName = ""
    private var walletAddress = ""
    var userEmail = ""

    init(tokenProvider: @escaping () async throws -> String) {
        self.apiClient = APIClient(baseURL: AppConstants.apiBaseURL)
        self.apiClient.tokenProvider = tokenProvider
    }

    func startOnboarding() async {
        // Ensure embedded wallet exists with server-side delegation configured
        do {
            struct WalletResponse: Decodable {
                let address: String
                let walletId: String
                let delegationConfigured: Bool
            }
            let wallet: WalletResponse = try await apiClient.request("POST", path: "/v1/wallet/ensure-wallet")
            walletAddress = wallet.address
        } catch {
            print("[Onboarding] ensure-wallet failed: \(error.localizedDescription)")
            await addBotMessage("Failed to set up wallet: \(error.localizedDescription)")
            return
        }

        // Check backend for last completed step and restore saved profile data
        do {
            struct ProfileResponse: Decodable {
                let user: UserProfile
            }
            struct UserProfile: Decodable {
                let onboardingStep: String?
                let firstName: String?
                let lastName: String?
                let privyWalletAddress: String?
            }
            let profile: ProfileResponse = try await apiClient.request("GET", path: "/v1/user/profile")
            if let fn = profile.user.firstName { firstName = fn }
            if let ln = profile.user.lastName { lastName = ln }
            if let addr = profile.user.privyWalletAddress { walletAddress = addr }
            if let step = profile.user.onboardingStep, let resumeStep = OnboardingStep(rawValue: step) {
                currentStep = resumeStep
            }
        } catch {
            print("[Onboarding] profile fetch failed: \(error.localizedDescription)")
            await addBotMessage("Failed to connect to server: \(error.localizedDescription)")
        }

        await startCurrentStep()
    }

    func handleUserInput(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        addUserMessage(trimmed)

        // Name input is now handled via interactive nameForm, not text input
    }

    func handleInteraction(_ action: InteractionAction) async {
        switch action {
        case .nameSubmitted(let first, let last):
            await handleNameSubmitted(first, last)
        case .splitConfigChoice(let accepted):
            if accepted { await acceptSplitConfig() } else { await splitConfigSaved() }
        case .kycChoice(let complete):
            await handleKycChoice(complete)
        }
    }

    // MARK: - Step Starters

    private func startCurrentStep() async {
        switch currentStep {
        case .name:
            await startNameStep()
        case .fundWallet:
            await startFundWalletStep()
        case .splitConfig:
            await startSplitConfigStep()
        case .transaction:
            await startTransactionStep()
        case .kyc:
            await startKycStep()
        case .completed:
            break
        }
    }

    private func startNameStep() async {
        await addBotMessage("Hi! I'm Nola, your financial assistant. Let's get you set up.")
        await addBotMessage("What's your name?")
        inputMode = .name
    }

    private func startFundWalletStep() async {
        await checkBalance()
        if let balance = Double(walletBalance), balance > 0 {
            await addBotMessage("You already have $\(walletBalance) USDC in your wallet. You can add more or continue.")
        } else {
            await addBotMessage("Let's fund your wallet with USDC.")
        }
        inputMode = .disabled
    }

    private func startSplitConfigStep() async {
        await addBotMessage("By default, **$100** goes to your card for spending and the rest earns yield in your vault.")
        inputMode = .disabled
        // No interactive inline buttons — action bar at the bottom handles this
    }

    func acceptSplitConfig() async {
        addUserMessage("Sounds good")
        await addBotMessage("Great! Your funds will be split automatically.")
        await advanceFromSplitConfig()
    }

    func splitConfigSaved() async {
        struct SettingsResponse: Decodable {
            let cardTargetAmount: Int?
        }
        var amountText = "$100"
        if let response: SettingsResponse = try? await apiClient.request("GET", path: "/v1/settings") {
            let cents = response.cardTargetAmount ?? 10000
            amountText = CurrencyFormatter.format(Double(cents) / 100)
        }
        addUserMessage("Changed settings")
        await addBotMessage("Got it! \(amountText) will go to your card.")
        await advanceFromSplitConfig()
    }

    private func advanceFromSplitConfig() async {
        await updateOnboardingStep("transaction")
        currentStep = .transaction
        await startCurrentStep()
    }

    private func startTransactionStep() async {
        await addBotMessage("Setting up your vault and card...")
        inputMode = .disabled

        let steps = [
            TxStep(label: "Creating Rain account", status: .inProgress),
            TxStep(label: "Issuing virtual card", status: .pending),
            TxStep(label: "Creating vault", status: .pending),
            TxStep(label: "Allocating funds", status: .pending),
        ]
        withAnimation {
            messages.append(.interactive(.txProgress(steps: steps)))
        }

        await executeTxSteps()
    }

    private func startKycStep() async {
        await addBotMessage("One last thing — KYC verification unlocks higher limits and a physical card.")
        await addBotMessage("KYC coming soon. Explore your account for now!")
        inputMode = .disabled
    }

    func skipKyc() async {
        await handleKycChoice(false)
    }

    // MARK: - Input Handlers

    private func handleNameSubmitted(_ first: String, _ last: String) async {
        firstName = first
        lastName = last
        addUserMessage("\(first) \(last)")

        isProcessing = true
        do {
            struct ProfileBody: Encodable {
                let firstName: String
                let lastName: String
            }
            struct ProfileResponse: Decodable {
                let user: UserData
            }
            struct UserData: Decodable {
                let id: String
            }
            let _: ProfileResponse = try await apiClient.request("POST", path: "/v1/user/profile", body: ProfileBody(firstName: firstName, lastName: lastName))
            await addBotMessage("Nice to meet you, \(firstName)!")
            await updateOnboardingStep("fundWallet")
            isProcessing = false
            currentStep = .fundWallet
            await startCurrentStep()
        } catch {
            isProcessing = false
            print("[Onboarding] save name error: \(error.localizedDescription)")
            await addBotMessage("Something went wrong saving your name. Please try again.")
        }
    }


    private func handleKycChoice(_ complete: Bool) async {
        if complete {
            addUserMessage("Complete KYC")
            await addBotMessage("KYC verification coming soon! For now, let's explore your account.")
        } else {
            addUserMessage("Explore")
        }

        // Complete onboarding
        isProcessing = true
        do {
            struct Empty: Decodable {}
            let _: Empty = try await apiClient.request("POST", path: "/v1/user/complete-onboarding")
        } catch {
            // Continue anyway - the metadata update is best-effort
        }
        isProcessing = false
        await addBotMessage("Welcome to Nola! Let's go.")
        currentStep = .completed
    }

    // MARK: - Transaction Execution

    func retryTransaction() async {
        txFailed = false
        // Reset all steps to pending and restart
        let steps = [
            TxStep(label: "Creating Rain account", status: .inProgress),
            TxStep(label: "Issuing virtual card", status: .pending),
            TxStep(label: "Creating vault", status: .pending),
            TxStep(label: "Allocating funds", status: .pending),
        ]
        // Replace the last txProgress message
        if let msgIndex = messages.lastIndex(where: {
            if case .txProgress = $0.interactive { return true }
            return false
        }) {
            messages[msgIndex] = .interactive(.txProgress(steps: steps))
        }
        await executeTxSteps()
    }

    private func txStepFailed(_ step: String, error: Error) {
        txFailed = true
        print("[Onboarding] \(step) error: \(error.localizedDescription)")
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: step, key: "onboarding_step")
            scope.setLevel(.error)
        }
    }

    private func executeTxSteps() async {
        // Ensure wallet address is available (may be empty if resuming)
        if walletAddress.isEmpty {
            do {
                struct AddressResponse: Decodable {
                    let address: String
                }
                let response: AddressResponse = try await apiClient.request("GET", path: "/v1/wallet/address")
                walletAddress = response.address
            } catch {
                await addBotMessage("Failed to get wallet address: \(error.localizedDescription)")
                return
            }
        }

        // Step 1: Create Rain user + card
        struct CardSetupBody: Encodable {
            let firstName: String
            let lastName: String
            let email: String
            let walletAddress: String
        }
        struct CardSetupResponse: Decodable {
            let rainUserId: String
            let depositAddress: String?
        }

        let setup: CardSetupResponse
        do {
            setup = try await apiClient.request("POST", path: "/v1/card/setup", body: CardSetupBody(firstName: firstName, lastName: lastName, email: userEmail, walletAddress: walletAddress))
            updateTxStep(0, status: .completed)
            updateTxStep(1, status: .completed)
        } catch {
            updateTxStep(0, status: .failed)
            txStepFailed("card_setup", error: error)
            await addBotMessage("Something went wrong setting up your card. Tap Retry to try again.")
            return
        }

        // Step 2: Create vault
        updateTxStep(2, status: .inProgress)
        do {
            struct VaultBody: Encodable {
                let rainDepositAddress: String
            }
            struct VaultResponse: Decodable {
                let vaultAddress: String
                let txHash: String?
            }
            let _: VaultResponse = try await apiClient.request("POST", path: "/v1/wallet/create-vault", body: VaultBody(rainDepositAddress: setup.depositAddress ?? ""))
            updateTxStep(2, status: .completed)
        } catch {
            updateTxStep(2, status: .failed)
            txStepFailed("create_vault", error: error)
            await addBotMessage("Vault creation timed out. This is normal — tap Retry to continue.")
            return
        }

        // Step 3: Allocate funds (enqueues to allocation queue)
        updateTxStep(3, status: .inProgress)
        do {
            struct AllocateResponse: Decodable {
                let status: String
            }
            let _: AllocateResponse = try await apiClient.request("POST", path: "/v1/wallet/allocate")
            updateTxStep(3, status: .completed)
        } catch {
            updateTxStep(3, status: .failed)
            txStepFailed("allocate", error: error)
            await addBotMessage("Failed to allocate funds. Tap Retry to try again.")
            return
        }

        await addBotMessage("All set! Your funds are being allocated to your vault and card.")
        await updateOnboardingStep("kyc")
        currentStep = .kyc
        await startCurrentStep()
    }

    private func updateTxStep(_ index: Int, status: TxStepStatus) {
        // Find the tx progress message and update the step
        if let msgIndex = messages.lastIndex(where: {
            if case .txProgress = $0.interactive { return true }
            return false
        }) {
            if case .txProgress(var steps) = messages[msgIndex].interactive, index < steps.count {
                steps[index].status = status
                if status == .completed, index + 1 < steps.count {
                    steps[index + 1].status = .inProgress
                }
                messages[msgIndex] = .interactive(.txProgress(steps: steps))
            }
        }
    }

    // MARK: - Balance Polling

    func checkBalance() async {
        struct BalanceResponse: Decodable {
            let balance: String
            let balanceFormatted: String
        }
        do {
            let response: BalanceResponse = try await apiClient.request("GET", path: "/v1/wallet/balance")
            walletBalance = response.balanceFormatted
        } catch {
            print("[Onboarding] checkBalance error: \(error)")
        }
    }

    func advanceFromFunding() async {
        isPolling = false
        await updateOnboardingStep("splitConfig")
        currentStep = .splitConfig
        await startCurrentStep()
    }

    func pollForBalance() async {
        struct BalanceResponse: Decodable {
            let balance: String
            let balanceFormatted: String
        }

        isPolling = true
        pollingTimedOut = false
        let previousBalance = walletBalance

        for _ in 0..<120 {
            try? await Task.sleep(for: .seconds(5))

            do {
                let response: BalanceResponse = try await apiClient.request("GET", path: "/v1/wallet/balance")
                walletBalance = response.balanceFormatted

                if let balance = Double(response.balanceFormatted), balance > 0, response.balanceFormatted != previousBalance {
                    isPolling = false
                    await addBotMessage("Received \(response.balanceFormatted) USDC!")
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    return
                }
            } catch {
                // Continue polling
            }
        }

        isPolling = false
        pollingTimedOut = true
        await addBotMessage("Didn't detect a deposit yet. You can fund later from the home screen.")
    }

    // MARK: - Helpers

    private func addBotMessage(_ text: String) async {
        // Small typing delay for natural feel
        try? await Task.sleep(for: .milliseconds(Int.random(in: 300...800)))
        withAnimation {
            messages.append(.bot(text))
        }
    }

    private func addUserMessage(_ text: String) {
        withAnimation {
            messages.append(.user(text))
        }
    }

    private func updateOnboardingStep(_ step: String) async {
        struct StepBody: Encodable {
            let step: String
        }
        struct StepResponse: Decodable {
            let user: StepUser
        }
        struct StepUser: Decodable {
            let onboardingStep: String?
        }
        let _: StepResponse? = try? await apiClient.request("PATCH", path: "/v1/user/onboarding-step", body: StepBody(step: step))
    }
}

import SwiftUI
import PrivySDK

struct ChatOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gateState: AppGateState

    @StateObject private var viewModel: OnboardingViewModel

    init() {
        // Placeholder init — real tokenProvider set in .task
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(tokenProvider: { "" }))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                chatRow(for: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: viewModel.messages.count) {
                        withAnimation {
                            if let last = viewModel.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                if viewModel.txFailed {
                    Button {
                        Task { await viewModel.retryTransaction() }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                } else if viewModel.currentStep == .fundWallet {
                    FundingActionBar(
                        balance: viewModel.walletBalance,
                        isPolling: viewModel.isPolling,
                        showContinue: (Double(viewModel.walletBalance) ?? 0) > 0 || viewModel.pollingTimedOut,
                        onFundWallet: { showFundSheet = true },
                        onContinue: { Task { await viewModel.advanceFromFunding() } }
                    )
                } else if viewModel.currentStep == .splitConfig {
                    SplitConfigActionBar(
                        onAccept: { Task { await viewModel.acceptSplitConfig() } },
                        onChange: { showSplitConfigSheet = true }
                    )
                } else if viewModel.currentStep == .kyc {
                    KycActionBar(
                        onExplore: { Task { await viewModel.skipKyc() } }
                    )
                } else {
                    ChatInputBar(text: $inputText, inputMode: viewModel.inputMode, onSend: {
                        sendMessage()
                    }, onNameSubmit: { first, last in
                        Task { await viewModel.handleInteraction(.nameSubmitted(firstName: first, lastName: last)) }
                    })
                }
            }
            } // ZStack
            .navigationTitle(Text("Nola"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let email = userEmail {
                            Text(email)
                        }
                        Divider()
                        Button(role: .destructive) {
                            showLogoutConfirm = true
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Are you sure you want to log out?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task { await gateState.logout(appState: appState) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showFundSheet, onDismiss: {
            Task { await viewModel.pollForBalance() }
        }) {
            FundUSDCSheet()
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSplitConfigSheet) {
            NavigationStack {
                AutoTopUpSettingsView(onSaved: {
                    showSplitConfigSheet = false
                    Task { await viewModel.splitConfigSaved() }
                })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSplitConfigSheet = false }
                    }
                }
            }
            .environmentObject(appState)
        }
        .task {
            if let _ = await getAccessToken() {
                viewModel.apiClient.tokenProvider = { try await self.appState.privy.getUser()!.getAccessToken() }
                viewModel.userEmail = userEmail ?? ""
                await viewModel.startOnboarding()
            }
        }
        .onChange(of: viewModel.currentStep) {
            if viewModel.currentStep == .completed {
                gateState.onboardingCompleted = true
            }
        }
    }

    @State private var inputText = ""
    @State private var showLogoutConfirm = false
    @State private var showFundSheet = false
    @State private var showSplitConfigSheet = false

    @ViewBuilder
    private func chatRow(for message: ChatMessage) -> some View {
        if let interactive = message.interactive {
            interactiveRow(interactive)
        } else {
            ChatBubble(message: message)
        }
    }

    @ViewBuilder
    private func interactiveRow(_ content: InteractiveContent) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image("NolaMarkSmall")
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            interactiveContent(content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 300, alignment: .leading)
            Spacer()
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private func interactiveContent(_ content: InteractiveContent) -> some View {
        switch content {
        case .faceIdPrompt:
            EmptyView() // Face ID setup moved to SecuritySetupView
        case .fundWallet:
            EmptyView()
        case .splitConfig:
            EmptyView()
        case .qrCode(let address):
            QRCodeStepView(address: address)
        case .txProgress(let steps):
            TxProgressStepView(steps: steps)
        case .kycPrompt:
            EmptyView()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await viewModel.handleUserInput(text) }
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

    private func getAccessToken() async -> String? {
        switch appState.privy.authState {
        case .authenticated(let user):
            return try? await user.getAccessToken()
        default:
            return nil
        }
    }
}

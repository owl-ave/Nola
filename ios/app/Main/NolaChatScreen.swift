import Combine
import SwiftUI
import PrivySDK
import WebKit

/// Full-screen chat view. Hosted on MainTabView via .fullScreenCover — never recreated.
struct NolaChatScreen: View {
    @EnvironmentObject var appState: AppState
    @Environment(NavigationRouter.self) var router
    @EnvironmentObject var authManager: BiometricAuthManager

    @State private var showPinSheet = false
    @State private var showActionAuth = false
    @State private var formSchema: FormSchemaWrapper?
    @State private var externalURL: URL?
    @State private var feedbackMessageId: String?
    @State private var pendingAction: (action: String, params: [String: Any])?
    @State private var webViewRef: WKWebView?
    @State private var inputText: String = ""
    @State private var isWebViewReady = false
    @State private var isStreaming = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @Namespace private var glassNS
    @State private var recorder = AudioRecorderManager()
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    @AppStorage("chatSessionId") private var chatSessionId = ""

    private let chatBaseURL = AppConstants.chatBaseURL

    private var inputBarHeight: CGFloat {
        if recorder.isRecording { return 120 }
        return isInputFocused ? 138 : 68
    }

    private var totalBottomInset: CGFloat {
        inputBarHeight + keyboardHeight + 24
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            WebView(
                url: {
                    let stored = UserDefaults.standard.string(forKey: "chatSessionId") ?? ""
                    let sessionPath = stored.isEmpty ? "_resolving" : stored
                    return chatBaseURL.appendingPathComponent(sessionPath).appending(queryItems: [
                        URLQueryItem(name: "nativeInput", value: "true"),
                        URLQueryItem(name: "lang", value: UserDefaults.standard.string(forKey: "preferredLanguage") ?? "en"),
                    ])
                }(),
                persistentWebView: Binding(
                    get: { appState.chatWebView },
                    set: { appState.chatWebView = $0 }
                ),
                onPinRequested: {
                    Task {
                        if await authManager.authenticate() {
                            _ = try? await webViewRef?.evaluateJavaScript(
                                "window.postMessage(JSON.stringify({type:'PIN_VERIFIED'}), '*')"
                            )
                        } else {
                            showPinSheet = true
                        }
                    }
                },
                onExecuteAction: { action, params in
                    pendingAction = (action: action, params: params)
                    Task {
                        if await authManager.authenticate() {
                            guard let pending = pendingAction else { return }
                            pendingAction = nil
                            let privyUser = await appState.privy.getUser()
                            let userId = privyUser?.id ?? ""
                            let service = ProtectedActionService(apiClient: appState.apiClient, userId: userId)
                            let result = await service.execute(action: pending.action, params: pending.params)

                            let jsPayload: String
                            if result.success {
                                let resultData = try? JSONSerialization.data(withJSONObject: result.result ?? [:])
                                let resultStr = String(data: resultData ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                                jsPayload = "{type:'ACTION_RESULT',success:true,result:\(resultStr)}"
                            } else {
                                let escapedError = (result.error ?? "Unknown error").replacingOccurrences(of: "'", with: "\\'")
                                jsPayload = "{type:'ACTION_RESULT',success:false,error:'\(escapedError)'}"
                            }
                            await MainActor.run {
                                webViewRef?.evaluateJavaScript("window.postMessage(JSON.stringify(\(jsPayload)), '*')")
                            }
                        } else {
                            showActionAuth = true
                        }
                    }
                },
                onCollectUserInput: { schema in
                    formSchema = FormSchemaWrapper(schema: schema)
                },
                onNavigate: { urlString in
                    guard let url = URL(string: urlString) else { return }
                    if let deepLink = DeepLink.from(url: url) {
                        router.showChat = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            router.handleDeepLink(deepLink)
                        }
                    }
                },
                onExternalLink: { url in
                    externalURL = url
                },
                onSubmitFeedback: { messageId in
                    feedbackMessageId = messageId
                },
                onReady: {
                    isWebViewReady = true
                    updateBottomInset(totalBottomInset)
                },
                onStreamingStarted: { isStreaming = true },
                onStreamingFinished: { isStreaming = false },
                webViewRef: $webViewRef
            ) {
                guard let user = await appState.privy.getUser() else { return nil }
                return try? await user.getAccessToken()
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if recorder.isRecording {
                        RecordingInputBar(
                            recorder: recorder,
                            onSend: { text in sendChatMessage(text) },
                            onStop: { text in
                                inputText = text
                                isInputFocused = true
                            },
                            onCancel: {}
                        )
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.95).combined(with: .opacity)
                            )
                        )
                    } else {
                        chatInputBar
                            .transition(
                                .asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                )
                            )
                    }
                }
                .background(.clear)
                .animation(.spring(duration: 0.4, bounce: 0.15), value: recorder.isRecording)
            }
            .navigationTitle(Text("Nola AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { router.showChat = false } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            router.showSessionList = true
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        Button {
                            let newId = UUID().uuidString.lowercased()
                            chatSessionId = newId
                            navigateWebView(to: "/\(newId)")
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: router.showSessionList)
        .sheet(isPresented: $showPinSheet) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: {
                    showPinSheet = false
                    webViewRef?.evaluateJavaScript(
                        "window.postMessage(JSON.stringify({type:'PIN_CANCELLED'}), '*')"
                    )
                })) {
                    showPinSheet = false
                    webViewRef?.evaluateJavaScript(
                        "window.postMessage(JSON.stringify({type:'PIN_VERIFIED'}), '*')"
                    )
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showActionAuth) {
            NavigationStack {
                LockScreenView(mode: .pinOnly(onCancel: {
                    showActionAuth = false
                    pendingAction = nil
                    let js = "window.postMessage(JSON.stringify({type:'ACTION_CANCELLED'}), '*')"
                    webViewRef?.evaluateJavaScript(js)
                })) {
                    showActionAuth = false
                    guard let pending = pendingAction else { return }
                    pendingAction = nil
                    Task {
                        let privyUser = await appState.privy.getUser()
                        let userId = privyUser?.id ?? ""
                        let service = ProtectedActionService(apiClient: appState.apiClient, userId: userId)
                        let result = await service.execute(action: pending.action, params: pending.params)

                        let jsPayload: String
                        if result.success {
                            let resultData = try? JSONSerialization.data(withJSONObject: result.result ?? [:])
                            let resultStr = String(data: resultData ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                            jsPayload = "{type:'ACTION_RESULT',success:true,result:\(resultStr)}"
                        } else {
                            let escapedError = (result.error ?? "Unknown error").replacingOccurrences(of: "'", with: "\\'")
                            jsPayload = "{type:'ACTION_RESULT',success:false,error:'\(escapedError)'}"
                        }
                        await MainActor.run {
                            webViewRef?.evaluateJavaScript("window.postMessage(JSON.stringify(\(jsPayload)), '*')")
                        }
                    }
                }
            }
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $router.showSessionList) {
            ChatSessionListSheet(apiClient: appState.apiClient) { sessionId in
                router.showSessionList = false
                chatSessionId = sessionId
                navigateWebView(to: "/\(sessionId)")
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $formSchema) { wrapper in
            DynamicFormSheet(schema: wrapper.schema) { result in
                formSchema = nil
                let resultData = try? JSONSerialization.data(withJSONObject: result)
                let resultStr = String(data: resultData ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
                webViewRef?.evaluateJavaScript(
                    "window.postMessage(JSON.stringify({type:'USER_INPUT_RESULT',data:\(resultStr)}), '*')"
                )
            } onCancel: {
                formSchema = nil
                webViewRef?.evaluateJavaScript(
                    "window.postMessage(JSON.stringify({type:'USER_INPUT_CANCELLED'}), '*')"
                )
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: router.pendingChatPrompt) { _, prompt in
            guard let prompt else { return }
            router.pendingChatPrompt = nil
            if isWebViewReady {
                sendChatMessage(prompt)
            } else {
                if chatSessionId.isEmpty {
                    let newId = UUID().uuidString.lowercased()
                    chatSessionId = newId
                }
                navigateWebView(to: "/\(chatSessionId)")
                Task {
                    for _ in 0..<50 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if isWebViewReady { break }
                    }
                    sendChatMessage(prompt)
                }
            }
        }
        .onChange(of: router.pendingChatLink) { _, link in
            guard let link else { return }
            router.pendingChatLink = nil
            switch link {
            case .chat:
                router.showChat = true
            case .chatNew:
                router.showChat = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let newId = UUID().uuidString.lowercased()
                    chatSessionId = newId
                    navigateWebView(to: "/\(newId)")
                }
            default:
                break
            }
        }
        .sheet(item: Binding(
            get: { externalURL.map { ExternalURLWrapper(url: $0) } },
            set: { externalURL = $0?.url }
        )) { wrapper in
            SafariView(url: wrapper.url)
        }
        .sheet(isPresented: Binding(
            get: { feedbackMessageId != nil },
            set: { if !$0 { feedbackMessageId = nil } }
        )) {
            if let messageId = feedbackMessageId {
                let sessionId = webViewRef?.url?.pathComponents.last ?? ""
                AIFeedbackSheet(
                    messageId: messageId,
                    sessionId: sessionId,
                    apiClient: appState.apiClient,
                    onSubmitted: {
                        feedbackMessageId = nil
                        let js = "window.postMessage(JSON.stringify({type:'FEEDBACK_SUBMITTED',messageId:'\(messageId)'}), '*')"
                        webViewRef?.evaluateJavaScript(js)
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .task {
            if chatSessionId.isEmpty {
                let id = await resolveSessionId()
                navigateWebView(to: "/\(id)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
                updateBottomInset(totalBottomInset)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
            updateBottomInset(totalBottomInset)
        }
        .alert("Recording Error", isPresented: Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.dismissError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recorder.errorMessage ?? "")
        }
        .accessibilityIdentifier("NolaChatScreen")
    }

    // MARK: - Chat Input Bar

    private var chatInputBar: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if !isInputFocused {
                        plusButton
                            .transition(.scale.combined(with: .opacity))
                    }

                    TextField("Message", text: $inputText, axis: .vertical)
                        .lineLimit(isInputFocused ? 2...8 : 1...1)
                        .focused($isInputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onTapGesture { isInputFocused = true }
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onSubmit { sendInputMessage() }

                    if !isInputFocused {
                        recordButton
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                if isInputFocused {
                    HStack {
                        HStack(spacing: 0) {
                            groupedActionButton(icon: "plus")
                            groupedActionButton(icon: "camera")
                            groupedActionButton(icon: "photo")
                            groupedActionButton(icon: "location")
                        }

                        Spacer()

                        if hasInput {
                            Button(action: sendInputMessage) {
                                Image(systemName: "arrow.up")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(12)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            recordButton
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .onChange(of: isInputFocused) {
            updateBottomInset(totalBottomInset)
        }
        .animation(.spring(duration: 0.3), value: isInputFocused)
        .animation(.easeInOut(duration: 0.15), value: hasInput)
    }

    // MARK: - Input Helpers

    private func actionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(12)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
    }

    private var plusButton: some View {
        actionButton(icon: "plus", action: {})
    }

    private var recordButton: some View {
        actionButton(icon: "waveform", action: { recorder.startRecording() })
    }

    private func groupedActionButton(icon: String) -> some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.body)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .glassEffectUnion(id: "actions", namespace: glassNS)
    }

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Message Sending

    private func sendInputMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isWebViewReady else { return }
        inputText = ""
        isInputFocused = false
        sendChatMessage(text)
    }

    private func sendChatMessage(_ text: String) {
        guard isWebViewReady else { return }
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = "window.__nolaChatApi?.sendMessage('\(escaped)')"
        Task { @MainActor in
            _ = try? await webViewRef?.evaluateJavaScript(js)
        }
    }

    private func updateBottomInset(_ height: CGFloat) {
        guard let webView = webViewRef, isWebViewReady else { return }
        let payload: [String: Any] = ["type": "SET_BOTTOM_INSET", "height": height]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.postMessage(\(json), '*')"
        Task { @MainActor in
            _ = try? await webView.evaluateJavaScript(js)
        }
    }

    private func resolveSessionId() async -> String {
        // 1. Use stored session ID if available
        if !chatSessionId.isEmpty {
            return chatSessionId
        }

        // 2. Try API to find latest session
        struct LatestSessionResponse: Decodable { let sessionId: String? }
        if let response: LatestSessionResponse = try? await appState.apiClient.request("GET", path: "/v1/ai/chat/latest-session") {
            if let id = response.sessionId {
                chatSessionId = id
                return id
            }
        }

        // 3. Generate new UUID
        let newId = UUID().uuidString.lowercased()
        chatSessionId = newId
        return newId
    }

    private func navigateWebView(to path: String) {
        var components = URLComponents(url: chatBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "nativeInput", value: "true"))
        queryItems.append(URLQueryItem(name: "lang", value: preferredLanguage))
        components.queryItems = queryItems
        if let url = components.url {
            webViewRef?.load(URLRequest(url: url))
        }
    }
}

// MARK: - Helpers

private struct ExternalURLWrapper: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FormSchemaWrapper: Identifiable {
    let id = UUID()
    let schema: [String: Any]
}

// MARK: - Chat Session List

private struct ChatSession: Decodable, Identifiable {
    let id: String
    let userId: String
    let title: String?
    let createdAt: String
    let updatedAt: String
}

struct ChatSessionListSheet: View {
    let apiClient: APIClient
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ChatSession] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var editingSession: ChatSession?
    @State private var editTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(0..<4, id: \.self) { _ in
                                SessionSkeletonRow()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .shimmer()
                } else if let error = loadError {
                    ContentUnavailableView {
                        Label("Failed to Load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await loadSessions() } }
                            .buttonStyle(.bordered)
                    }
                } else if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a new conversation to see it here.")
                    }
                } else {
                    List {
                        ForEach(sessions) { session in
                            Button { onSelect(session.id) } label: {
                                SessionRow(session: session)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteSession(session.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    editTitle = session.title ?? ""
                                    editingSession = session
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .listRowSeparatorTint(Color(.separator).opacity(0.3))
                    .environment(\.defaultMinListRowHeight, 44)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(Text("Conversations"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Rename Conversation", isPresented: Binding(
                get: { editingSession != nil },
                set: { if !$0 { editingSession = nil } }
            )) {
                TextField("Title", text: $editTitle)
                Button("Save") {
                    if let session = editingSession {
                        Task { await renameSession(session.id, title: editTitle) }
                    }
                    editingSession = nil
                }
                Button("Cancel", role: .cancel) { editingSession = nil }
            }
        }
        .task { await loadSessions() }
    }

    private func loadSessions() async {
        isLoading = true
        loadError = nil
        do {
            struct Response: Decodable { let sessions: [ChatSession] }
            let response: Response = try await apiClient.request("GET", path: "/v1/ai/chat/sessions")
            sessions = response.sessions
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteSession(_ id: String) async {
        struct Response: Decodable { let success: Bool }
        do {
            _ = try await apiClient.request("DELETE", path: "/v1/ai/chat/sessions/\(id)") as Response
            sessions.removeAll { $0.id == id }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func renameSession(_ id: String, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        struct Body: Encodable { let title: String }
        struct Response: Decodable { let success: Bool }
        do {
            _ = try await apiClient.request("PATCH", path: "/v1/ai/chat/sessions/\(id)", body: Body(title: trimmed)) as Response
            if let idx = sessions.firstIndex(where: { $0.id == id }) {
                sessions[idx] = ChatSession(id: sessions[idx].id, userId: sessions[idx].userId, title: trimmed, createdAt: sessions[idx].createdAt, updatedAt: sessions[idx].updatedAt)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: ChatSession

    var body: some View {
        HStack {
            Text(session.title ?? "Untitled")
                .font(.subheadline)
                .foregroundStyle(session.title != nil ? .primary : .secondary)
                .lineLimit(1)
            Spacer()
            Text(formatDate(session.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .contentShape(Rectangle())
    }

    private func formatDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: iso)
        }() else { return iso }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let df = DateFormatter()
            df.timeStyle = .short
            return df.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let df = DateFormatter()
            df.dateStyle = .short
            return df.string(from: date)
        }
    }
}

// MARK: - Skeleton

private struct SessionSkeletonRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: CGFloat.random(in: 140...220), height: 14)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray6))
                .frame(width: 50, height: 10)
        }
        .padding(.vertical, 10)
    }
}

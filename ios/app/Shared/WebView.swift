import LocalAuthentication
import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    var persistentWebView: Binding<WKWebView?>?
    var onPinRequested: (() -> Void)?
    var onExecuteAction: ((String, [String: Any]) -> Void)?
    var onCollectUserInput: (([String: Any]) -> Void)?
    var onNavigate: ((String) -> Void)?
    var onExternalLink: ((URL) -> Void)?
    var onSubmitFeedback: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onStreamingStarted: (() -> Void)?
    var onStreamingFinished: (() -> Void)?
    var onSessionId: ((String) -> Void)?
    @Binding var webViewRef: WKWebView?
    let getAccessToken: () async -> String?

    func makeCoordinator() -> Coordinator {
        Coordinator(getAccessToken: getAccessToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        // Reuse persistent WebView if available
        if let existing = persistentWebView?.wrappedValue {
            existing.configuration.userContentController.removeAllScriptMessageHandlers()
            existing.configuration.userContentController.add(context.coordinator, name: "nola")
            existing.navigationDelegate = context.coordinator
            context.coordinator.webView = existing
            context.coordinator.originHost = url.host()
            wireCallbacks(context.coordinator)
            if existing.url != url {
                existing.load(URLRequest(url: url))
            }
            DispatchQueue.main.async { self.webViewRef = existing }
            return existing
        }

        // First time — create new WebView
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "nola")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.originHost = url.host()
        wireCallbacks(context.coordinator)
        DispatchQueue.main.async {
            self.webViewRef = webView
            self.persistentWebView?.wrappedValue = webView
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        wireCallbacks(context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Don't remove the message handler — WebView may be reused
    }

    private func wireCallbacks(_ coordinator: Coordinator) {
        coordinator.onPinRequested = onPinRequested
        coordinator.onExecuteAction = onExecuteAction
        coordinator.onCollectUserInput = onCollectUserInput
        coordinator.onNavigate = onNavigate
        coordinator.onExternalLink = onExternalLink
        coordinator.onSubmitFeedback = onSubmitFeedback
        coordinator.onReady = onReady
        coordinator.onStreamingStarted = onStreamingStarted
        coordinator.onStreamingFinished = onStreamingFinished
        coordinator.onSessionId = onSessionId
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        let getAccessToken: () async -> String?
        var originHost: String?
        var onPinRequested: (() -> Void)?
        var onExecuteAction: ((String, [String: Any]) -> Void)?
        var onCollectUserInput: (([String: Any]) -> Void)?
        var onNavigate: ((String) -> Void)?
        var onExternalLink: ((URL) -> Void)?
        var onSubmitFeedback: ((String) -> Void)?
        var onReady: (() -> Void)?
        var onStreamingStarted: (() -> Void)?
        var onStreamingFinished: (() -> Void)?
        var onSessionId: ((String) -> Void)?

        init(getAccessToken: @escaping () async -> String?) {
            self.getAccessToken = getAccessToken
        }

        // MARK: - Link Interception

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "nola" {
                decisionHandler(.cancel)
                onNavigate?(url.absoluteString)
                return
            }

            if url.host() == originHost {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                onExternalLink?(url)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - Script Message Handler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "nola",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "AUTH_TOKEN_REQUEST":
                Task { @MainActor in
                    guard let token = await getAccessToken() else { return }
                    let js = "window.postMessage(JSON.stringify({type:'AUTH_TOKEN',token:'\(token)'}), '*')"
                    _ = try? await webView?.evaluateJavaScript(js)
                }

            case "PIN_VERIFY_REQUEST":
                Task { @MainActor in
                    onPinRequested?()
                }

            case "EXECUTE_ACTION":
                guard let action = body["action"] as? String,
                      let params = body["params"] as? [String: Any] else { return }
                Task { @MainActor in
                    self.onExecuteAction?(action, params)
                }

            case "COLLECT_USER_INPUT":
                guard let schema = body["schema"] as? [String: Any] else { return }
                Task { @MainActor in
                    self.onCollectUserInput?(schema)
                }

            case "BIOMETRIC_TYPE_REQUEST":
                let context = LAContext()
                var error: NSError?
                let biometricValue: String
                if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                    switch context.biometryType {
                    case .faceID: biometricValue = "faceid"
                    case .touchID: biometricValue = "touchid"
                    default: biometricValue = "pin"
                    }
                } else {
                    biometricValue = "pin"
                }
                let js = "window.postMessage(JSON.stringify({type:'BIOMETRIC_TYPE',value:'\(biometricValue)'}), '*')"
                Task { @MainActor in
                    _ = try? await self.webView?.evaluateJavaScript(js)
                }

            case "NAVIGATE":
                guard let urlString = body["url"] as? String else { return }
                Task { @MainActor in
                    self.onNavigate?(urlString)
                }

            case "SUBMIT_FEEDBACK":
                guard let messageId = body["messageId"] as? String else { return }
                Task { @MainActor in
                    self.onSubmitFeedback?(messageId)
                }

            case "READY":
                Task { @MainActor in self.onReady?() }

            case "STREAMING_STARTED":
                Task { @MainActor in self.onStreamingStarted?() }

            case "STREAMING_FINISHED":
                Task { @MainActor in self.onStreamingFinished?() }

            case "SESSION_ID":
                guard let sessionId = body["sessionId"] as? String else { return }
                Task { @MainActor in self.onSessionId?(sessionId) }

            default:
                break
            }
        }
    }
}

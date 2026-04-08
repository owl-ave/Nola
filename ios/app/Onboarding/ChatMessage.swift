import Foundation

enum MessageSender {
    case bot, user
}

enum InputMode {
    case text, numeric, name, disabled
}

enum InteractiveContent {
    case faceIdPrompt
    case fundWallet
    case splitConfig(defaultAmount: String)
    case qrCode(address: String)
    case txProgress(steps: [TxStep])
    case kycPrompt
}

struct TxStep: Identifiable {
    let id = UUID()
    let label: String
    var status: TxStepStatus
}

enum TxStepStatus {
    case pending, inProgress, completed, failed
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: MessageSender
    let text: String?
    let interactive: InteractiveContent?
    let timestamp = Date()

    static func bot(_ text: String) -> ChatMessage {
        ChatMessage(sender: .bot, text: text, interactive: nil)
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(sender: .user, text: text, interactive: nil)
    }

    static func interactive(_ content: InteractiveContent) -> ChatMessage {
        ChatMessage(sender: .bot, text: nil, interactive: content)
    }
}

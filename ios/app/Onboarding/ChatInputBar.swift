import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let inputMode: InputMode
    let onSend: () -> Void
    var onNameSubmit: ((String, String) -> Void)?

    @State private var firstName = ""
    @State private var lastName = ""
    @FocusState private var nameFocus: NameField?

    private enum NameField {
        case first, last
    }

    var body: some View {
        Group {
            if inputMode == .name {
                nameInputBar
            } else {
                textInputBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Standard Text Input

    private var textInputBar: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { if canSendText { onSend() } }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .disabled(inputMode == .disabled)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSendText ? Color.accentColor : Color.accentColor.opacity(0.25))
            }
            .disabled(!canSendText)
        }
    }

    // MARK: - Name Input (First + Last + Send)

    private var nameInputBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .focused($nameFocus, equals: .first)
                    .submitLabel(.next)
                    .onSubmit { nameFocus = .last }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .focused($nameFocus, equals: .last)
                    .submitLabel(.send)
                    .onSubmit { submitName() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button(action: submitName) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSendName ? Color.accentColor : Color.accentColor.opacity(0.25))
                }
                .disabled(!canSendName)
            }
        }
        .onAppear { nameFocus = .first }
    }

    // MARK: - Helpers

    private var canSendText: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && inputMode != .disabled
    }

    private var canSendName: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitName() {
        guard canSendName else { return }
        nameFocus = nil
        onNameSubmit?(
            firstName.trimmingCharacters(in: .whitespaces),
            lastName.trimmingCharacters(in: .whitespaces)
        )
    }

    private var placeholder: String {
        inputMode == .disabled ? "Waiting..." : "Type a message"
    }

    private var keyboardType: UIKeyboardType {
        inputMode == .numeric ? .numberPad : .default
    }
}

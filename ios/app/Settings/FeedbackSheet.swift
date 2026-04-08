import PrivySDK
import Sentry
import SwiftUI

// MARK: - Feedback Sheet

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false

    var userName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Message input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What happened?")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
                            )
                            .overlay(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("Describe the bug or issue...")
                                        .font(.body)
                                        .foregroundStyle(Color(.placeholderText))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 20)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .padding(.bottom, 24)

                    // Submit button
                    Button(action: { Task { await submitFeedback() } }) {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Submit Report", systemImage: "paperplane.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Color.accentColor : Color.accentColor.opacity(0.3))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(Text("Report a Bug"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Thank you!")
                .font(.headline)
            Text("Your feedback has been submitted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submitFeedback() async {
        isSubmitting = true

        var userEmail: String?
        if let user = await appState.privy.getUser() {
            for account in user.linkedAccounts {
                if case .email(let emailAccount) = account {
                    userEmail = emailAccount.email
                    break
                }
            }
        }

        let feedback = SentryFeedback(
            message: message.trimmingCharacters(in: .whitespaces),
            name: userName,
            email: userEmail,
            source: .custom,
            associatedEventId: nil,
            attachments: nil
        )
        SentrySDK.capture(feedback: feedback)

        isSubmitting = false

        withAnimation(.easeInOut(duration: 0.25)) {
            showSuccess = true
        }

        try? await Task.sleep(for: .seconds(1.5))
        dismiss()
    }
}

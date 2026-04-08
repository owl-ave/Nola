import SwiftUI

struct AIFeedbackSheet: View {
    let messageId: String
    let sessionId: String
    let apiClient: APIClient
    let onSubmitted: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: String?
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private let categories = [
        ("wrong_answer", "Wrong answer"),
        ("wrong_tool", "Wrong tool"),
        ("confusing", "Confusing"),
        ("offensive", "Offensive"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    ForEach(categories, id: \.0) { value, label in
                        Button {
                            selectedCategory = value
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedCategory == value {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                if selectedCategory != nil {
                    Section("Details (optional)") {
                        TextField("Add details...", text: $comment, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(Text("Report Issue"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task { await submit() }
                        }
                        .fontWeight(.semibold)
                        .disabled(selectedCategory == nil)
                    }
                }
            }
        }
    }

    private func submit() async {
        guard let category = selectedCategory else { return }
        isSubmitting = true
        error = nil

        struct Body: Encodable {
            let messageId: String
            let sessionId: String
            let category: String
            let comment: String?
        }
        struct Response: Decodable { let id: String }

        do {
            let _: Response = try await apiClient.request(
                "POST",
                path: "/v1/ai/feedback",
                body: Body(
                    messageId: messageId,
                    sessionId: sessionId,
                    category: category,
                    comment: comment.isEmpty ? nil : comment
                )
            )
            onSubmitted()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

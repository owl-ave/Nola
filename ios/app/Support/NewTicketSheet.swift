import SwiftUI

struct NewTicketSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var subject = ""
    @State private var description = ""
    @State private var priority = 2
    @State private var isSubmitting = false
    @State private var error: String?

    private var supportService: SupportService { SupportService(client: appState.apiClient) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Subject
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subject")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        TextField("Subject", text: $subject)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        TextEditor(text: $description)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        Picker("Priority", selection: $priority) {
                            Text("Low").tag(1)
                            Text("Medium").tag(2)
                            Text("High").tag(3)
                            Text("Urgent").tag(4)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Error
                    if let error {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button { self.error = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text("New Ticket"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button { Task { await submit() } } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .fontWeight(.semibold)
                        .disabled(subject.isEmpty || description.isEmpty)
                    }
                }
            }
        }
        .sensoryFeedback(.error, trigger: error)
    }

    private func submit() async {
        isSubmitting = true; error = nil
        do {
            _ = try await supportService.createTicket(subject: subject, description: description, priority: priority)
            onCreated()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

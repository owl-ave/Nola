import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var firstName: String
    @State var lastName: String
    @State private var isSaving = false
    @State private var errorAlert: String?
    @State private var savedFirstName: String
    @State private var savedLastName: String
    @FocusState private var focusedField: Field?

    private enum Field { case firstName, lastName }

    init(firstName: String, lastName: String) {
        _firstName = State(initialValue: firstName)
        _lastName = State(initialValue: lastName)
        _savedFirstName = State(initialValue: firstName)
        _savedLastName = State(initialValue: lastName)
    }

    private var hasChanges: Bool {
        firstName != savedFirstName || lastName != savedLastName
    }

    private var canSave: Bool {
        hasChanges
            && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("First Name", text: $firstName)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .firstName)
                TextField("Last Name", text: $lastName)
                    .textContentType(.familyName)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .lastName)
            }
        }
        .navigationTitle(Text("Edit Profile"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        focusedField = nil
                        Task { await saveProfile() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { errorAlert != nil }, set: { if !$0 { errorAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlert ?? "")
        }
        .sensoryFeedback(.error, trigger: errorAlert)
    }

    // MARK: - API

    private struct ProfileResponse: Decodable {
        let user: ProfileData
    }

    private struct ProfileData: Decodable {
        let firstName: String?
        let lastName: String?
    }

    private struct UpdateBody: Encodable {
        let firstName: String
        let lastName: String
    }

    private func saveProfile() async {
        isSaving = true
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        do {
            let _: ProfileResponse = try await appState.apiClient.request(
                "POST",
                path: "/v1/user/profile",
                body: UpdateBody(firstName: trimmedFirst, lastName: trimmedLast)
            )
            dismiss()
        } catch {
            errorAlert = "Failed to save profile."
        }
        isSaving = false
    }
}

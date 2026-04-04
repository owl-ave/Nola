import SwiftUI

struct FormStepView: View {
    let step: FormStepModel
    @Binding var values: [String: String]
    let showValidation: Bool

    var body: some View {
        Form {
            Section(step.title) {
                ForEach(step.fields) { field in
                    DynamicFormField(
                        field: field,
                        value: Binding(
                            get: { values[field.name] ?? field.defaultValue },
                            set: { values[field.name] = $0 }
                        ),
                        showError: showValidation
                    )
                }
            }
        }
    }
}

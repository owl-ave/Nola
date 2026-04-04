import SwiftUI

struct DynamicFormSheet: View {
    let schema: [String: Any]
    let onSubmit: ([String: Any]) -> Void
    let onCancel: () -> Void

    private let formTitle: String
    private let formDescription: String?
    private let steps: [FormStepModel]

    @State private var currentStep: Int = 0
    @State private var values: [String: String]
    @State private var showValidation: Bool = false
    @State private var showSummary: Bool = false

    init(schema: [String: Any], onSubmit: @escaping ([String: Any]) -> Void, onCancel: @escaping () -> Void) {
        self.schema = schema
        self.onSubmit = onSubmit
        self.onCancel = onCancel

        let parsed = FormFieldModel.parseSchema(schema)
        // Use top-level title, or fall back to first step title
        self.formTitle = parsed.title.isEmpty ? (parsed.steps.first?.title ?? "Form") : parsed.title
        self.formDescription = parsed.description
        self.steps = parsed.steps

        // Initialize values with defaultValue for every field
        var initialValues: [String: String] = [:]
        for step in parsed.steps {
            for field in step.fields {
                initialValues[field.name] = field.defaultValue
            }
        }
        _values = State(initialValue: initialValues)
    }

    var body: some View {
        NavigationStack {
            Group {
                if steps.isEmpty {
                    ContentUnavailableView {
                        Label("Invalid Form", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("No form fields received.")
                    }
                } else if steps.count == 1 {
                    singleStepBody
                } else {
                    wizardBody
                }
            }
            .navigationTitle(formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                }
                if steps.count == 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            submitIfValid(step: steps[0])
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Single Step

    private var singleStepBody: some View {
        FormStepView(
            step: steps[0],
            values: $values,
            showValidation: showValidation
        )
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Wizard

    private var wizardBody: some View {
        VStack(spacing: 0) {
            if showSummary {
                FormSummaryView(steps: steps, values: values)
            } else {
                FormStepView(
                    step: steps[currentStep],
                    values: $values,
                    showValidation: showValidation
                )
            }

            Divider()

            wizardNavBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
    }

    private var wizardNavBar: some View {
        HStack(spacing: 12) {
            if showSummary || currentStep > 0 {
                Button {
                    withAnimation {
                        if showSummary {
                            showSummary = false
                            showValidation = false
                        } else {
                            currentStep -= 1
                            showValidation = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.medium))
                        Text("Back")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if showSummary {
                Button {
                    submitAll()
                } label: {
                    Text("Submit")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    advanceOrSubmit()
                } label: {
                    HStack(spacing: 6) {
                        Text(currentStep == steps.count - 1 ? "Review" : "Next")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Step Navigation

    private var stepIndicator: some View {
        Text("Step \(currentStep + 1) of \(steps.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func advanceOrSubmit() {
        let step = steps[currentStep]
        guard validateStep(step) else {
            withAnimation { showValidation = true }
            return
        }
        showValidation = false
        withAnimation {
            if currentStep < steps.count - 1 {
                currentStep += 1
            } else {
                showSummary = true
            }
        }
    }

    private func submitIfValid(step: FormStepModel) {
        guard validateStep(step) else {
            withAnimation { showValidation = true }
            return
        }
        submitAll()
    }

    private func submitAll() {
        var result: [String: Any] = [:]
        for (key, stringValue) in values {
            // Find the field type for type conversion
            let fieldType = fieldType(for: key)
            switch fieldType {
            case "toggle":
                result[key] = stringValue == "true"
            case "number":
                if let intValue = Int(stringValue) {
                    result[key] = intValue
                } else if let doubleValue = Double(stringValue) {
                    result[key] = doubleValue
                } else {
                    result[key] = stringValue
                }
            default:
                result[key] = stringValue
            }
        }
        onSubmit(result)
    }

    // MARK: - Validation

    private func validateStep(_ step: FormStepModel) -> Bool {
        for field in step.fields {
            if field.required {
                let val = values[field.name] ?? ""
                if val.isEmpty { return false }
            }
        }
        return true
    }

    // MARK: - Helpers

    private func fieldType(for name: String) -> String {
        for step in steps {
            if let field = step.fields.first(where: { $0.name == name }) {
                return field.type
            }
        }
        return "text"
    }
}

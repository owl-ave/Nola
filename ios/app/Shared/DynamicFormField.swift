import SwiftUI

// MARK: - Models

struct FormFieldModel: Identifiable {
    let id = UUID()
    let name: String
    let label: String
    let type: String
    let required: Bool
    let placeholder: String?
    let maxLength: Int?
    let options: [(label: String, value: String)]
    let defaultValue: String
}

struct FormStepModel: Identifiable {
    let id = UUID()
    let title: String
    let fields: [FormFieldModel]
}

// MARK: - Schema Parsing

extension FormFieldModel {
    static func parseSchema(_ schema: [String: Any]) -> (title: String, description: String?, steps: [FormStepModel]) {
        print("[FormParser] Schema keys: \(schema.keys.sorted())")
        let title = schema["title"] as? String ?? ""
        let description = schema["description"] as? String

        let rawSteps = schema["steps"] as? [[String: Any]] ?? []
        print("[FormParser] Title: '\(title)', rawSteps count: \(rawSteps.count)")
        let steps: [FormStepModel] = rawSteps.map { rawStep in
            let stepTitle = rawStep["title"] as? String ?? ""
            let rawFields = rawStep["fields"] as? [[String: Any]] ?? []
            let fields: [FormFieldModel] = rawFields.map { rawField in
                let name = rawField["name"] as? String ?? ""
                let label = rawField["label"] as? String ?? ""
                let type = rawField["type"] as? String ?? "text"
                let required = rawField["required"] as? Bool ?? false
                let placeholder = rawField["placeholder"] as? String
                let maxLength = rawField["maxLength"] as? Int
                let defaultValue = rawField["defaultValue"] as? String ?? ""

                let rawOptions = rawField["options"] as? [[String: Any]] ?? []
                let options: [(label: String, value: String)] = rawOptions.compactMap { opt in
                    guard let label = opt["label"] as? String,
                          let value = opt["value"] as? String else { return nil }
                    return (label: label, value: value)
                }

                return FormFieldModel(
                    name: name,
                    label: label,
                    type: type,
                    required: required,
                    placeholder: placeholder,
                    maxLength: maxLength,
                    options: options,
                    defaultValue: defaultValue
                )
            }
            print("[FormParser] Step '\(stepTitle)' has \(fields.count) fields: \(fields.map { $0.name })")
            return FormStepModel(title: stepTitle, fields: fields)
        }

        print("[FormParser] Parsed \(steps.count) steps total")
        return (title: title, description: description, steps: steps)
    }
}

// MARK: - DynamicFormField View

struct DynamicFormField: View {
    let field: FormFieldModel
    @Binding var value: String
    let showError: Bool

    @State private var selectedDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldControl
            if showError && field.required && value.isEmpty {
                Text("Required")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var fieldLabel: String {
        field.required ? field.label : "\(field.label) (optional)"
    }

    private var promptText: String {
        field.placeholder ?? "Enter \(field.label.lowercased())"
    }

    @ViewBuilder
    private var fieldControl: some View {
        switch field.type {
        case "text":
            LabeledContent(fieldLabel) {
                TextField(promptText, text: limitedBinding)
                    .multilineTextAlignment(.trailing)
            }

        case "textarea":
            VStack(alignment: .leading, spacing: 6) {
                Text(fieldLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $value)
                    .frame(minHeight: 80)
                    .onChange(of: value) { _, newValue in
                        if let maxLength = field.maxLength, newValue.count > maxLength {
                            value = String(newValue.prefix(maxLength))
                        }
                    }
            }

        case "number":
            LabeledContent(fieldLabel) {
                TextField(promptText, text: $value)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

        case "email":
            LabeledContent(fieldLabel) {
                TextField(promptText, text: $value)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .multilineTextAlignment(.trailing)
            }

        case "phone":
            LabeledContent(fieldLabel) {
                TextField(promptText, text: $value)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
            }

        case "select":
            Picker(fieldLabel, selection: $value) {
                if !field.required {
                    Text("Select...").tag("")
                } else {
                    Text("Select...").tag("").disabled(true)
                }
                ForEach(field.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)

        case "toggle":
            Toggle(fieldLabel, isOn: Binding(
                get: { value == "true" },
                set: { value = $0 ? "true" : "false" }
            ))

        case "date":
            DatePicker(
                fieldLabel,
                selection: Binding(
                    get: {
                        if let interval = Double(value) {
                            return Date(timeIntervalSince1970: interval)
                        }
                        return selectedDate
                    },
                    set: { newDate in
                        selectedDate = newDate
                        value = String(newDate.timeIntervalSince1970)
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)

        default:
            LabeledContent(fieldLabel) {
                TextField(promptText, text: limitedBinding)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var limitedBinding: Binding<String> {
        Binding(
            get: { value },
            set: { newValue in
                if let maxLength = field.maxLength, newValue.count > maxLength {
                    value = String(newValue.prefix(maxLength))
                } else {
                    value = newValue
                }
            }
        )
    }
}

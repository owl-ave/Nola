import SwiftUI

struct FormSummaryView: View {
    let steps: [FormStepModel]
    let values: [String: String]

    var body: some View {
        Form {
            ForEach(steps) { step in
                Section(step.title) {
                    ForEach(step.fields) { field in
                        HStack {
                            Text(field.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(displayValue(for: field))
                                .font(.subheadline)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    private func displayValue(for field: FormFieldModel) -> String {
        let raw = values[field.name] ?? field.defaultValue

        switch field.type {
        case "select":
            return field.options.first(where: { $0.value == raw })?.label ?? raw

        case "toggle":
            return raw == "true" ? "Yes" : "No"

        case "date":
            if let interval = Double(raw) {
                let date = Date(timeIntervalSince1970: interval)
                return date.formatted(date: .long, time: .omitted)
            }
            return raw

        default:
            return raw.isEmpty ? "—" : raw
        }
    }
}

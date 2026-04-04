import SwiftUI

struct TxProgressStepView: View {
    let steps: [TxStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    stepIndicator(step.status)
                    Text(step.label)
                        .font(.body)
                        .foregroundStyle(step.status == .failed ? .red : .primary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func stepIndicator(_ status: TxStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

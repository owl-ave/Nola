import SwiftUI

struct TransactionFilterSheet: View {
    @Binding var filter: ActivityFilter
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ActivityFilter = .init()
    @State private var showDatePicker = false

    private let typeOptions: [(label: String, value: String)] = [
        ("Card", "card_spend,card_refund,card_payment"),
        ("Vault", "deposit,withdraw"),
        ("In", "transfer_in,deposit_rain"),
        ("Out", "card_spend,send,topup,auto_topup,fee"),
    ]

    /// Maps type value to segment index (0 = All)
    private var selectedTypeIndex: Int {
        guard let types = draft.types else { return 0 }
        return (typeOptions.firstIndex(where: { $0.value == types }) ?? -1) + 1
    }

    private let datePresets: [(label: String, range: () -> (Date, Date))] = [
        ("Today", { (Calendar.current.startOfDay(for: Date()), Date()) }),
        ("Yesterday", {
            let cal = Calendar.current
            let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
            return (cal.startOfDay(for: yesterday), cal.startOfDay(for: Date()))
        }),
        ("This Week", {
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            return (start, Date())
        }),
        ("This Month", {
            let cal = Calendar.current
            let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            return (start, Date())
        }),
        ("Last 30 Days", {
            let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            return (start, Date())
        }),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Type
                    Picker("Type", selection: Binding(
                        get: { selectedTypeIndex },
                        set: { newIndex in
                            draft.types = newIndex == 0 ? nil : typeOptions[newIndex - 1].value
                        }
                    )) {
                        Text("All").tag(0)
                        ForEach(Array(typeOptions.enumerated()), id: \.offset) { index, option in
                            Text(option.label).tag(index + 1)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Date range
                    Menu {
                        Button("Any Time") {
                            draft.startDate = nil
                            draft.endDate = nil
                        }
                        ForEach(datePresets, id: \.label) { preset in
                            Button(preset.label) {
                                let (start, end) = preset.range()
                                draft.startDate = start
                                draft.endDate = end
                            }
                        }
                        Divider()
                        Button("Custom Range...") {
                            showDatePicker = true
                        }
                    } label: {
                        HStack {
                            Text("Date Range")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(dateLabel)
                                .foregroundStyle(draft.startDate != nil ? Color.accentColor : .secondary)
                        }
                    }

                    // Amount range
                    HStack {
                        Text("Amount")
                        Spacer()
                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            TextField("Min", text: Binding(
                                get: { draft.minAmount.map { String(format: "%.0f", $0) } ?? "" },
                                set: { draft.minAmount = Double($0) }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            .font(.subheadline)
                        }

                        Text("–")
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            TextField("Max", text: Binding(
                                get: { draft.maxAmount.map { String(format: "%.0f", $0) } ?? "" },
                                set: { draft.maxAmount = Double($0) }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            .font(.subheadline)
                        }
                    }
                }

                // Reset all
                if !draft.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            draft = ActivityFilter(cardId: filter.cardId)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Reset All Filters")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("Filters"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = draft
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DateRangePickerSheet(startDate: $draft.startDate, endDate: $draft.endDate)
                    .presentationDetents([.large])
            }
        }
        .onAppear { draft = filter }
    }

    // MARK: - Date Label

    private var dateLabel: String {
        guard let start = draft.startDate else { return "Any Time" }
        let startStr = start.formatted(.dateTime.month(.abbreviated).day())
        if let end = draft.endDate {
            let endStr = end.formatted(.dateTime.month(.abbreviated).day())
            return "\(startStr) – \(endStr)"
        }
        return "From \(startStr)"
    }
}

// MARK: - Active Filter Chips (for ActivityView)

struct ActiveFilterChips: View {
    @Binding var filter: ActivityFilter
    let onChanged: () -> Void

    private let typeLabels: [String: String] = [
        "card_spend,card_refund,card_payment": "Card",
        "deposit,withdraw": "Vault",
        "transfer_in,deposit_rain": "Received",
        "card_spend,send,topup,auto_topup,fee": "Sent",
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let types = filter.types, let label = typeLabels[types] {
                    chip(label, icon: "tag") { filter.types = nil; onChanged() }
                }
                if let start = filter.startDate {
                    let label = filter.endDate != nil
                        ? "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(filter.endDate!.formatted(.dateTime.month(.abbreviated).day()))"
                        : "From \(start.formatted(.dateTime.month(.abbreviated).day()))"
                    chip(label, icon: "calendar") {
                        filter.startDate = nil
                        filter.endDate = nil
                        onChanged()
                    }
                }
                if let min = filter.minAmount {
                    chip("≥ $\(String(format: "%.0f", min))", icon: "dollarsign") {
                        filter.minAmount = nil
                        onChanged()
                    }
                }
                if let max = filter.maxAmount {
                    chip("≤ $\(String(format: "%.0f", max))", icon: "dollarsign") {
                        filter.maxAmount = nil
                        onChanged()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ label: String, icon: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.caption.weight(.medium))
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

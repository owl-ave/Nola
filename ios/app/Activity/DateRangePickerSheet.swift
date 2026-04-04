import SwiftUI

struct DateRangePickerSheet: View {
    @Binding var startDate: Date?
    @Binding var endDate: Date?
    @Environment(\.dismiss) private var dismiss

    @State private var tapState: TapState = .idle
    @State private var originalStart: Date?
    @State private var originalEnd: Date?

    private enum TapState {
        case idle
        case startSelected(Date)
    }

    private let calendar = Calendar.current
    private let today = Date()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var months: [Date] {
        (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: today)
        }.reversed()
    }

    private var selectionSummary: String {
        guard let start = startDate else { return "Tap a start date" }
        let startStr = start.formatted(.dateTime.month(.abbreviated).day())
        guard let end = endDate else { return "\(startStr) → tap an end date" }
        let endStr = end.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(start, inSameDayAs: end) { return startStr }
        return "\(startStr) – \(endStr)"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(months, id: \.self) { month in
                            MonthView(
                                month: month,
                                startDate: startDate,
                                endDate: endDate,
                                today: today,
                                onDayTap: { day in
                                    haptic.impactOccurred()
                                    handleDayTap(day)
                                }
                            )
                            .id(month)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // Bottom artwork + hint
                    datePickerHint
                        .padding(.top, 40)
                        .padding(.bottom, 80)
                        .id("bottom-hint")
                }
                .onAppear {
                    proxy.scrollTo("bottom-hint", anchor: .bottom)
                }
                .safeAreaInset(edge: .bottom) {
                    floatingWeekdayBar
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(startDate != nil ? selectionSummary : "Select Dates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        startDate = originalStart
                        endDate = originalEnd
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            haptic.prepare()
            originalStart = startDate
            originalEnd = endDate
            if startDate != nil, endDate != nil {
                tapState = .idle
            } else if let start = startDate {
                tapState = .startSelected(start)
            }
        }
        .sensoryFeedback(.success, trigger: endDate)
    }

    // MARK: - Floating Bottom Bar

    private var floatingWeekdayBar: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Hint Artwork

    private var datePickerHint: some View {
        VStack(spacing: 16) {
            // Illustration — two tapping hands
            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Start")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("End")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(spacing: 4) {
                Text("Tap to select a date range")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("First tap sets the start, second tap sets the end")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .opacity(startDate == nil ? 1 : 0.5)
    }

    // MARK: - Logic

    private func handleDayTap(_ day: Date) {
        switch tapState {
        case .idle:
            startDate = day
            endDate = nil
            tapState = .startSelected(day)
        case .startSelected(let start):
            if day < start {
                startDate = day
                endDate = nil
                tapState = .startSelected(day)
            } else if day == start {
                endDate = day
                tapState = .idle
            } else {
                endDate = day
                tapState = .idle
            }
        }
    }
}

// MARK: - Month View

private struct MonthView: View {
    let month: Date
    let startDate: Date?
    let endDate: Date?
    let today: Date
    let onDayTap: (Date) -> Void

    private let calendar = Calendar.current

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    /// Split days into week rows of 7 (nil for empty slots)
    private var weeks: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }

        let weekdayOffset = calendar.component(.weekday, from: firstDay) - 1
        var allDays: [Date?] = Array(repeating: nil, count: weekdayOffset)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                allDays.append(date)
            }
        }

        // Pad to full weeks
        while allDays.count % 7 != 0 { allDays.append(nil) }

        return stride(from: 0, to: allDays.count, by: 7).map { Array(allDays[$0..<$0+7]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(monthLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 4)
                .padding(.bottom, 2)

            VStack(spacing: 2) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                    WeekRow(
                        week: week,
                        startDate: startDate,
                        endDate: endDate,
                        today: today,
                        weekId: "\(monthLabel)-\(weekIndex)",
                        onDayTap: onDayTap
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}

// MARK: - Week Row

private struct WeekRow: View {
    let week: [Date?]
    let startDate: Date?
    let endDate: Date?
    let today: Date
    let weekId: String
    let onDayTap: (Date) -> Void

    @Namespace private var rowNS
    private let calendar = Calendar.current
    private let cellHeight: CGFloat = 42

    private func isInRange(_ date: Date) -> Bool {
        guard let start = startDate, let end = endDate else { return false }
        return date >= start && date <= end
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    if let day = week[i] {
                        let isStart = startDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
                        let isEnd = endDate.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
                        let inRange = isInRange(day)

                        DayCell(
                            date: day,
                            isToday: calendar.isDate(day, inSameDayAs: today),
                            isFuture: day > today,
                            isStart: isStart,
                            isEnd: isEnd,
                            isInRange: inRange,
                            isSelected: isStart || isEnd || inRange,
                            rangeNS: rowNS,
                            onTap: { onDayTap(day) }
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: cellHeight)
                    }
                }
            }
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isFuture: Bool
    let isStart: Bool
    let isEnd: Bool
    let isInRange: Bool
    let isSelected: Bool
    let rangeNS: Namespace.ID
    let onTap: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onTap) {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .fontWeight(isStart || isEnd ? .bold : isToday ? .medium : .regular)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .buttonStyle(.plain)
        .if_selected(isSelected) { view in
            view
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .glassEffectUnion(id: "range", namespace: rangeNS)
        }
        .disabled(isFuture)
    }

    private var foregroundColor: some ShapeStyle {
        if isFuture { return AnyShapeStyle(.quaternary) }
        if isStart || isEnd { return AnyShapeStyle(.primary) }
        if isInRange { return AnyShapeStyle(.primary) }
        if isToday { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.primary)
    }
}

// MARK: - Conditional Modifier

private extension View {
    @ViewBuilder
    func if_selected<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

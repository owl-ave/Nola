import SwiftUI

struct SupportView: View {
    @EnvironmentObject var appState: AppState
    @State private var tickets: [SupportTicket] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showNewTicket = false

    private var supportService: SupportService { SupportService(client: appState.apiClient) }
    private var openTickets: [SupportTicket] { tickets.filter { $0.isOpen } }
    private var closedTickets: [SupportTicket] { tickets.filter { !$0.isOpen } }

    var body: some View {
        Group {
            if isLoading && tickets.isEmpty {
                // First load
                List {
                    ForEach(0..<4, id: \.self) { _ in
                        TicketSkeletonRow()
                    }
                }
                .listStyle(.insetGrouped)
            } else if let error = loadError, tickets.isEmpty {
                // Error on first load
                ContentUnavailableView {
                    Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await loadTickets() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if tickets.isEmpty {
                // Empty
                ContentUnavailableView {
                    Label("No Tickets", systemImage: "questionmark.bubble")
                } description: {
                    Text("Create a ticket to get help from our team.")
                } actions: {
                    Button("New Ticket") { showNewTicket = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                // Ticket list
                List {
                    if !openTickets.isEmpty {
                        Section("Open") {
                            ForEach(openTickets) { ticket in
                                NavigationLink(value: SettingsDestination.supportTicket(String(ticket.id))) {
                                    TicketRow(ticket: ticket)
                                }
                            }
                        }
                    }
                    if !closedTickets.isEmpty {
                        Section("Resolved") {
                            ForEach(closedTickets) { ticket in
                                NavigationLink(value: SettingsDestination.supportTicket(String(ticket.id))) {
                                    TicketRow(ticket: ticket)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(Text("Support"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewTicket = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await loadTickets() }
        .task { await loadTickets() }
        .sheet(isPresented: $showNewTicket) {
            NewTicketSheet {
                showNewTicket = false
                Task { await loadTickets() }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func loadTickets() async {
        if tickets.isEmpty { isLoading = true }
        loadError = nil
        do {
            tickets = try await supportService.listTickets()
        } catch {
            print("[Support] Failed to load tickets: \(error)")
            if tickets.isEmpty { loadError = error.localizedDescription }
        }
        isLoading = false
    }
}

// MARK: - Helpers

private struct TicketRow: View {
    let ticket: SupportTicket

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ticket.subject)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(ticket.statusLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(relativeDate(ticket.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var statusColor: Color {
        switch ticket.status {
        case 2: return .blue
        case 3: return .orange
        case 4: return .green
        default: return .secondary
        }
    }

    private func relativeDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: iso)
        }() else { return String(iso.prefix(10)) }

        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}

private struct TicketSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray5))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: CGFloat.random(in: 120...200), height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemGray6))
                    .frame(width: 80, height: 10)
            }
            Spacer()
        }
        .shimmer()
    }
}

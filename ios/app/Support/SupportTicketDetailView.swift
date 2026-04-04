import SwiftUI

struct SupportTicketDetailView: View {
    @EnvironmentObject var appState: AppState
    let ticketId: Int

    @State private var ticket: SupportTicket?
    @State private var conversations: [SupportConversation] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var replyText = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var isUpdatingStatus = false
    @State private var showCloseConfirmation = false
    @FocusState private var isInputFocused: Bool
    @State private var showReplyInput = false

    private var supportService: SupportService { SupportService(client: appState.apiClient) }

    var body: some View {
        Group {
            if isLoading && ticket == nil {
                loadingSkeleton
            } else if let error = loadError, ticket == nil {
                ContentUnavailableView {
                    Label("Couldn't Load Ticket", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await loadTicket() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if let ticket {
                ticketContent(ticket)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: showReplyInput)
        .sensoryFeedback(.error, trigger: sendError)
        .navigationTitle(Text("#\(ticketId)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ticket != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let ticket, ticket.isOpen {
                            Button(role: .destructive) {
                                showCloseConfirmation = true
                            } label: {
                                Label("Mark as Resolved", systemImage: "checkmark.circle")
                            }
                        } else {
                            Button {
                                Task { await updateStatus(2) }
                            } label: {
                                Label("Reopen Ticket", systemImage: "arrow.uturn.left.circle")
                            }
                        }
                    } label: {
                        if isUpdatingStatus {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .disabled(isUpdatingStatus)
                }
            }
        }
        .confirmationDialog(
            "Resolve this ticket?",
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Resolved") { Task { await updateStatus(4) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will close the ticket. You can reopen it later if needed.")
        }
        .refreshable { await loadTicket() }
        .task { await loadTicket() }
    }

    // MARK: - Skeleton

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header skeleton
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 220, height: 22)
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: 70, height: 22)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 22)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray6))
                        .frame(height: 48)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Activity skeleton
                VStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 140, height: 12)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray6))
                                    .frame(height: 40)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .shimmer()
        }
    }

    // MARK: - Content

    private func ticketContent(_ ticket: SupportTicket) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ticketHeader(ticket)
                    activityDivider
                    conversationThread
                }
                .padding(.bottom, ticket.isOpen ? 80 : 12)
            }
            .onTapGesture { isInputFocused = false }
            .overlay(alignment: .bottomTrailing) {
                if ticket.isOpen && !showReplyInput {
                    Button {
                        showReplyInput = true
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 52, height: 52)
                    }
                    .tint(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if ticket.isOpen && showReplyInput {
                    commentInput
                        .onAppear { isInputFocused = true }
                } else if !ticket.isOpen {
                    resolvedBanner
                }
            }
            .animation(.spring(duration: 0.3), value: showReplyInput)
            .onChange(of: isInputFocused) { _, focused in
                if !focused && replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showReplyInput = false
                }
            }
            .onChange(of: conversations.count) {
                if let lastId = conversations.last?.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private func ticketHeader(_ ticket: SupportTicket) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ticket.subject)
                .font(.title2.weight(.bold))

            HStack(spacing: 8) {
                StatusPill(
                    icon: statusIcon(ticket),
                    label: ticket.statusLabel,
                    color: statusColor(ticket)
                )
                StatusPill(
                    icon: "flag.fill",
                    label: ticket.priorityLabel,
                    color: priorityColor(ticket)
                )
                Spacer()
                Text(relativeDate(ticket.createdAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let desc = ticket.descriptionText, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - Activity Divider

    private var activityDivider: some View {
        HStack(spacing: 12) {
            VStack { Divider() }
            HStack(spacing: 4) {
                Text("Activity")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                if !conversations.isEmpty {
                    Text("\(conversations.count)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.quaternary)
                }
            }
            .layoutPriority(1)
            VStack { Divider() }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Conversation Thread

    @ViewBuilder
    private var conversationThread: some View {
        if conversations.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.title)
                    .foregroundStyle(.quaternary)
                Text("No replies yet")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(conversations) { conv in
                    CommentCard(conversation: conv)
                        .id(conv.id)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Comment Input

    private var hasInput: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var commentInput: some View {
        VStack(spacing: 0) {
            if let sendError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(sendError)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button { self.sendError = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment...", text: $replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))

                if hasInput || isSending {
                    Button {
                        Task { await sendReply() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .tint(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(isSending || !hasInput)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: hasInput)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.clear)
    }

    // MARK: - Resolved Banner

    private var resolvedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("This ticket has been resolved")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func statusIcon(_ ticket: SupportTicket) -> String {
        switch ticket.status {
        case 2: return "circle.badge"
        case 3: return "clock"
        case 4: return "checkmark.circle"
        case 5: return "xmark.circle"
        default: return "questionmark.circle"
        }
    }

    private func statusColor(_ ticket: SupportTicket) -> Color {
        switch ticket.status {
        case 2: return .blue
        case 3: return .orange
        case 4: return .green
        case 5: return .secondary
        default: return .secondary
        }
    }

    private func priorityColor(_ ticket: SupportTicket) -> Color {
        switch ticket.priority {
        case 1: return .secondary
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
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
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Data

    private func loadTicket() async {
        if ticket == nil { isLoading = true }
        loadError = nil
        do {
            let response = try await supportService.getTicket(id: ticketId)
            ticket = response.ticket
            conversations = response.conversations
        } catch {
            if ticket == nil { loadError = error.localizedDescription }
        }
        isLoading = false
    }

    private func updateStatus(_ status: Int) async {
        isUpdatingStatus = true
        do {
            try await supportService.updateTicketStatus(id: ticketId, status: status)
            await loadTicket()
        } catch {
            sendError = error.localizedDescription
        }
        isUpdatingStatus = false
    }

    private func sendReply() async {
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        sendError = nil
        do {
            let newConv = try await supportService.replyToTicket(id: ticketId, body: trimmed)
            conversations.append(newConv)
            replyText = ""
            isInputFocused = false
            showReplyInput = false
        } catch {
            sendError = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Status Pill

private struct StatusPill: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Comment Card

private struct CommentCard: View {
    let conversation: SupportConversation

    private var isCustomer: Bool { conversation.incoming ?? true }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(isCustomer ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                    .frame(width: 32, height: 32)
                Image(systemName: isCustomer ? "person.fill" : "headset")
                    .font(.caption)
                    .foregroundStyle(isCustomer ? Color.accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Attribution
                HStack(spacing: 6) {
                    Text(isCustomer ? "You" : "Support Team")
                        .font(.subheadline.weight(.medium))
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(formatDate(conversation.createdAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                // Body
                Text(cleanHtml(conversation.body))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private func cleanHtml(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: iso) ?? {
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: iso)
        }() else { return String(iso.prefix(10)) }

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

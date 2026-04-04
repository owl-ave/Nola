import Foundation

struct SupportTicket: Decodable, Identifiable {
    let id: Int
    let subject: String
    let status: Int
    let priority: Int
    let descriptionText: String?
    let createdAt: String
    let updatedAt: String?

    var statusLabel: String {
        switch status {
        case 2: return "Open"
        case 3: return "Pending"
        case 4: return "Resolved"
        case 5: return "Closed"
        default: return "Unknown"
        }
    }

    var statusColor: String {
        switch status {
        case 2: return "blue"
        case 3: return "orange"
        case 4: return "green"
        case 5: return "gray"
        default: return "gray"
        }
    }

    var priorityLabel: String {
        switch priority {
        case 1: return "Low"
        case 2: return "Medium"
        case 3: return "High"
        case 4: return "Urgent"
        default: return "Medium"
        }
    }

    var isOpen: Bool { status == 2 || status == 3 }
}

struct SupportConversation: Decodable, Identifiable {
    let id: Int
    let body: String
    let incoming: Bool?
    let createdAt: String
}

struct SupportTicketListResponse: Decodable {
    let tickets: [SupportTicket]
}

struct SupportTicketDetailResponse: Decodable {
    let ticket: SupportTicket
    let conversations: [SupportConversation]
}

class SupportService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func createTicket(subject: String, description: String, priority: Int = 2) async throws -> SupportTicket {
        struct Body: Encodable { let subject: String; let description: String; let priority: Int }
        return try await client.request("POST", path: "/v1/support/tickets", body: Body(subject: subject, description: description, priority: priority))
    }

    func listTickets() async throws -> [SupportTicket] {
        let response: SupportTicketListResponse = try await client.request("GET", path: "/v1/support/tickets")
        return response.tickets
    }

    func getTicket(id: Int) async throws -> SupportTicketDetailResponse {
        try await client.request("GET", path: "/v1/support/tickets/\(id)")
    }

    func updateTicketStatus(id: Int, status: Int) async throws {
        struct Body: Encodable { let status: Int }
        struct Response: Decodable { let id: Int; let status: Int }
        _ = try await client.request("PUT", path: "/v1/support/tickets/\(id)", body: Body(status: status)) as Response
    }

    func replyToTicket(id: Int, body: String) async throws -> SupportConversation {
        struct Body: Encodable { let body: String }
        return try await client.request("POST", path: "/v1/support/tickets/\(id)/reply", body: Body(body: body))
    }
}

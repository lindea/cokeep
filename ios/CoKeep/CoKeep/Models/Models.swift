import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: String
    var firstName: String
    var lastName: String
    var email: String
    var phoneE164: String
    var countryCode: String
    var avatarUrl: String?
    var preferredLanguage: String?

    var displayName: String { "\(firstName) \(lastName)" }
    var initials: String {
        String(firstName.prefix(1) + lastName.prefix(1)).uppercased()
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct SharedObject: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var template: String
    var imageUrl: String?
    var role: String?
    var unreadAlertCount: Int?
    var members: [ObjectMember]?
    var todoLists: [TodoListSummary]?
}

struct ObjectMember: Codable, Identifiable, Hashable {
    let id: String
    var role: String
    var joinedAt: String?
    var user: User
}

struct TodoListSummary: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var sortOrder: Int?
}

struct TodoList: Codable, Identifiable {
    let id: String
    var objectId: String
    var name: String
    var sortOrder: Int?
    var unreadAlertCount: Int?
    var openItems: [TodoItem]
    var doneItems: [TodoItem]
}

struct TodoItem: Codable, Identifiable, Hashable {
    let id: String
    var listId: String
    var objectId: String?
    var name: String
    var description: String?
    var scheduleType: String
    var dueDate: String?
    var recurrence: String?
    var assigneeId: String?
    var assignee: Assignee?
    var isDone: Bool
    var completedAt: String?
    var completedById: String?
    var totalWorkMinutes: Int?
    var hasUnreadAlert: Bool?
    var logs: [WorkLogEntry]?
}

struct Assignee: Codable, Hashable {
    let id: String
    var firstName: String
    var lastName: String
    var avatarUrl: String?

    var displayName: String { "\(firstName) \(lastName)" }
}

struct WorkLogEntry: Codable, Identifiable, Hashable {
    let id: String
    var startedAt: String
    var endedAt: String
    var durationMinutes: Int
    var note: String?
    var user: User
}

struct CostEntry: Codable, Identifiable, Hashable {
    let id: String
    var amountCents: Int
    var currency: String
    var description: String?
    var receiptUrl: String?
    var spentAt: String
    var todoItemId: String?
    var todoItemName: String?
    var user: User

    var amountDisplay: String {
        let value = Double(amountCents) / 100.0
        return String(format: "%.2f %@", value, currency)
    }
}

struct Invite: Codable, Identifiable {
    let id: String
    var status: String?
    var createdAt: String?
    var object: SharedObject
    var invitedBy: User
}

struct ChartPoint: Codable, Identifiable {
    var id: String { label }
    let label: String
    let value: Double
}

struct SpendingsReport: Codable {
    let totalCents: Int
    let currency: String
    let byUser: [UserSpend]
    let items: [ReportCostItem]
    let chart: [ChartPoint]
}

struct UserSpend: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let firstName: String
    let lastName: String
    let avatarUrl: String?
    let totalCents: Int
}

struct ReportCostItem: Codable, Identifiable {
    let id: String
    let amountCents: Int
    let currency: String
    let description: String?
    let spentAt: String
    let userId: String
    let firstName: String
    let lastName: String
}

struct WorkReport: Codable {
    let totalMinutes: Int
    let byUser: [UserWork]
    let items: [ReportWorkItem]
    let chart: [ChartPoint]
}

struct UserWork: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let firstName: String
    let lastName: String
    let avatarUrl: String?
    let totalMinutes: Int
}

struct ReportWorkItem: Codable, Identifiable {
    let id: String
    let startedAt: String
    let endedAt: String
    let durationMinutes: Int
    let todoItemId: String
    let todoItemName: String
    let userId: String
    let firstName: String
    let lastName: String
}

struct CountryCode: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let flag: String
    let name: String

    static let common: [CountryCode] = [
        .init(code: "+47", flag: "🇳🇴", name: "Norway"),
        .init(code: "+46", flag: "🇸🇪", name: "Sweden"),
        .init(code: "+45", flag: "🇩🇰", name: "Denmark"),
        .init(code: "+1", flag: "🇺🇸", name: "United States"),
        .init(code: "+44", flag: "🇬🇧", name: "United Kingdom"),
        .init(code: "+49", flag: "🇩🇪", name: "Germany"),
        .init(code: "+358", flag: "🇫🇮", name: "Finland"),
    ]
}

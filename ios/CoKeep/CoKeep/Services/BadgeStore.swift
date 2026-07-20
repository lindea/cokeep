import Foundation
import UIKit
import Combine
import SwiftUI

/// Tracks unread push alerts and keeps the home-screen app icon badge in sync.
@MainActor
final class BadgeStore: ObservableObject {
    static let shared = BadgeStore()

    @Published private(set) var badge = 0
    @Published private(set) var unreadInviteCount = 0
    @Published private(set) var unreadTodoItemIds: Set<String> = []
    @Published private(set) var byObject: [String: Int] = [:]
    @Published private(set) var byList: [String: Int] = [:]

    private init() {}

    func refresh() async {
        guard APIClient.shared.authToken != nil else {
            applyLocal(badge: 0, invites: 0, todoIds: [], byObject: [:], byList: [:])
            return
        }
        struct Resp: Codable {
            let badge: Int
            let unreadInviteCount: Int
            let unreadTodoItemIds: [String]
            let byObject: [String: Int]
            let byList: [String: Int]
        }
        do {
            let resp: Resp = try await APIClient.shared.request("GET", path: "api/users/badge")
            applyLocal(
                badge: resp.badge,
                invites: resp.unreadInviteCount,
                todoIds: resp.unreadTodoItemIds,
                byObject: resp.byObject,
                byList: resp.byList
            )
        } catch {
            print("Badge refresh failed: \(error)")
        }
    }

    func markTodoViewed(_ todoItemId: String) async {
        struct Body: Encodable { let todoItemId: String }
        struct Resp: Codable { let badge: Int }
        do {
            let resp: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/users/notifications/mark-read",
                body: Body(todoItemId: todoItemId)
            )
            unreadTodoItemIds.remove(todoItemId)
            setIconBadge(resp.badge)
            badge = resp.badge
            await refresh()
        } catch {
            print("Mark todo notification read failed: \(error)")
        }
    }

    func markInvitesViewed() async {
        struct Body: Encodable { let invites: Bool }
        struct Resp: Codable { let badge: Int }
        do {
            let resp: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/users/notifications/mark-read",
                body: Body(invites: true)
            )
            unreadInviteCount = 0
            setIconBadge(resp.badge)
            badge = resp.badge
            await refresh()
        } catch {
            print("Mark invite notifications read failed: \(error)")
        }
    }

    private func applyLocal(
        badge: Int,
        invites: Int,
        todoIds: [String],
        byObject: [String: Int],
        byList: [String: Int]
    ) {
        self.badge = badge
        unreadInviteCount = invites
        unreadTodoItemIds = Set(todoIds)
        self.byObject = byObject
        self.byList = byList
        setIconBadge(badge)
    }

    private func setIconBadge(_ count: Int) {
        UIApplication.shared.applicationIconBadgeNumber = count
    }
}

struct AlertBadgeView: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, count > 9 ? 6 : 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.danger))
        }
    }
}

struct AlertDotView: View {
    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: 8, height: 8)
    }
}

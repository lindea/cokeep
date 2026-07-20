import SwiftUI

struct MainTabView: View {
    @StateObject private var badges = BadgeStore.shared
    @State private var selected = 0
    @State private var pendingObjectId: String?
    @State private var pendingTodoItemId: String?

    var body: some View {
        TabView(selection: $selected) {
            ObjectsListView(
                deepLinkObjectId: $pendingObjectId,
                deepLinkTodoItemId: $pendingTodoItemId
            )
            .tabItem {
                Label(L10n.string("tab.objects"), systemImage: "house.fill")
            }
            .tag(0)

            PendingInvitesView()
                .tabItem {
                    Label(L10n.string("tab.invites"), systemImage: "person.badge.plus")
                }
                .badge(badges.unreadInviteCount)
                .tag(1)

            ProfileView()
                .tabItem {
                    Label(L10n.string("tab.profile"), systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(Theme.accent)
        .task {
            await badges.refresh()
        }
        .onAppear {
            PushNotificationRegistrar.onOpenInvites = {
                selected = 1
            }
            PushNotificationRegistrar.onOpenTodo = { objectId, todoItemId in
                selected = 0
                pendingObjectId = objectId
                pendingTodoItemId = todoItemId
            }
        }
    }
}

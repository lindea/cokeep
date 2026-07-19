import SwiftUI

struct MainTabView: View {
    @State private var selected = 0

    var body: some View {
        TabView(selection: $selected) {
            ObjectsListView()
                .tabItem {
                    Label(L10n.string("tab.objects"), systemImage: "house.fill")
                }
                .tag(0)

            PendingInvitesView()
                .tabItem {
                    Label(L10n.string("tab.invites"), systemImage: "person.badge.plus")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label(L10n.string("tab.profile"), systemImage: "person.crop.circle")
                }
                .tag(2)
        }
        .tint(Theme.accent)
    }
}

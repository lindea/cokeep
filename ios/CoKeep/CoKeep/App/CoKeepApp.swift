import SwiftUI

@main
struct CoKeepApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var localization = LocalizationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    session.handleDeepLink(url)
                }
        }
    }
}

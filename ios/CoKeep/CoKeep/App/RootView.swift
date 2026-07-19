import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isBootstrapping {
                SplashView()
            } else if session.isAuthenticated {
                MainTabView()
                    .task {
                        await PushNotificationRegistrar.requestAuthorization()
                    }
            } else if session.resetToken != nil {
                ResetPasswordView(token: session.resetToken!)
            } else {
                AuthFlowView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        .task {
            await session.bootstrap()
        }
    }
}

struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("CoKeep")
                    .font(Theme.brandFont(size: 44))
                    .foregroundStyle(Theme.ink)
                    .scaleEffect(appear ? 1 : 0.92)
                    .opacity(appear ? 1 : 0)
                Text(L10n.string("splash.tagline"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                appear = true
            }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var launch = LaunchConfigStore.shared

    var body: some View {
        Group {
            if session.isBootstrapping || launch.isChecking {
                SplashView()
            } else if let gate = launch.gate {
                switch gate {
                case .forceUpdate(let msg):
                    LaunchMessageView(message: msg, isForceUpdate: true)
                case .message(let msg):
                    LaunchMessageView(message: msg, isForceUpdate: false) {
                        launch.acknowledgeMessage()
                    }
                }
            } else if session.isAuthenticated {
                MainTabView()
                    .task {
                        await PushNotificationRegistrar.requestAuthorization()
                        await PushNotificationRegistrar.flushPendingToken()
                        await BadgeStore.shared.refresh()
                    }
            } else if session.resetToken != nil {
                ResetPasswordView(token: session.resetToken!)
            } else {
                AuthFlowView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: launch.gate)
        .task {
            async let boot = session.bootstrap()
            async let cfg = launch.checkOnLaunch()
            await boot
            await cfg
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

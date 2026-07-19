import Foundation
import UserNotifications

/// Registers for remote notifications. Wire APNs credentials on the backend for production delivery.
enum PushNotificationRegistrar {
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await MainActor.run {
                // UIApplication.shared.registerForRemoteNotifications() — call from AppDelegate / scene when available.
            }
            // After receiving the device token in the app delegate, POST it to /api/users/device-token.
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    static func registerToken(_ token: Data) async {
        let hex = token.map { String(format: "%02.2hhx", $0) }.joined()
        struct Body: Encodable {
            let token: String
            let platform: String
        }
        struct Resp: Codable {
            let device: DeviceTokenDTO
        }
        struct DeviceTokenDTO: Codable {
            let id: String
        }
        do {
            let _: Resp = try await APIClient.shared.request(
                "POST",
                path: "api/users/device-token",
                body: Body(token: hex, platform: "ios")
            )
        } catch {
            print("Failed to register device token: \(error)")
        }
    }
}

import Foundation
import UIKit
import UserNotifications

/// Registers FCM push tokens and routes notification taps.
@MainActor
enum PushNotificationRegistrar {
    static var onOpenInvites: (() -> Void)?

    static func requestAuthorization() async {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("Push: add GoogleService-Info.plist from Firebase to enable notifications")
            return
        }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    static func registerToken(_ token: String) async {
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
                body: Body(token: token, platform: "ios")
            )
        } catch {
            print("Failed to register device token: \(error)")
        }
    }

    static func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        let data = flatten(userInfo)
        guard data["type"] == "invite" else { return }
        onOpenInvites?()
    }

    private static func flatten(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            if let nested = value as? [AnyHashable: Any] {
                for (nestedKey, nestedValue) in nested {
                    guard let nestedKey = nestedKey as? String else { continue }
                    result[nestedKey] = String(describing: nestedValue)
                }
            } else {
                result[key] = String(describing: value)
            }
        }
        return result
    }
}

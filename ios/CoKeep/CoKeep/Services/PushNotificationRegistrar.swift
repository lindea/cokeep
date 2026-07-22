import Foundation
import UIKit
import UserNotifications

/// Registers APNs device tokens and routes notification taps.
@MainActor
enum PushNotificationRegistrar {
    static var onOpenInvites: (() -> Void)?
    static var onOpenTodo: ((String, String) -> Void)?

    /// Held until the user is authenticated, then flushed to the API.
    private static var pendingToken: String?

    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await UIApplication.shared.registerForRemoteNotifications()
            await flushPendingToken()
        } catch {
            print("Push authorization failed: \(error)")
        }
    }

    /// Stores the APNs token and uploads it once a session JWT is available.
    static func registerToken(_ token: String) async {
        pendingToken = token
        await flushPendingToken()
    }

    /// Uploads any deferred device token after login / bootstrap.
    static func flushPendingToken() async {
        guard let token = pendingToken else { return }
        guard APIClient.shared.authToken != nil else {
            print("Deferred device token registration until authenticated")
            return
        }

        struct Body: Encodable {
            let token: String
            let platform: String
            let language: String
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
                body: Body(token: token, platform: "ios", language: L10n.appLanguageCode)
            )
        } catch {
            print("Failed to register device token: \(error)")
        }
    }

    static func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        let data = flatten(userInfo)
        let type = data["type"] ?? ""
        switch type {
        case "invite":
            onOpenInvites?()
        case "todo_due_soon", "todo_overdue":
            if let objectId = data["objectId"], let todoItemId = data["todoItemId"] {
                onOpenTodo?(objectId, todoItemId)
            }
        default:
            break
        }
        Task { await BadgeStore.shared.refresh() }
    }

    static func handleForegroundPush(_ userInfo: [AnyHashable: Any]) {
        if let badgeString = flatten(userInfo)["badge"], let badge = Int(badgeString) {
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
        Task { await BadgeStore.shared.refresh() }
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

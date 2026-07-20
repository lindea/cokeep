import Foundation
import Combine

enum LaunchVersionOp: String, Codable, Equatable {
    case ANY, EQ, LT, LTE, GT, GTE, BETWEEN
}

/// One remote launch splash / force-update message.
struct AppLaunchMessage: Codable, Equatable, Identifiable {
    let id: String
    var enabled: Bool
    var title: String
    var bodyMarkdown: String
    var blocking: Bool
    var forceUpdate: Bool
    var versionOp: LaunchVersionOp
    var versionA: String?
    var versionB: String?
    var updateUrl: String?
    var sortOrder: Int
    var updatedAt: String
}

private struct LaunchMessagesResponse: Codable {
    let messages: [AppLaunchMessage]
    let defaultUpdateUrl: String?
}

@MainActor
final class LaunchConfigStore: ObservableObject {
    static let shared = LaunchConfigStore()

    @Published private(set) var isChecking = true
    /// When set, the splash (or force-update) gate is active.
    @Published private(set) var gate: Gate?

    private var queue: [AppLaunchMessage] = []
    private let dismissedKey = "cokeep.launchMessage.dismissedById"

    enum Gate: Equatable {
        case forceUpdate(AppLaunchMessage)
        case message(AppLaunchMessage)
    }

    func checkOnLaunch() async {
        isChecking = true
        defer { isChecking = false }

        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let lang = L10n.appLanguageCode

        do {
            let response: LaunchMessagesResponse = try await APIClient.shared.request(
                "GET",
                path: "api/app/launch-messages",
                query: [
                    URLQueryItem(name: "iosVersion", value: installed),
                    URLQueryItem(name: "lang", value: lang),
                ],
                authorized: false
            )
            queue = Self.applicableMessages(response.messages, installed: installed)
            presentNext()
        } catch {
            // Fail open: do not block the app if the config endpoint is unreachable.
            queue = []
            gate = nil
        }
    }

    func acknowledgeMessage() {
        guard case .message(let msg) = gate else { return }
        if !msg.blocking {
            markDismissed(msg)
        }
        if !queue.isEmpty {
            queue.removeFirst()
        }
        presentNext()
    }

    private func presentNext() {
        while let next = queue.first {
            if next.forceUpdate {
                gate = .forceUpdate(next)
                return
            }
            let hasContent = !next.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !next.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasContent {
                queue.removeFirst()
                continue
            }
            if !next.blocking, isDismissed(next) {
                queue.removeFirst()
                continue
            }
            gate = .message(next)
            return
        }
        gate = nil
    }

    private static func applicableMessages(
        _ messages: [AppLaunchMessage],
        installed: String
    ) -> [AppLaunchMessage] {
        messages
            .filter { $0.enabled && AppVersion.matches(installed, op: $0.versionOp, a: $0.versionA, b: $0.versionB) }
            .sorted { lhs, rhs in
                if lhs.forceUpdate != rhs.forceUpdate { return lhs.forceUpdate && !rhs.forceUpdate }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func dismissedMap() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: String]) ?? [:]
    }

    private func isDismissed(_ msg: AppLaunchMessage) -> Bool {
        dismissedMap()[msg.id] == msg.updatedAt
    }

    private func markDismissed(_ msg: AppLaunchMessage) {
        var map = dismissedMap()
        map[msg.id] = msg.updatedAt
        UserDefaults.standard.set(map, forKey: dismissedKey)
    }
}

enum AppVersion {
    /// Compares dotted version strings (e.g. "1.2.0" vs "1.10").
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    static func matches(
        _ installed: String,
        op: LaunchVersionOp,
        a: String?,
        b: String?
    ) -> Bool {
        let versionA = a?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let versionB = b?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch op {
        case .ANY:
            return true
        case .EQ:
            return !versionA.isEmpty && compare(installed, versionA) == .orderedSame
        case .LT:
            return !versionA.isEmpty && compare(installed, versionA) == .orderedAscending
        case .LTE:
            return !versionA.isEmpty && compare(installed, versionA) != .orderedDescending
        case .GT:
            return !versionA.isEmpty && compare(installed, versionA) == .orderedDescending
        case .GTE:
            return !versionA.isEmpty && compare(installed, versionA) != .orderedAscending
        case .BETWEEN:
            return !versionA.isEmpty
                && !versionB.isEmpty
                && compare(installed, versionA) != .orderedAscending
                && compare(installed, versionB) != .orderedDescending
        }
    }
}

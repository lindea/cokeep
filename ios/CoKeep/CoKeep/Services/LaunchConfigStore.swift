import Foundation
import Combine

enum LaunchVersionOp: String, Codable, Equatable {
    case ANY, EQ, LT, LTE, GT, GTE, BETWEEN
}

/// One remote launch splash / force-update message.
struct AppLaunchMessage: Codable, Equatable, Identifiable {
    let id: String
    var enabled: Bool
    /// Server-resolved for requested lang (may be wrong if lang detection mismatched).
    var title: String
    var bodyMarkdown: String
    var lang: String?
    var titleEn: String?
    var bodyMarkdownEn: String?
    var titleNb: String?
    var bodyMarkdownNb: String?
    var blocking: Bool
    var forceUpdate: Bool
    var versionOp: LaunchVersionOp
    var versionA: String?
    var versionB: String?
    var updateUrl: String?
    var expiresAt: String?
    var sortOrder: Int
    var updatedAt: String

    /// True when expiresAt is set and is not in the future.
    var isExpired: Bool {
        guard let expiresAt,
              let date = ISO8601DateFormatter.launchExpires.date(from: expiresAt)
                ?? ISO8601DateFormatter.launchExpiresFractional.date(from: expiresAt)
        else { return false }
        return date <= Date()
    }

    /// Picks EN/NB the same way as the rest of the app (`L10n.appLanguageCode`).
    func localizedForApp() -> AppLaunchMessage {
        let code = L10n.appLanguageCode
        let useNb = code == "nb"
        let nbTitle = titleNb?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nbBody = bodyMarkdownNb?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let enTitle = titleEn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let enBody = bodyMarkdownEn?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var copy = self
        if useNb {
            // Prefer Norwegian when present; fall back to English only if NB is empty.
            copy.title = nbTitle.isEmpty ? (enTitle.isEmpty ? title : enTitle) : nbTitle
            copy.bodyMarkdown = nbBody.isEmpty ? (enBody.isEmpty ? bodyMarkdown : enBody) : nbBody
        } else {
            copy.title = enTitle.isEmpty ? title : enTitle
            copy.bodyMarkdown = enBody.isEmpty ? bodyMarkdown : enBody
        }
        copy.lang = code
        return copy
    }
}

private struct LaunchMessagesResponse: Codable {
    let messages: [AppLaunchMessage]
    let defaultUpdateUrl: String?
}

private extension ISO8601DateFormatter {
    static let launchExpires: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let launchExpiresFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

@MainActor
final class LaunchConfigStore: ObservableObject {
    static let shared = LaunchConfigStore()

    @Published private(set) var isChecking = true
    /// When set, the splash (or force-update) gate is active.
    @Published private(set) var gate: Gate?

    private var queue: [AppLaunchMessage] = []
    /// Message ids the user has already continued past (non–force-update).
    private let seenIdsKey = "cokeep.launchMessage.seenIds"
    /// Legacy map of id → updatedAt from earlier dismissal logic.
    private let legacyDismissedKey = "cokeep.launchMessage.dismissedById"

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
            queue = Self.applicableMessages(
                response.messages.map { $0.localizedForApp() },
                installed: installed
            )
            presentNext()
        } catch {
            // Fail open: do not block the app if the config endpoint is unreachable.
            queue = []
            gate = nil
        }
    }

    func acknowledgeMessage() {
        guard case .message(let msg) = gate else { return }
        // Blocking and non-blocking: once the user continues, never show again.
        // Force-update never goes through this path.
        markSeen(msg)
        if !queue.isEmpty {
            queue.removeFirst()
        }
        presentNext()
    }

    private func presentNext() {
        while let next = queue.first {
            // Forced updates always show while the version rule matches.
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

            // Already continued past this message (including confirmed blocking ones).
            if hasSeen(next) {
                queue.removeFirst()
                continue
            }

            // Blocking: keep presenting every launch until acknowledgeMessage().
            // Non-blocking: same gate UI; first Continue marks seen.
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
            .filter {
                $0.enabled
                    && !$0.isExpired
                    && AppVersion.matches(installed, op: $0.versionOp, a: $0.versionA, b: $0.versionB)
            }
            .sorted { lhs, rhs in
                if lhs.forceUpdate != rhs.forceUpdate { return lhs.forceUpdate && !rhs.forceUpdate }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func seenIds() -> Set<String> {
        var ids = Set(UserDefaults.standard.stringArray(forKey: seenIdsKey) ?? [])
        // Migrate legacy per-update dismissal map → permanent seen ids.
        if let legacy = UserDefaults.standard.dictionary(forKey: legacyDismissedKey) as? [String: String] {
            ids.formUnion(legacy.keys)
            UserDefaults.standard.set(Array(ids), forKey: seenIdsKey)
            UserDefaults.standard.removeObject(forKey: legacyDismissedKey)
        }
        return ids
    }

    private func hasSeen(_ msg: AppLaunchMessage) -> Bool {
        seenIds().contains(msg.id)
    }

    private func markSeen(_ msg: AppLaunchMessage) {
        var ids = seenIds()
        ids.insert(msg.id)
        UserDefaults.standard.set(Array(ids), forKey: seenIdsKey)
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

import Foundation
import Combine

/// Remote launch splash / force-update config from `GET /api/app/launch-config`.
struct AppLaunchConfig: Codable, Equatable {
    var enabled: Bool
    var title: String
    var bodyMarkdown: String
    var blocking: Bool
    var forceUpdate: Bool
    var minIosVersion: String?
    var updateUrl: String?
    var updatedAt: String
}

@MainActor
final class LaunchConfigStore: ObservableObject {
    static let shared = LaunchConfigStore()

    @Published private(set) var isChecking = true
    /// When set, the splash (or force-update) gate is active.
    @Published private(set) var gate: Gate?

    private let dismissedKey = "cokeep.launchMessage.dismissedUpdatedAt"

    enum Gate: Equatable {
        case forceUpdate(AppLaunchConfig)
        case message(AppLaunchConfig)
    }

    func checkOnLaunch() async {
        isChecking = true
        defer { isChecking = false }

        do {
            let cfg: AppLaunchConfig = try await APIClient.shared.request(
                "GET",
                path: "api/app/launch-config",
                authorized: false
            )
            gate = resolveGate(cfg)
        } catch {
            // Fail open: do not block the app if the config endpoint is unreachable.
            gate = nil
        }
    }

    func acknowledgeMessage() {
        guard case .message(let cfg) = gate else { return }
        if !cfg.blocking {
            UserDefaults.standard.set(cfg.updatedAt, forKey: dismissedKey)
        }
        gate = nil
    }

    private func resolveGate(_ cfg: AppLaunchConfig) -> Gate? {
        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        if cfg.forceUpdate,
           let min = cfg.minIosVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !min.isEmpty,
           AppVersion.compare(installed, min) == .orderedAscending {
            return .forceUpdate(cfg)
        }

        guard cfg.enabled else { return nil }
        let hasContent = !cfg.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !cfg.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasContent else { return nil }

        if cfg.blocking {
            return .message(cfg)
        }

        let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
        if dismissed == cfg.updatedAt {
            return nil
        }
        return .message(cfg)
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
}

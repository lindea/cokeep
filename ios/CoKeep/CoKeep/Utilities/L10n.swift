import Foundation
import Combine

/// Resolves app language from the phone system language (English default, Norwegian when `nb`/`nn`/`no`).
@MainActor
final class LocalizationStore: ObservableObject {
    @Published private(set) var locale: Locale

    init() {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("nb") || preferred.hasPrefix("nn") || preferred.hasPrefix("no") {
            locale = Locale(identifier: "nb")
        } else {
            locale = Locale(identifier: "en")
        }
    }
}

enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

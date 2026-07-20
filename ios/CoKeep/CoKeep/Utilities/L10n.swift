import Foundation
import Combine

/// Resolves app language from the phone system language (English default, Norwegian when `nb`/`nn`/`no`).
@MainActor
final class LocalizationStore: ObservableObject {
    @Published private(set) var locale: Locale

    init() {
        locale = Locale(identifier: L10n.appLanguageCode)
    }
}

enum L10n {
    /// App language code matching LocalizationStore / Localizable.strings (`en` or `nb`).
    /// Uses the same Bundle localization Apple applies to `NSLocalizedString`, not only
    /// `Locale.preferredLanguages.first` (which can disagree on some devices).
    static var appLanguageCode: String {
        let candidates =
            Bundle.main.preferredLocalizations
            + Locale.preferredLanguages
            + [Locale.current.identifier]

        for raw in candidates {
            let lower = raw.lowercased()
            if lower.hasPrefix("nb") || lower.hasPrefix("nn") || lower.hasPrefix("no") {
                return "nb"
            }
        }

        if #available(iOS 16, *) {
            if let code = Locale.current.language.languageCode?.identifier.lowercased(),
               code == "nb" || code == "nn" || code == "no" {
                return "nb"
            }
        }

        return "en"
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// Localizes default cabin todo list names stored in English in the database.
    static func todoListName(_ rawName: String) -> String {
        switch rawName {
        case "Maintenance":
            return string("todos.list.maintenance")
        case "Seasonal":
            return string("todos.list.seasonal")
        case "Shopping":
            return string("todos.list.shopping")
        default:
            return rawName
        }
    }

    static func inviteSmsBody(inviterName: String, objectName: String, link: String) -> String {
        String(format: string("invite.smsBody"), inviterName, objectName, link)
    }
}

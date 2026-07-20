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
    /// App language code matching LocalizationStore (`en` or `nb`).
    static var appLanguageCode: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("nb") || preferred.hasPrefix("nn") || preferred.hasPrefix("no") {
            return "nb"
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

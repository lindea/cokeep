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

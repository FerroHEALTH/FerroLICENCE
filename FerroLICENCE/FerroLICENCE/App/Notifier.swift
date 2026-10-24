import Foundation
import LicenceCore
import Register
import UserNotifications

/// The app's three notifications: recorded, not recorded, renewal due.
struct Notifier: Sendable {
    /// Off in fixture mode, so screenshots never ask for permission.
    let enabled: Bool

    func post(_ id: String, title: String, body: String) {
        guard enabled else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func recorded(_ licence: Licence) {
        post(
            "recorded-\(licence.id)", title: String(localized: "Licence recorded", comment: "Notification title"),
            body: String(
                localized: "\(licence.licensee), until \(licence.notAfter). Ready to send.",
                comment: "Notification: the customer, then the last day"))
    }

    func notRecorded(_ licensee: String, why: String) {
        post(
            "failed-\(licensee)", title: String(localized: "Not recorded", comment: "Notification title"),
            body: String(localized: "\(licensee): \(why)", comment: "Notification: the customer, then why it was not recorded"))
    }

    /// One reminder per licence ending within 60 days, once a day at most.
    func remindRenewals(_ todo: [Todo], register: LicenceRegister) {
        let today = CivilDate.today.description
        for case .endingSoon(_, let id, let days) in todo {
            let key = "reminded.\(id)"
            guard UserDefaults.standard.string(forKey: key) != today, let entry = register.entry(id) else { continue }
            UserDefaults.standard.set(today, forKey: key)
            post(
                "renew-\(id)", title: String(localized: "Renewal due", comment: "Notification title"),
                body: String(
                    localized: "\(entry.licence.licensee) ends in \(days) days.", comment: "Notification: the customer, then the days left")
            )
        }
    }
}

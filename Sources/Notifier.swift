// Native Notification Center posts, so a rank move is seen without opening the
// panel — the panel banner only shows once you click the menu bar, which is too
// late to be a notification. Best-effort: an ad-hoc-signed app may be denied,
// and the diagnostic runs have no bundle at all, so every call is guarded.

import Foundation
import UserNotifications

enum Notifier {
    /// Only a real app bundle can talk to the notification centre; the bare
    /// binary used by `--dump` and friends has no bundle id and would crash.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// Asked once at launch. A denial just means posts are dropped silently.
    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

import AppKit
import UserNotifications

/// Notifications — only on the transition into a waiting state.
@MainActor
enum Notifier {
    private static var authorized = false

    static func prepare() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in authorized = granted }
        }
    }

    static func announce(_ session: Session) {
        guard authorized, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = session.title
        content.subtitle = session.state.title
        content.body = session.detail ?? session.headline
        content.sound = .default
        content.userInfo = ["sessionId": session.id]

        let request = UNNotificationRequest(
            identifier: "\(session.id)-\(session.state.rawValue)-\(Int(session.stateSince.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

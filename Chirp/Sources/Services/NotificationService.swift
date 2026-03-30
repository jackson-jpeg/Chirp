import UserNotifications
import UIKit

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            // Permission result
        }
    }

    func showMessageNotification(from sender: String, text: String, channelName: String) {
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = sender
        content.subtitle = channelName
        content.body = text.hasPrefix("IMG:") ? "Sent a photo" : text
        content.sound = .default
        content.threadIdentifier = channelName

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // immediate
        )
        UNUserNotificationCenter.current().add(request)
    }

    func showSOSNotification(from sender: String) {
        let content = UNMutableNotificationContent()
        content.title = "SOS ALERT"
        content.body = "\(sender) activated emergency beacon"
        content.sound = UNNotificationSound.defaultCritical
        content.interruptionLevel = .critical

        let request = UNNotificationRequest(
            identifier: "sos-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

import ChirpCore
import Foundation
import UserNotifications

/// Local notifications for what arrives while the phone is locked (texts,
/// help, roll call, pings, meet-ups, "Maya is talking"). Nothing leaves the
/// phone: these are posted by the app itself when Bluetooth wakes it.
///
/// Permission is asked on the same first tap that starts the radio, never at
/// launch (5.1.1(iv)); if it is refused, nothing is posted and nothing nags.
enum Notifier {
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(_ alert: LockedAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = alert.thread
        content.sound = .default
        // Time sensitive shows through a Focus once the app has the
        // Time Sensitive Notifications capability; without it iOS treats this
        // as active, which is still delivered.
        content.interruptionLevel = alert.urgency == .timeSensitive ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

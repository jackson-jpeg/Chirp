import AppIntents
import SwiftUI

// MARK: - PTT Intent (Action Button / Shortcuts)

/// App Intent that opens ChirpChirp and starts a PTT session.
/// Users can assign this to their Action Button for instant walkie-talkie.
struct StartChirpPTTIntent: AppIntent {
    static let title: LocalizedStringResource = "Push to Talk"
    static let description: IntentDescription = "Open ChirpChirps and start transmitting on your active channel."
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .chirpPTTShortcutTriggered,
                object: nil
            )
        }
        return .result()
    }
}

/// Opens ChirpChirp to the active channel
struct OpenChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Channel"
    static let description: IntentDescription = "Open ChirpChirps to your active channel."
    static let openAppWhenRun = true

    @Parameter(title: "Channel Name")
    var channelName: String?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .chirpOpenChannelShortcut,
                object: channelName
            )
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Registers shortcuts that appear in the Shortcuts app and can be
/// assigned to the Action Button.
struct ChirpShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartChirpPTTIntent(),
            phrases: [
                "Push to talk with \(.applicationName)",
                "Start \(.applicationName)",
                "Talk on \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Push to Talk",
            systemImageName: "antenna.radiowaves.left.and.right"
        )

        AppShortcut(
            intent: OpenChannelIntent(),
            phrases: [
                "Open \(.applicationName) channel",
                "Open \(.applicationName)"
            ],
            shortTitle: "Open Channel",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let chirpPTTShortcutTriggered = Notification.Name("chirpPTTShortcutTriggered")
    static let chirpOpenChannelShortcut = Notification.Name("chirpOpenChannelShortcut")
}

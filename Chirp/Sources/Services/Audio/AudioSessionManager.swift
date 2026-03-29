import AVFoundation
import OSLog

enum AudioSessionManager {

    // MARK: - Interruption Callbacks

    /// Called when an audio interruption begins (e.g., phone call).
    /// PTTEngine should auto-release the floor when this fires.
    nonisolated(unsafe) static var onInterruptionBegan: (() -> Void)?

    /// Called when an audio interruption ends with shouldResume.
    nonisolated(unsafe) static var onInterruptionEnded: (() -> Void)?

    // MARK: - Configuration

    /// Configure audio session for PTT.
    /// - Parameter echoCancel: Use `.voiceChat` mode with echo cancellation.
    ///   Set to false for loopback testing (AEC would cancel your own voice).
    ///   Set to true for real peer-to-peer (prevents speaker→mic feedback).
    static func configure(echoCancel: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()

        // .voiceChat enables hardware AEC + AGC + noise suppression
        // .default disables AEC — needed for loopback (hearing yourself)
        let mode: AVAudioSession.Mode = echoCancel ? .voiceChat : .default

        try session.setCategory(
            .playAndRecord,
            mode: mode,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )

        try session.setPreferredIOBufferDuration(0.010)
        try session.setPreferredSampleRate(16000)
        try session.setActive(true, options: [])

        Logger.audio.info(
            "Audio session configured: rate=\(session.sampleRate), mode=\(mode == .voiceChat ? "voiceChat" : "default"), speaker=\(session.currentRoute.outputs.first?.portType.rawValue ?? "?")"
        )
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            Logger.audio.info("Audio session deactivated")
        } catch {
            Logger.audio.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification Observers

    /// Register for audio session interruption and route change notifications.
    /// Call once at app launch.
    static func registerForNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleInterruption(notification)
        }

        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleRouteChange(notification)
        }

        Logger.audio.info("Registered for audio session interruption and route change notifications")
    }

    // MARK: - Interruption Handling

    private static func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            Logger.audio.warning("Audio session interruption BEGAN — releasing floor")
            onInterruptionBegan?()

        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                Logger.audio.info("Audio session interruption ENDED — shouldResume, reactivating")
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                onInterruptionEnded?()
            } else {
                Logger.audio.info("Audio session interruption ENDED — no shouldResume flag")
            }

        @unknown default:
            Logger.audio.warning("Unknown audio session interruption type: \(typeValue)")
        }
    }

    // MARK: - Route Change Handling

    private static func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        let session = AVAudioSession.sharedInstance()
        let currentOutput = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
        let currentInput = session.currentRoute.inputs.first?.portType.rawValue ?? "none"

        let reasonName: String
        switch reason {
        case .newDeviceAvailable:       reasonName = "newDeviceAvailable"
        case .oldDeviceUnavailable:     reasonName = "oldDeviceUnavailable"
        case .categoryChange:           reasonName = "categoryChange"
        case .override:                 reasonName = "override"
        case .wakeFromSleep:            reasonName = "wakeFromSleep"
        case .noSuitableRouteForCategory: reasonName = "noSuitableRouteForCategory"
        case .routeConfigurationChange: reasonName = "routeConfigurationChange"
        default:                        reasonName = "unknown(\(reasonValue))"
        }

        Logger.audio.info("Audio route changed: reason=\(reasonName), output=\(currentOutput), input=\(currentInput)")
    }
}

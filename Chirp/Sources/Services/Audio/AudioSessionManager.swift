import AVFoundation
import OSLog

enum AudioSessionManager {
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
}

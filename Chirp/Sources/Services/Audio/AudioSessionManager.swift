import AVFoundation
import OSLog

enum AudioSessionManager {
    static func configure() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )

        try session.setPreferredIOBufferDuration(0.010)
        try session.setPreferredSampleRate(Constants.Opus.sampleRate)
        try session.setActive(true, options: [])

        Logger.audio.info(
            "Audio session configured: sampleRate=\(session.sampleRate), ioBuffer=\(session.ioBufferDuration)"
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

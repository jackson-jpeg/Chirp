import AVFoundation
import OSLog

/// Simple AVAudioRecorder wrapper for voice note recording in chat.
/// Records compressed AAC audio suitable for mesh transmission.
@MainActor
final class VoiceNoteRecorder {

    private var recorder: AVAudioRecorder?
    private let fileURL: URL
    private let logger = Logger(subsystem: Constants.subsystem, category: "VoiceNote")

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        fileURL = tempDir.appendingPathComponent("chirp_voicenote_\(UUID().uuidString).m4a")
    }

    /// Start recording audio. Returns `false` if recording could not be started.
    @discardableResult
    func startRecording() -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32_000
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record()
            logger.info("Voice note recording started")
            return true
        } catch {
            logger.error("Failed to start voice note recording: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Stop recording and return the audio data. Returns `nil` if recording failed.
    func stopRecording() -> Data? {
        recorder?.stop()
        recorder = nil

        defer { cleanup() }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.warning("Voice note file not found after recording")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            logger.info("Voice note recorded: \(data.count) bytes")
            return data
        } catch {
            logger.error("Failed to read voice note: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cancel recording without saving.
    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        cleanup()
        logger.info("Voice note recording cancelled")
    }

    private func cleanup() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

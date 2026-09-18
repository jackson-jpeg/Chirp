import Foundation
import Observation
import OSLog

/// Plays a stored Opus clip (a voice message) through the same decode and
/// jitter-buffer path live push-to-talk uses, at real-time pace.
///
/// The Voice Messages screen used to push every frame of a message into
/// ``AudioEngine/receiveAudioPacket(_:sequenceNumber:)`` in one loop. The
/// jitter buffer holds 300 ms and trims the oldest frames beyond that, so all
/// but the last fraction of a second was discarded and a message "played" as
/// a blip. Frames are now fed one per 20 ms, the rate they were captured at.
@Observable
@MainActor
final class VoiceClipPlayer {

    /// The clip currently playing, if any. Views bind play/stop state to it.
    private(set) var playingID: UUID?

    /// 0...1 through the current clip.
    private(set) var progress: Double = 0

    private let audioEngine: AudioEngine
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: Constants.subsystem, category: "VoiceClipPlayer")

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    func isPlaying(_ id: UUID) -> Bool { playingID == id }

    /// Start `frames` from the beginning, replacing anything already playing.
    func play(id: UUID, frames: [Data]) {
        stop()
        guard !frames.isEmpty else { return }

        // A new clip starts at sequence 0. The buffer remembers the last
        // sequence it played and drops anything at or below it as late, so
        // without a reset a second clip would be discarded frame by frame.
        audioEngine.resetJitterBuffer()
        playingID = id
        progress = 0
        logger.info("Playing clip \(id.uuidString, privacy: .public): \(frames.count) frames")

        let engine = audioEngine
        let frameInterval = Constants.Opus.frameDuration
        task = Task { [weak self] in
            let start = ContinuousClock.now
            for (index, frame) in frames.enumerated() {
                if Task.isCancelled { return }
                engine.receiveAudioPacket(frame, sequenceNumber: UInt32(index))
                self?.progress = Double(index + 1) / Double(frames.count)
                let due = start + .milliseconds(Int(Double(index + 1) * frameInterval * 1000))
                try? await Task.sleep(until: due, clock: .continuous)
            }
            // Let the jitter buffer's playout depth drain before calling it done.
            try? await Task.sleep(for: .milliseconds(Constants.JitterBuffer.initialDepthMs + 60))
            guard !Task.isCancelled, let self, self.playingID == id else { return }
            self.playingID = nil
            self.progress = 0
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        playingID = nil
        progress = 0
    }

    /// Split the app's stored voice-message format into Opus frames:
    /// `[count: UInt32 BE]` then `[length: UInt32 BE][packet]` per frame.
    nonisolated static func frames(fromStored data: Data) -> [Data]? {
        guard let count = data.readBigEndian(UInt32.self, at: 0) else { return nil }
        var offset = 4
        var frames: [Data] = []
        frames.reserveCapacity(min(Int(count), data.count / 4))
        for _ in 0..<count {
            guard let length = data.readBigEndian(UInt32.self, at: offset) else { return nil }
            offset += 4
            guard let frame = data.slice(at: offset, length: Int(length)) else { return nil }
            frames.append(Data(frame))
            offset += Int(length)
        }
        return frames
    }
}

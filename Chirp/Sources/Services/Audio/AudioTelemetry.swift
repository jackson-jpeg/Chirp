#if DEBUG
import AVFoundation
import Foundation
import OSLog
import Synchronization

/// Debug-only instrumentation for the device-test harness.
///
/// WHY THIS EXISTS
///
/// "Does the phone make a sound" cannot be asserted by a machine. What *can* be
/// asserted is that the audio path carried a signal: this records an RMS
/// envelope at both ends — what the microphone captured, and what was handed to
/// the player node — timestamped in absolute time so that the envelope recorded
/// on the SENDING phone can be compared against the envelope recorded on the
/// RECEIVING phone. Silence produces a flat envelope; garbled or dropped audio
/// produces one that does not track the sender's. Both fail.
///
/// This deliberately does not decide anything. It records numbers; the harness
/// on the Mac decides, because the decision needs both phones' data and because
/// assertion logic that lives off-device can be tested without a device.
///
/// WHAT KEEPS IT OUT OF THE PRODUCT
///
///   1. The whole file is inside `#if DEBUG` — it does not exist in a Release
///      build, so it cannot ship even by accident.
///   2. Even in Debug it is inert unless the process was launched with
///      `-ChirpAudioTelemetry YES`, which only the harness passes.
///
/// CONCURRENCY
///
/// Written from the audio processing queue and the playback timer queue, read
/// from whichever thread flushes. State is held in a `Mutex` rather than behind
/// an `@unchecked Sendable` annotation: a `final class` whose stored properties
/// are all `let` and Sendable conforms to `Sendable` on its own terms, with the
/// compiler checking rather than being told.
final class AudioTelemetry: Sendable {

    static let shared = AudioTelemetry()

    struct Sample: Codable, Equatable {
        /// Absolute unix time. Absolute, not relative to launch, because these
        /// files are compared ACROSS devices and the two apps do not start
        /// together. Both phones are NTP-synced; the harness tolerates the
        /// residual skew by searching for the best alignment rather than
        /// assuming zero.
        let t: Double
        let rms: Float
    }

    struct Marker: Codable, Equatable {
        let t: Double
        let name: String
    }

    private struct Report: Codable {
        let role: String
        let startedAt: Double
        let capture: [Sample]
        let playback: [Sample]
        let markers: [Marker]
        let truncated: Bool
    }

    private struct State {
        var capture: [Sample] = []
        var playback: [Sample] = []
        var markers: [Marker] = []
        var samplesSinceFlush = 0
        var truncated = false
    }

    /// A bound on memory, not on the test. At ~50 samples/second per channel
    /// this is over twenty minutes of continuous audio, far longer than any
    /// scripted run. If it is ever hit the report says so rather than silently
    /// presenting a clipped envelope as a complete one.
    private static let maxSamplesPerChannel = 65_536

    /// Flushing every N samples rather than on a timer: no extra timer to
    /// interact with the audio path, and the file on disk is never more than a
    /// couple of seconds stale, so a crashed or killed app still yields data.
    private static let flushInterval = 128

    let isEnabled: Bool
    private let role: String
    private let startedAt: Double
    private let fileURL: URL
    private let state = Mutex(State())

    private init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: "ChirpAudioTelemetry")
        self.role = defaults.string(forKey: "ChirpRole") ?? "unknown"
        self.startedAt = Date().timeIntervalSince1970
        self.fileURL = URL.documentsDirectory.appending(path: "audio-telemetry.json")
    }

    // MARK: - Recording

    func recordCapture(rms: Float) {
        guard isEnabled else { return }
        append(Sample(t: Date().timeIntervalSince1970, rms: rms), to: \.capture)
    }

    func recordPlayback(rms: Float) {
        guard isEnabled else { return }
        append(Sample(t: Date().timeIntervalSince1970, rms: rms), to: \.playback)
    }

    /// A named point in time — "capture-start", "backgrounded", "ptt-press".
    /// Markers are what let the harness say *which* part of the run failed
    /// instead of only that the run failed.
    func mark(_ name: String) {
        guard isEnabled else { return }
        let marker = Marker(t: Date().timeIntervalSince1970, name: name)
        let snapshot: Report? = state.withLock { state in
            state.markers.append(marker)
            return self.report(from: state)
        }
        // Markers are rare and delimit the interesting regions, so flushing on
        // every one costs nothing and means an interrupted run still has its
        // structure on disk.
        write(snapshot)
    }

    private func append(_ sample: Sample, to channel: WritableKeyPath<State, [Sample]>) {
        let snapshot: Report? = state.withLock { state in
            guard state[keyPath: channel].count < Self.maxSamplesPerChannel else {
                state.truncated = true
                return nil
            }
            state[keyPath: channel].append(sample)
            state.samplesSinceFlush += 1
            guard state.samplesSinceFlush >= Self.flushInterval else { return nil }
            state.samplesSinceFlush = 0
            return self.report(from: state)
        }
        write(snapshot)
    }

    private func report(from state: State) -> Report {
        Report(
            role: role,
            startedAt: startedAt,
            capture: state.capture,
            playback: state.playback,
            markers: state.markers,
            truncated: state.truncated
        )
    }

    // MARK: - Output

    /// Force the current state to disk. Called at the end of a scripted run.
    func flush() {
        guard isEnabled else { return }
        write(state.withLock { report(from: $0) })
    }

    private func write(_ report: Report?) {
        guard let report else { return }
        // Not `try?`: a telemetry file that silently fails to write would make
        // a broken harness look like a broken app, which is precisely the
        // failure mode this whole exercise exists to remove. There is nothing
        // to recover here, so it reports and continues.
        do {
            let data = try JSONEncoder().encode(report)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.audio.error("AudioTelemetry write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// RMS of the first channel of a float buffer. Matches the calculation used
    /// on the capture side so the two envelopes are directly comparable.
    static func rms(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return nil
        }
        let samples = channelData[0]
        let count = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for i in 0..<count {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }
        return (sumOfSquares / Float(count)).squareRoot()
    }
}
#endif

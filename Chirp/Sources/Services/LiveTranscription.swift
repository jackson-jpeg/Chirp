@preconcurrency import Speech
import AVFoundation
import Foundation
import Observation
import OSLog

/// On-device live speech transcription for PTT audio.
/// Shows real-time captions when someone is speaking — essential for noisy
/// environments, hearing-impaired users, and searchable message history.
@Observable
@MainActor
final class LiveTranscription {
    private let logger = Logger(subsystem: Constants.subsystem, category: "Transcription")

    // MARK: - Public State

    /// The live, partial transcript being built as speech arrives.
    private(set) var currentTranscript: String = ""

    /// Whether we are actively transcribing incoming audio.
    private(set) var isTranscribing = false

    /// Whether on-device speech recognition is available on this device.
    private(set) var isAvailable = false

    /// Name of the peer currently being transcribed.
    private(set) var currentSpeaker: String = ""

    /// Chronological history of completed transcriptions.
    private(set) var history: [TranscriptEntry] = []

    // MARK: - Types

    struct TranscriptEntry: Identifiable, Sendable {
        let id: UUID
        let speakerName: String
        let text: String
        let timestamp: Date
        let duration: TimeInterval

        init(speakerName: String, text: String, timestamp: Date, duration: TimeInterval) {
            self.id = UUID()
            self.speakerName = speakerName
            self.text = text
            self.timestamp = timestamp
            self.duration = duration
        }
    }

    // MARK: - Private

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var availabilityDelegate: AvailabilityDelegate?
    private var transcriptionStartTime: Date?

    /// Maximum history entries kept in memory.
    private let maxHistoryCount = 50

    /// Audio format matching the decoded PCM output from OpusCodec (16 kHz mono Float32).
    /// We use Float32 because SFSpeechAudioBufferRecognitionRequest works best with it,
    /// and the AudioEngine already converts to Float32 for playback.
    private let transcriptionFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Constants.Opus.sampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Init

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        isAvailable = recognizer?.isAvailable ?? false

        // Watch for availability changes (e.g. locale changes, resource downloads)
        let delegate = AvailabilityDelegate { [weak self] available in
            Task { @MainActor [weak self] in
                self?.isAvailable = available
            }
        }
        self.availabilityDelegate = delegate
        recognizer?.delegate = delegate
    }

    // MARK: - Authorization

    /// Request speech recognition authorization from the user.
    /// Returns `true` if authorized.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authorized = status == .authorized
                continuation.resume(returning: authorized)
            }
        }
    }

    // MARK: - Transcription Lifecycle

    /// Start transcribing incoming audio buffers from a speaker.
    /// Call `feedAudioBuffer(_:)` to provide decoded PCM audio, then
    /// `stopTranscribing()` when the speaker releases PTT.
    func startTranscribing(speakerName: String) {
        guard isAvailable else {
            logger.warning("Speech recognition not available")
            return
        }

        // Tear down any in-flight session
        cancelCurrentTask()

        currentSpeaker = speakerName
        currentTranscript = ""
        transcriptionStartTime = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // Limit task to dictation style for better PTT results
        request.taskHint = .dictation

        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.finalizeTranscript()
                    }
                }

                if let error {
                    // Code 1 = "no speech detected" — not a real error
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1 {
                        self.logger.debug("No speech detected for \(speakerName)")
                    } else {
                        self.logger.error("Recognition error: \(error.localizedDescription)")
                    }
                    self.isTranscribing = false
                }
            }
        }

        isTranscribing = true
        logger.info("Started transcribing for '\(speakerName)'")
    }

    /// Feed a decoded PCM audio buffer for transcription.
    /// The buffer should be Float32, 16 kHz, mono — matching the playback format
    /// produced by AudioEngine.receiveAudioPacket.
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isTranscribing, let recognitionRequest else { return }
        recognitionRequest.append(buffer)
    }

    /// Feed raw Int16 PCM data (from OpusCodec.decode) by converting to Float32 first.
    func feedInt16Buffer(_ buffer: AVAudioPCMBuffer) {
        guard isTranscribing, let recognitionRequest else { return }

        // Convert Int16 -> Float32 for the speech recognizer
        guard let floatBuffer = AVAudioPCMBuffer(
            pcmFormat: transcriptionFormat,
            frameCapacity: buffer.frameLength
        ) else { return }

        floatBuffer.frameLength = buffer.frameLength

        if let int16Data = buffer.int16ChannelData,
           let floatData = floatBuffer.floatChannelData {
            for i in 0..<Int(buffer.frameLength) {
                floatData[0][i] = Float(int16Data[0][i]) / Float(Int16.max)
            }
        }

        recognitionRequest.append(floatBuffer)
    }

    /// Stop transcribing and finalize the current transcript entry.
    func stopTranscribing() {
        guard isTranscribing else { return }

        // Signal end of audio — the recognizer will produce a final result
        recognitionRequest?.endAudio()

        // If we already have text, finalize immediately (the final callback
        // may still fire and update, but we want responsive UI)
        if !currentTranscript.isEmpty {
            finalizeTranscript()
        }

        isTranscribing = false
        logger.info("Stopped transcribing for '\(self.currentSpeaker)'")
    }

    /// Clear all transcript history.
    func clearHistory() {
        history.removeAll()
    }

    // MARK: - Private

    private func finalizeTranscript() {
        let text = currentTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let startTime = transcriptionStartTime ?? Date()
        let duration = Date().timeIntervalSince(startTime)

        let entry = TranscriptEntry(
            speakerName: currentSpeaker,
            text: text,
            timestamp: startTime,
            duration: duration
        )

        history.append(entry)

        // Trim to max history size
        if history.count > maxHistoryCount {
            history.removeFirst(history.count - maxHistoryCount)
        }

        logger.info("Transcript saved: '\(text.prefix(60))...' from \(self.currentSpeaker) (\(String(format: "%.1f", duration))s)")
    }

    private func cancelCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

// MARK: - SFSpeechRecognizerDelegate Bridge

/// Lightweight delegate to forward availability changes back to the @Observable class.
private final class AvailabilityDelegate: NSObject, SFSpeechRecognizerDelegate, Sendable {
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        onChange(available)
    }
}

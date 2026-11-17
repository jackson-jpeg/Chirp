import AVFoundation
import ChirpCore
import Observation
import Speech

/// Live captions (scope 2), the app's side of ChirpCore's `Captions`.
///
/// - The speech permission is asked only from `send(.tappedCaptions)` or
///   `send(.chose(...))`, both user taps (5.1.1(iv)). `init` and `refresh()`
///   read the status, which never prompts.
/// - Recognition runs on the phone only (`requiresOnDeviceRecognition`). With
///   no on-device recognizer for the language, captions are unavailable.
/// - The audio engine opens one `CaptionFeed` per speaker stream (the same
///   peer and epoch as its jitter buffer), appends decoded PCM to it from any
///   thread, and ends it when the stream ends. Your own voice goes the same
///   way while you hold to talk. Captions-only: the engine asks `playsAudio`.
@MainActor
@Observable
final class LiveCaptions {
    private(set) var settings: CaptionSettings
    private(set) var track = CaptionTrack()
    /// A line to show once, after a tap that could not turn captions on.
    var notice: String?

    @ObservationIgnored private var feeds: [CaptionTrack.Speaker: CaptionFeed] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let mode = defaults.string(forKey: "captionMode").flatMap(CaptionMode.init(rawValue:)) ?? .on
        settings = CaptionSettings(mode: mode, permission: Self.osPermission())
    }

    var card: CaptionCard { Captions.card(settings) }
    var playsAudio: Bool { Captions.playsAudio(settings) }

    func send(_ event: CaptionEvent) {
        let (next, effects) = Captions.reduce(settings, event)
        if next.mode != settings.mode { defaults.set(next.mode.rawValue, forKey: "captionMode") }
        settings = next
        if !Captions.captioning(settings) { endAll() }
        for effect in effects { run(effect) }
    }

    /// Read the status again (returning from Settings). Never prompts.
    func refresh() { send(.permissionChecked(Self.osPermission())) }

    private func run(_ effect: CaptionEffect) {
        switch effect {
        case .requestPermission:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in self?.send(.permissionAnswered(granted: status == .authorized)) }
            }
        case .explainDenied:
            notice = "Captions need Speech Recognition. Turn it on for ChirpChirps in Settings."
        case .explainUnavailable:
            notice = "Captions are not available for your language on this phone yet."
        }
    }

    private static func osPermission() -> SpeechPermission {
        guard let r = SFSpeechRecognizer(), r.supportsOnDeviceRecognition else { return .unavailable }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    // MARK: Streams

    /// Starts captioning one speaker stream; nil when captions are off or not
    /// allowed. The feed is safe to append to from the audio thread.
    func begin(_ speaker: CaptionTrack.Speaker, format: AVAudioFormat) -> CaptionFeed? {
        guard Captions.captioning(settings), let recognizer = SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else { return nil }
        feeds[speaker]?.end()
        let feed = CaptionFeed(recognizer: recognizer, format: format) { [weak self] text, final in
            Task { @MainActor in self?.received(speaker, text: text, final: final) }
        }
        feeds[speaker] = feed
        return feed
    }

    func end(_ speaker: CaptionTrack.Speaker) {
        feeds.removeValue(forKey: speaker)?.end()
    }

    private func endAll() {
        for feed in feeds.values { feed.end() }
        feeds.removeAll()
    }

    private func received(_ speaker: CaptionTrack.Speaker, text: String, final: Bool) {
        track.update(speaker, text: text, final: final, at: .now)
        if final { feeds.removeValue(forKey: speaker) }
    }
}

/// One recognition request for one speaker stream, on the phone only.
final class CaptionFeed: @unchecked Sendable {
    let format: AVAudioFormat
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer, format: AVAudioFormat,
         onResult: @escaping @Sendable (String, Bool) -> Void) {
        self.format = format
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            } else if error != nil {
                onResult("", true)
            }
        }
    }

    /// Appends decoded audio in `format`. Callable from any thread.
    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }

    /// No more audio: the recognizer sends its final result.
    func end() { request.endAudio() }
}

@preconcurrency import Speech
import AVFoundation
import Foundation
import NaturalLanguage
import Observation
import OSLog
#if canImport(Translation)
import Translation
#endif

/// Real-time speech translation service for the ChirpChirp mesh.
///
/// Chains four stages into a live pipeline:
///   1. **Speech-to-Text** — on-device `SFSpeechRecognizer` transcribes local mic audio
///   2. **Translation** — iOS 18+ `TranslationSession` converts text to the target language
///   3. **Mesh transport** — translated text sent as `BBL!` packets via `onSendPacket`
///   4. **Text-to-Speech** — `AVSpeechSynthesizer` speaks received translations aloud
@Observable
@MainActor
final class BabelService {
    private let logger = Logger(subsystem: Constants.subsystem, category: "Babel")

    // MARK: - Public State

    /// The currently active translation session, if any.
    private(set) var activeSession: BabelSession?

    /// Incoming translations from other mesh peers (ring buffer, last 100).
    private(set) var receivedTranslations: [BabelMessage] = []

    /// Whether the translation pipeline is actively processing.
    private(set) var isTranslating = false

    /// Whether local speech recognition is actively listening.
    private(set) var isListening = false

    /// Toggle for automatic TTS playback of received translations.
    var autoSpeak = true

    /// Live partial result from the speech recognizer.
    private(set) var currentPartialText: String = ""

    /// Languages available from the Translation framework.
    private(set) var availableLanguages: [String] = []

    /// User's preferred language for receiving translations.
    /// Stored in UserDefaults, defaults to Locale.current.
    var preferredLanguage: String {
        get {
            UserDefaults.standard.string(forKey: "babel.preferredLanguage")
                ?? Locale.current.language.languageCode?.identifier ?? "en"
        }
        set { UserDefaults.standard.set(newValue, forKey: "babel.preferredLanguage") }
    }

    // MARK: - Translation Cache

    /// Cache of translated strings. Key = hash of originalText + sourceLang + targetLang.
    private var translationCache: [String: String] = [:]

    /// Build a cache key from the translation parameters.
    func cacheKey(text: String, from source: String, to target: String) -> String {
        "\(source)|\(target)|\(text)"
    }

    /// Test-only accessor for cache key generation.
    func testCacheKey(text: String, from source: String, to target: String) -> String {
        cacheKey(text: text, from: source, to: target)
    }

    // MARK: - Callbacks

    /// Called when a translated packet is ready to send over the mesh.
    /// Parameters: (payload data, channel ID)
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private — Speech Recognition

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var availabilityDelegate: AvailabilityDelegate?

    // MARK: - Private — Translation

    #if canImport(Translation)
    private var translationSession: TranslationSession?
    #endif

    // MARK: - Private — TTS

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Private — Session Context

    private var channelID: String = ""
    private var senderID: String = ""
    private var senderName: String = ""

    /// Debounce tracker for partial-result translations.
    private var lastPartialTranslation: Date = .distantPast

    /// Maximum received translations kept in memory.
    private let maxReceivedCount = 100

    /// Audio format for feeding the speech recognizer (16 kHz mono Float32).
    private let recognitionFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Constants.Opus.sampleRate,
        channels: 1,
        interleaved: false
    )

    // MARK: - Init

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)

        let delegate = AvailabilityDelegate { [weak self] available in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.info("Speech recognizer availability changed: \(available)")
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

    // MARK: - Session Lifecycle

    /// Start a new translation session with the given language pair.
    ///
    /// - Parameters:
    ///   - sourceLanguage: BCP-47 code for the local speaker's language (e.g., "en-US")
    ///   - targetLanguage: BCP-47 code for the translation target (e.g., "es")
    ///   - channelID: Mesh channel to send translations on
    ///   - senderID: Local peer identifier
    ///   - senderName: Local peer display name
    func startSession(
        sourceLanguage: String,
        targetLanguage: String,
        channelID: String,
        senderID: String,
        senderName: String
    ) async throws {
        // Tear down any existing session
        stopSession()

        self.channelID = channelID
        self.senderID = senderID
        self.senderName = senderName

        // Configure speech recognizer for source language
        let locale = Locale(identifier: sourceLanguage)
        recognizer = SFSpeechRecognizer(locale: locale)
        recognizer?.delegate = availabilityDelegate

        guard recognizer?.isAvailable == true else {
            logger.error("Speech recognizer not available for locale: \(sourceLanguage)")
            throw BabelError.speechRecognizerUnavailable
        }

        // Configure translation session (non-fatal — falls back to original text)
        #if canImport(Translation)
        do {
            try await configureTranslation(source: sourceLanguage, target: targetLanguage)
        } catch {
            logger.warning("Translation session setup failed, will send original text: \(error.localizedDescription)")
        }
        #endif

        let session = BabelSession(
            id: UUID(),
            sourceLanguageCode: sourceLanguage,
            targetLanguageCode: targetLanguage,
            isActive: true
        )
        activeSession = session

        // Start speech recognition
        startListening()

        isTranslating = true
        logger.info("Babel session started: \(sourceLanguage) -> \(targetLanguage)")
    }

    /// Stop the current translation session and tear down all resources.
    func stopSession() {
        stopListening()

        #if canImport(Translation)
        translationSession = nil
        #endif

        synthesizer.stopSpeaking(at: .immediate)

        activeSession = nil
        isTranslating = false
        currentPartialText = ""

        logger.info("Babel session stopped")
    }

    // MARK: - Audio Input

    /// Feed a local microphone audio buffer into the speech recognizer.
    ///
    /// Called by AudioEngine when the user is transmitting in Babel mode.
    /// Buffer should be Float32, 16 kHz, mono.
    func feedLocalAudio(buffer: AVAudioPCMBuffer) {
        guard isListening, let recognitionRequest else { return }
        recognitionRequest.append(buffer)
    }

    // MARK: - Incoming Packets

    /// Handle an incoming mesh packet that may contain a Babel translation.
    ///
    /// Decodes the `BBL!` payload, appends to `receivedTranslations`, and
    /// optionally speaks the result via TTS.
    func handlePacket(_ data: Data, channelID: String) {
        guard let message = BabelMessage.from(payload: data) else { return }

        // Only process final translations for display and TTS
        guard message.isFinal else {
            logger.debug("Received partial Babel message, skipping")
            return
        }

        receivedTranslations.append(message)

        // Trim ring buffer
        if receivedTranslations.count > maxReceivedCount {
            receivedTranslations.removeFirst(receivedTranslations.count - maxReceivedCount)
        }

        logger.info("Received Babel from \(message.senderName): \(message.displayText.prefix(60))")

        if autoSpeak {
            speak(message.displayText, language: message.targetLanguage.isEmpty ? preferredLanguage : message.targetLanguage)
        }
    }

    // MARK: - Private — Speech Recognition

    private func startListening() {
        guard recognizer?.isAvailable == true else {
            logger.warning("Speech recognizer not available — cannot start listening")
            return
        }

        cancelRecognitionTask()

        currentPartialText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation

        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handleRecognitionResult(result, error: error)
            }
        }

        isListening = true
        logger.info("Babel speech recognition started")
    }

    private func stopListening() {
        recognitionRequest?.endAudio()
        cancelRecognitionTask()
        isListening = false
    }

    private func cancelRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            currentPartialText = text

            if result.isFinal {
                // Final result — translate and send
                let finalText = text
                currentPartialText = ""
                Task { @MainActor in
                    await translateAndSend(text: finalText, isFinal: true)
                }
            } else {
                // Partial result — translate for preview but don't send over mesh
                // Throttle: only translate partials every 0.3s to avoid starving the main thread
                if Date().timeIntervalSince(lastPartialTranslation) >= 0.3 {
                    lastPartialTranslation = Date()
                    let partialText = text
                    Task { @MainActor in
                        await translateAndSend(text: partialText, isFinal: false)
                    }
                }
            }
        }

        if let error {
            let nsError = error as NSError
            // Code 1 = "no speech detected" — not a real error
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1 {
                logger.debug("Babel: No speech detected")
            } else if nsError.code == 216 {
                // Recognition task was cancelled — expected during teardown
                logger.debug("Babel: Recognition task cancelled")
            } else {
                logger.error("Babel recognition error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Language Detection

    /// Detect the dominant language of text using NLLanguageRecognizer.
    /// Returns a BCP-47 language code, or nil if detection fails.
    func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }
        return lang.rawValue
    }

    // MARK: - Reusable Translation

    /// Translate text using the active session, with caching.
    /// Requires startSession() to have been called first.
    func translateText(_ text: String, from source: String, to target: String) async -> String? {
        let key = cacheKey(text: text, from: source, to: target)
        if let cached = translationCache[key] {
            return cached
        }
        guard activeSession != nil else { return nil }
        do {
            let result = try await translate(text)
            translationCache[key] = result
            return result
        } catch {
            logger.error("Translation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private — Translation (Session-based)

    #if canImport(Translation)
    private func configureTranslation(source: String, target: String) async throws {
        let sourceLang = Locale.Language(identifier: source)
        let targetLang = Locale.Language(identifier: target)

        translationSession = try await TranslationSession(
            installedSource: sourceLang,
            target: targetLang
        )
        logger.info("Translation session configured: \(source) -> \(target)")
    }
    #endif

    private func translate(_ text: String) async throws -> String {
        #if canImport(Translation)
        guard let session = translationSession else {
            throw BabelError.translationSessionNotConfigured
        }
        // TranslationSession is not Sendable but is safe to use across async boundaries
        // since we only access it from @MainActor.
        nonisolated(unsafe) let s = session
        let response = try await s.translate(text)
        return response.targetText
        #else
        logger.warning("Translation framework not available, returning original text")
        return text
        #endif
    }

    private func translateAndSend(text: String, isFinal: Bool) async {
        guard let session = activeSession, session.isActive else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Detect source language
        let detectedLang = detectLanguage(text) ?? session.sourceLanguageCode

        // Translate on sender side using the active session
        var translated: String? = nil
        do {
            translated = try await translate(text)
        } catch {
            logger.warning("Translation failed, sending original: \(error.localizedDescription)")
        }

        let message = BabelMessage(
            id: UUID(),
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            sourceLanguage: detectedLang,
            targetLanguage: session.targetLanguageCode,
            originalText: text,
            translatedText: translated,
            isFinal: isFinal,
            timestamp: Date()
        )

        if isFinal {
            if let payload = try? message.wirePayload() {
                onSendPacket?(payload, channelID)
                logger.info("Sent Babel: \(message.displayText.prefix(60))")
            }
        }
    }

    // MARK: - Private — Text-to-Speech

    /// Speak translated text aloud using AVSpeechSynthesizer.
    func speak(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    // MARK: - Errors

    enum BabelError: LocalizedError {
        case speechRecognizerUnavailable
        case unsupportedLanguagePair
        case translationSessionNotConfigured
        case translationTimeout

        var errorDescription: String? {
            switch self {
            case .speechRecognizerUnavailable:
                "Speech recognizer is not available for the selected language."
            case .unsupportedLanguagePair:
                "The selected language pair is not supported for translation."
            case .translationSessionNotConfigured:
                "Translation session has not been configured."
            case .translationTimeout:
                "Translation timed out after 5 seconds — the language model may not be downloaded."
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate Bridge

/// Lightweight delegate to forward availability changes back to the @Observable class.
private final class AvailabilityDelegate: NSObject, SFSpeechRecognizerDelegate, Sendable {
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        onChange(available)
    }
}

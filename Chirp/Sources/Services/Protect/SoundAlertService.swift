import AVFoundation
import Foundation
import Observation
import OSLog
import SoundAnalysis

/// Listens for emergency sounds (gunshots, screams, sirens, etc.) using Apple's
/// built-in sound classifier and broadcasts detections over the mesh network.
///
/// Only active when Emergency Mode is engaged. Feeds audio from the existing
/// `AudioEngine` tap via `feedAudio(buffer:time:)` -- no second tap is installed.
@Observable
@MainActor
final class SoundAlertService: NSObject {

    private let logger = Logger(subsystem: Constants.subsystem, category: "SoundAlert")

    // MARK: - Public State

    private(set) var isListening: Bool = false
    private(set) var recentAlerts: [SoundAlert] = []
    private(set) var meshAlerts: [SoundAlert] = []

    // MARK: - Callbacks

    /// Called when a local detection should be broadcast to the mesh.
    var onAlertBroadcast: ((Data) -> Void)?

    // MARK: - Dependencies

    private let locationService: LocationService
    private var senderID: String = ""
    private var senderName: String = ""

    // MARK: - SoundAnalysis (accessed only from analysisQueue)

    nonisolated(unsafe) private var analyzer: SNAudioStreamAnalyzer?
    nonisolated(unsafe) private var analysisRequest: SNClassifySoundRequest?
    nonisolated(unsafe) private var isListeningFlag: Bool = false

    private let analysisQueue = DispatchQueue(label: "com.chirpchirp.soundanalysis", qos: .userInitiated)

    // MARK: - Dedup / Confirmation Tracking

    private var lastClassifications: [String: (count: Int, lastTime: Date)] = [:]
    private var recentBroadcasts: [String: Date] = [:]

    private let confidenceThreshold: Double = 0.70
    /// Sound classes that need 2 consecutive detections within 3 seconds (high false positive rate).
    private let confirmationRequired: Set<String> = ["gunshot", "scream"]

    /// Apple classifier labels that map to our SoundClass cases.
    private let classifierLabelMap: [String: SoundAlert.SoundClass] = [
        "gunshot": .gunshot,
        "gunshot, gunfire": .gunshot,
        "machine_gun": .gunshot,
        "scream": .scream,
        "screaming": .scream,
        "shatter": .glassBreaking,
        "glass": .glassBreaking,
        "breaking": .glassBreaking,
        "fire_alarm": .fireAlarm,
        "smoke_detector": .smokeDetector,
        "smoke_detector, smoke_alarm": .smokeDetector,
        "siren": .siren,
        "civil_defense_siren": .siren,
        "ambulance_siren": .siren,
        "police_car_siren": .siren,
        "fire_engine_siren": .siren,
        "explosion": .explosion,
    ]

    // MARK: - Init

    init(locationService: LocationService) {
        self.locationService = locationService
        super.init()

        NotificationCenter.default.addObserver(
            forName: .emergencyModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let active = notification.userInfo?["active"] as? Bool else { return }
            Task { @MainActor [weak self] in
                if active {
                    self?.startListening()
                } else {
                    self?.stopListening()
                }
            }
        }
    }

    func configure(senderID: String, senderName: String) {
        self.senderID = senderID
        self.senderName = senderName
    }

    // MARK: - Lifecycle

    func startListening() {
        guard !isListening else { return }
        isListening = true
        isListeningFlag = true
        lastClassifications.removeAll()
        recentBroadcasts.removeAll()
        logger.info("Sound alert listening started")
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        isListeningFlag = false

        analysisQueue.async { [weak self] in
            if let request = self?.analysisRequest {
                self?.analyzer?.remove(request)
            }
            self?.analyzer = nil
            self?.analysisRequest = nil
        }

        lastClassifications.removeAll()
        recentBroadcasts.removeAll()
        logger.info("Sound alert listening stopped")
    }

    // MARK: - Audio Feed

    /// Called from AudioEngine's onRawAudioBuffer callback on the audio I/O thread.
    nonisolated func feedAudio(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard isListeningFlag else { return }

        nonisolated(unsafe) let buf = buffer
        let audioTime = time
        analysisQueue.async { [weak self] in
            guard let self else { return }
            guard self.isListeningFlag else { return }
            let buffer = buf; let time = audioTime

            // Lazy-create analyzer with the buffer's format on first call
            if self.analyzer == nil {
                let newAnalyzer = SNAudioStreamAnalyzer(format: buffer.format)
                do {
                    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                    request.windowDuration = CMTimeMakeWithSeconds(1.5, preferredTimescale: 48_000)
                    request.overlapFactor = 0.5
                    try newAnalyzer.add(request, withObserver: self)
                    self.analyzer = newAnalyzer
                    self.analysisRequest = request
                } catch {
                    let msg = error.localizedDescription
                    Task { @MainActor in
                        Logger(subsystem: Constants.subsystem, category: "SoundAlert")
                            .error("Failed to set up sound classifier: \(msg)")
                    }
                    return
                }
            }

            self.analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }

    // MARK: - Mesh Alert Handling

    /// Process an incoming sound alert payload received from the mesh.
    func handleMeshAlert(_ payload: Data) {
        guard let alert = SoundAlert.from(payload: payload) else { return }

        // Dedup: same sound class from same sender within 5 seconds
        if let existing = meshAlerts.first(where: {
            $0.senderID == alert.senderID
            && $0.soundClass == alert.soundClass
            && abs($0.timestamp.timeIntervalSince(alert.timestamp)) < 5.0
        }) {
            _ = existing
            return
        }

        meshAlerts.insert(alert, at: 0)
        if meshAlerts.count > 50 {
            meshAlerts = Array(meshAlerts.prefix(50))
        }

        logger.warning("Mesh sound alert: \(alert.soundClass.displayName) from \(alert.senderName, privacy: .public) (conf: \(String(format: "%.0f", alert.confidence * 100))%)")
    }

    // MARK: - Private: Process Classification Result

    private func processClassification(identifier: String, confidence: Double) {
        guard confidence >= confidenceThreshold else { return }

        // Map Apple classifier label to our sound class
        guard let soundClass = classifierLabelMap[identifier] else { return }

        let now = Date()
        let classKey = soundClass.rawValue

        // Confirmation logic for high-false-positive sounds
        if confirmationRequired.contains(classKey) {
            if let prev = lastClassifications[classKey],
               now.timeIntervalSince(prev.lastTime) < 3.0 {
                // Second detection within window
                lastClassifications[classKey] = (count: prev.count + 1, lastTime: now)
                if prev.count + 1 < 2 {
                    return // Need at least 2
                }
            } else {
                // First detection -- store and wait for confirmation
                lastClassifications[classKey] = (count: 1, lastTime: now)
                return
            }
        }

        // Dedup: don't broadcast same class within 5 seconds
        if let lastBroadcast = recentBroadcasts[classKey],
           now.timeIntervalSince(lastBroadcast) < 5.0 {
            return
        }
        recentBroadcasts[classKey] = now

        let location = locationService.currentLocation

        let alert = SoundAlert(
            id: UUID(),
            senderID: senderID,
            senderName: senderName,
            soundClass: soundClass,
            confidence: confidence,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            timestamp: now
        )

        // Store locally
        recentAlerts.insert(alert, at: 0)
        if recentAlerts.count > 50 {
            recentAlerts = Array(recentAlerts.prefix(50))
        }

        logger.warning("Sound detected: \(soundClass.displayName) (conf: \(String(format: "%.0f", confidence * 100))%)")

        // Broadcast to mesh
        if let payload = try? alert.wirePayload() {
            onAlertBroadcast?(payload)
        }
    }

    /// Clear all stored alerts.
    func clearAlerts() {
        recentAlerts.removeAll()
        meshAlerts.removeAll()
    }
}

// MARK: - SNResultsObserving

extension SoundAlertService: SNResultsObserving {

    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        // Find the top classification that matches one of our alert types
        for candidate in classification.classifications {
            let identifier = candidate.identifier.lowercased()
            let confidence = candidate.confidence

            Task { @MainActor [weak self] in
                self?.processClassification(identifier: identifier, confidence: confidence)
            }

            // Only process the top matching result
            if confidence >= confidenceThreshold {
                break
            }
        }
    }

    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in
            Logger(subsystem: Constants.subsystem, category: "SoundAlert")
                .error("Sound analysis failed: \(msg)")
        }
    }

    nonisolated func requestDidComplete(_ request: SNRequest) {
        Task { @MainActor in
            Logger(subsystem: Constants.subsystem, category: "SoundAlert")
                .info("Sound analysis request completed")
        }
    }
}

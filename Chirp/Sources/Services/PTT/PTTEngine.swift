import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class PTTEngine {

    // MARK: - Public State

    private(set) var state: PTTState = .idle

    /// When true, encoded audio is looped back to the decoder for playback.
    /// Lets you test the full audio pipeline on a single device.
    var loopbackMode: Bool = true

    // MARK: - Dependencies

    let audioEngine: AudioEngine
    let floorController: FloorController
    var multipeerTransport: MultipeerTransport?
    var wifiAwareTransport: WiFiAwareTransport?

    /// Provides the current peer list for transport preference decisions.
    var peerListProvider: (() -> [ChirpPeer])?

    /// Provides current Wi-Fi Aware link metrics for quality-aware transport selection.
    var wifiAwareMetricsProvider: (() -> [String: WALinkMetrics])?

    // MARK: - Private

    private let logger = Logger.ptt
    private let localPeerID: String
    private var sequenceNumber: UInt32 = 0
    nonisolated(unsafe) private var stateObservationTask: Task<Void, Never>?
    nonisolated(unsafe) private var heartbeatTask: Task<Void, Never>?

    // MARK: - Init

    init(
        audioEngine: AudioEngine,
        floorController: FloorController,
        localPeerID: String
    ) {
        self.audioEngine = audioEngine
        self.floorController = floorController
        self.localPeerID = localPeerID
    }

    deinit {
        stateObservationTask?.cancel()
        heartbeatTask?.cancel()
    }

    // MARK: - Setup

    /// Wire callbacks between subsystems.
    func setupCallbacks() {
        // Audio capture -> network: when the audio engine encodes a frame,
        // wrap it in an AudioPacket and send over the mesh transport.
        // The closure runs on the audio processing queue, so dispatch to
        // @MainActor for state access (sequence number, loopback mode).
        audioEngine.onEncodedAudio = { [weak self] opusData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seq = self.nextSequenceNumber()

                // Loopback: feed encoded audio back to decoder for local playback
                if self.loopbackMode {
                    self.audioEngine.receiveAudioPacket(opusData, sequenceNumber: seq)
                }

                let packet = AudioPacket(
                    sequenceNumber: seq,
                    timestamp: Self.currentTimestamp(),
                    opusData: opusData
                )
                // Send via preferred transport(s) — quality-aware for audio
                let serialized = packet.serialize()
                let peers = self.peerListProvider?() ?? []
                let metrics = self.wifiAwareMetricsProvider?()
                let choice = TransportPreference.preferredTransport(
                    for: .audio,
                    wifiAwareMetrics: metrics,
                    peers: peers
                )
                if TransportPreference.shouldSendOnMC(choice: choice) {
                    try? self.multipeerTransport?.sendAudio(serialized)
                }
                if TransportPreference.shouldSendOnWA(choice: choice) {
                    try? self.wifiAwareTransport?.sendAudio(serialized)
                }
            }
        }

        // Floor control -> network: broadcast control messages to all peers
        // via both transports for reliability (quality-aware: control always sends on both).
        floorController.sendToAllPeers = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let peers = self.peerListProvider?() ?? []
                let metrics = self.wifiAwareMetricsProvider?()
                let choice = TransportPreference.preferredTransport(
                    for: .control,
                    wifiAwareMetrics: metrics,
                    peers: peers
                )
                if TransportPreference.shouldSendOnMC(choice: choice) {
                    try? self.multipeerTransport?.sendControl(message)
                }
                if TransportPreference.shouldSendOnWA(choice: choice) {
                    try? self.wifiAwareTransport?.sendControl(message)
                }
            }
        }

        logger.info("PTTEngine callbacks wired")
    }

    // MARK: - Lifecycle

    /// Full startup sequence: configure audio and wire callbacks.
    /// Audio/control delivery is handled externally by AppState's meshRouter callback.
    func start() async throws {
        try audioEngine.setup()
        setupCallbacks()
        startHeartbeat()
        logger.info("PTTEngine started")
    }

    /// Tear down all tasks and the audio engine.
    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        stateObservationTask?.cancel()
        stateObservationTask = nil
        audioEngine.teardown()
        logger.info("PTTEngine stopped")
    }

    // MARK: - Transmit Controls

    /// Begin transmitting: request the floor and, if granted, start audio capture.
    func startTransmitting() {
        floorController.requestFloor()

        // Check if we got the floor (optimistic grant).
        guard floorController.state == .transmitting else {
            syncState()
            logger.info("Floor request was not granted")
            return
        }

        sequenceNumber = 0
        audioEngine.resetJitterBuffer()
        wifiAwareTransport?.setRealtimeMode(true)
        audioEngine.startCapture()
        syncState()
        logger.info("Transmitting -- audio capture started")
    }

    /// Stop transmitting: halt capture and release the floor.
    func stopTransmitting() {
        audioEngine.stopCapture()
        wifiAwareTransport?.setRealtimeMode(false)
        floorController.releaseFloor()
        syncState()
        logger.info("Stopped transmitting")
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                let heartbeat = FloorControlMessage.heartbeat(peerID: self.localPeerID, timestamp: Date())
                let peers = self.peerListProvider?() ?? []
                let metrics = self.wifiAwareMetricsProvider?()
                let choice = TransportPreference.preferredTransport(
                    for: .control,
                    wifiAwareMetrics: metrics,
                    peers: peers
                )
                if TransportPreference.shouldSendOnMC(choice: choice) {
                    try? self.multipeerTransport?.sendControl(heartbeat)
                }
                if TransportPreference.shouldSendOnWA(choice: choice) {
                    try? self.wifiAwareTransport?.sendControl(heartbeat)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func syncState() {
        state = floorController.state
    }

    private func nextSequenceNumber() -> UInt32 {
        let seq = sequenceNumber
        sequenceNumber &+= 1
        return seq
    }

    private static func currentTimestamp() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000) // milliseconds
    }
}

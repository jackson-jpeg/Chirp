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
    var loopbackMode: Bool = false

    // MARK: - Dependencies

    let audioEngine: AudioEngine
    let floorController: FloorController
    var multipeerTransport: MultipeerTransport?

    /// Provides the current peer list.
    var peerListProvider: (() -> [ChirpPeer])?

    // MARK: - Private

    private let logger = Logger.ptt
    private let localPeerID: String
    private var sequenceNumber: UInt32 = 0
    private var stateObservationTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var transmitTimeoutTask: Task<Void, Never>?

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

    // Cleanup is handled by stop(), called by AppState.stop().

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
                let serialized = packet.serialize()
                do {
                    try self.multipeerTransport?.sendAudio(serialized)
                } catch {
                    self.logger.error("Audio frame send failed (seq \(seq)): \(error.localizedDescription)")
                }
            }
        }

        // Floor control -> network: broadcast control messages to all peers.
        floorController.sendToAllPeers = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try self.multipeerTransport?.sendControl(message)
                } catch {
                    self.logger.error("Floor control send failed: \(error.localizedDescription)")
                }
            }
        }

        // Floor lost to a peer mid-transmission: close the microphone.
        //
        // Until now the only things that stopped capture were the user letting
        // go of the button, an audio interruption, the input device
        // disappearing, and the 120-second timeout. A peer winning the floor
        // was not one of them — so the floor controller would move to
        // `.receiving` and show someone else talking while this device's
        // microphone stayed open and kept sending audio frames.
        floorController.onFloorRevoked = { [weak self] in
            guard let self, self.state == .transmitting else { return }
            self.logger.warning("Floor revoked by a peer — stopping transmission")
            self.stopTransmitting()
        }

        // Audio session interruption: auto-release floor
        AudioSessionManager.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .transmitting else { return }
                self.logger.warning("Audio interruption began — stopping transmission")
                self.stopTransmitting()
            }
        }

        // Audio session resumed: restart engine if iOS killed it
        AudioSessionManager.onInterruptionEnded = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioEngine.restartEngineIfNeeded()
                self.logger.info("Audio interruption ended — engine verified")
            }
        }

        // Bluetooth/headset disconnected mid-transmit: stop capture, release floor
        AudioSessionManager.onInputDeviceLost = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.state == .transmitting else { return }
                self.logger.warning("Input device lost — stopping transmission")
                self.stopTransmitting()
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

        audioEngine.resetJitterBuffer()
        audioEngine.startCapture()

        // SAFETY NET, not a mechanism. Every ordinary way of stopping —
        // releasing the button, losing the floor to a peer, an interruption,
        // the input device disappearing — cancels this before it fires. If it
        // ever does fire, something above it failed and the device has been
        // holding an open microphone for two minutes. Treat a hit here as a
        // defect report, not as the design working.
        transmitTimeoutTask?.cancel()
        transmitTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self else { return }
            self.logger.error("Transmit timeout fired after 120s — nothing else stopped this transmission")
            self.stopTransmitting()
        }

        syncState()
        logger.info("Transmitting -- audio capture started")
    }

    /// Stop transmitting: halt capture and release the floor.
    func stopTransmitting() {
        transmitTimeoutTask?.cancel()
        transmitTimeoutTask = nil
        audioEngine.stopCapture()
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
                do {
                    try self.multipeerTransport?.sendControl(heartbeat)
                } catch {
                    self.logger.error("Heartbeat send failed: \(error.localizedDescription)")
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

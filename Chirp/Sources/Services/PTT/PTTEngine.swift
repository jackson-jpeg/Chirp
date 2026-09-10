import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class PTTEngine {

    // MARK: - Public State

    /// Projected from the floor session — the one source of truth. The old
    /// design kept a copy here and re-synced it by hand at each call site,
    /// which is how the copy and the floor came to disagree (stuck-button bug).
    var state: PTTState { floorSession.state }

    /// When true, encoded audio is looped back to the decoder for playback.
    /// Lets you test the full audio pipeline on a single device.
    var loopbackMode: Bool = false

    // MARK: - Dependencies

    let audioEngine: AudioEngine
    let floorSession: FloorSession
    /// Named for its production conformer; typed as the protocol so the
    /// loopback tests can join engines with an in-memory transport.
    var multipeerTransport: (any PTTTransport)?

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
        floorSession: FloorSession,
        localPeerID: String
    ) {
        self.audioEngine = audioEngine
        self.floorSession = floorSession
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
                    try self.multipeerTransport?.sendAudio(serialized, channelID: nil)
                } catch {
                    self.logger.error("Audio frame send failed (seq \(seq)): \(error.localizedDescription)")
                }
            }
        }

        // Floor control -> network: broadcast control messages to all peers.
        floorSession.sendToAllPeers = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try self.multipeerTransport?.sendControl(message, channelID: nil)
                } catch {
                    self.logger.error("Floor control send failed: \(error.localizedDescription)")
                }
            }
        }

        // The machine's verdict on capture. Every transition that grants this
        // device the floor opens the microphone here, and every transition
        // that takes it away — button release, losing a collision, the holder
        // being forcibly released — closes it here. There is no other path,
        // which is the point: the old design closed the microphone from one
        // hand-wired callback on one transition out of five, and the other
        // four were the stuck-microphone bugs.
        floorSession.onOpenMicrophone = { [weak self] in
            guard let self else { return }
            self.audioEngine.resetJitterBuffer()
            self.audioEngine.startCapture()
            self.armTransmitWatchdog()
        }
        floorSession.onCloseMicrophone = { [weak self] in
            guard let self else { return }
            self.transmitTimeoutTask?.cancel()
            self.transmitTimeoutTask = nil
            self.audioEngine.stopCapture()
        }

        // Audio session interruption: auto-release floor.
        // Guarded on the machine's microphone flag, not the projected UI state:
        // a refusal overlay (double press) must not make this device deaf to
        // an interruption while the microphone underneath is still open.
        AudioSessionManager.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.floorSession.floorState.microphoneIsOpen else { return }
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
                guard let self, self.floorSession.floorState.microphoneIsOpen else { return }
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

    /// Begin transmitting: request the floor. If the machine grants it,
    /// capture starts through the `onOpenMicrophone` effect it returns.
    func startTransmitting() {
        floorSession.requestFloor()
        if state == .transmitting {
            logger.info("Transmitting -- audio capture started")
        } else {
            logger.info("Floor request was not granted")
        }
    }

    /// Stop transmitting: release the floor. Capture stops through the
    /// `onCloseMicrophone` effect the machine returns.
    func stopTransmitting() {
        floorSession.releaseFloor()
        logger.info("Stopped transmitting")
    }

    /// SAFETY NET, not a mechanism. Every ordinary way of stopping —
    /// releasing the button, losing the floor to a peer, an interruption,
    /// the input device disappearing — closes the microphone and cancels
    /// this before it fires. If it ever does fire, something above it failed
    /// and the device has been holding an open microphone for two minutes.
    /// Treat a hit here as a defect report, not as the design working.
    private func armTransmitWatchdog() {
        transmitTimeoutTask?.cancel()
        transmitTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self else { return }
            self.logger.error("Transmit timeout fired after 120s — nothing else stopped this transmission")
            self.stopTransmitting()
        }
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
                    try self.multipeerTransport?.sendControl(heartbeat, channelID: nil)
                } catch {
                    self.logger.error("Heartbeat send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func nextSequenceNumber() -> UInt32 {
        let seq = sequenceNumber
        sequenceNumber &+= 1
        return seq
    }

    private static func currentTimestamp() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000) // milliseconds
    }
}

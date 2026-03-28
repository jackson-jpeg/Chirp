import Foundation
import Observation
import OSLog

@Observable
final class PTTEngine: @unchecked Sendable {

    // MARK: - Public State

    private(set) var state: PTTState = .idle

    /// When true, encoded audio is looped back to the decoder for playback.
    /// Lets you test the full audio pipeline on a single device.
    var loopbackMode: Bool = true

    // MARK: - Dependencies

    let audioEngine: AudioEngine
    let floorController: FloorController
    let connectionManager: ConnectionManager
    var multipeerTransport: MultipeerTransport?

    // MARK: - Private

    private let logger = Logger.ptt
    private var sequenceNumber: UInt32 = 0
    private var audioReceiveTask: Task<Void, Never>?
    private var controlReceiveTask: Task<Void, Never>?
    private var stateObservationTask: Task<Void, Never>?

    // MARK: - Init

    init(
        audioEngine: AudioEngine,
        floorController: FloorController,
        connectionManager: ConnectionManager
    ) {
        self.audioEngine = audioEngine
        self.floorController = floorController
        self.connectionManager = connectionManager
    }

    deinit {
        audioReceiveTask?.cancel()
        controlReceiveTask?.cancel()
        stateObservationTask?.cancel()
    }

    // MARK: - Setup

    /// Wire callbacks between subsystems.
    func setupCallbacks() {
        // Audio capture -> network: when the audio engine encodes a frame,
        // wrap it in an AudioPacket and send over the transport.
        audioEngine.onEncodedAudio = { [weak self] opusData in
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
            // Send via MultipeerConnectivity
            try? self.multipeerTransport?.sendAudio(packet.serialize())
            // Also send via Wi-Fi Aware ConnectionManager
            Task {
                try? await self.connectionManager.sendAudio(packet.serialize())
            }
        }

        // Floor control -> network: broadcast control messages to all peers.
        floorController.sendToAllPeers = { [weak self] message in
            guard let self else { return }
            // Send via MultipeerConnectivity
            try? self.multipeerTransport?.sendControl(message)
            // Also send via Wi-Fi Aware
            Task {
                do {
                    try await self.connectionManager.sendControl(message)
                } catch {
                    Logger.network.error("Failed to send control message: \(error.localizedDescription)")
                }
            }
        }

        logger.info("PTTEngine callbacks wired")
    }

    // MARK: - Lifecycle

    /// Full startup sequence: configure audio, wire callbacks, start receive loops.
    func start() async throws {
        try audioEngine.setup()
        setupCallbacks()
        await startReceiving()
        logger.info("PTTEngine started")
    }

    /// Tear down all tasks and the audio engine.
    func stop() {
        audioReceiveTask?.cancel()
        controlReceiveTask?.cancel()
        stateObservationTask?.cancel()
        audioReceiveTask = nil
        controlReceiveTask = nil
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
        audioEngine.startCapture()
        syncState()
        logger.info("Transmitting — audio capture started")
    }

    /// Stop transmitting: halt capture and release the floor.
    func stopTransmitting() {
        audioEngine.stopCapture()
        floorController.releaseFloor()
        syncState()
        logger.info("Stopped transmitting")
    }

    // MARK: - Receive Loops

    /// Spawn two long-lived tasks: one for incoming audio packets and one for
    /// control messages from the transport layer.
    func startReceiving() async {
        // Cancel any existing tasks before creating new ones.
        audioReceiveTask?.cancel()
        controlReceiveTask?.cancel()

        audioReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.connectionManager.audioPackets
            for await data in stream {
                guard !Task.isCancelled else { break }
                guard let packet = AudioPacket.deserialize(data) else {
                    Logger.audio.warning("Failed to deserialize audio packet (\(data.count) bytes)")
                    continue
                }
                self.audioEngine.receiveAudioPacket(
                    packet.opusData,
                    sequenceNumber: packet.sequenceNumber
                )
            }
        }

        controlReceiveTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.connectionManager.controlMessages
            for await message in stream {
                guard !Task.isCancelled else { break }
                self.floorController.handleMessage(message)
                self.syncState()
            }
        }

        logger.info("Receive loops started")
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

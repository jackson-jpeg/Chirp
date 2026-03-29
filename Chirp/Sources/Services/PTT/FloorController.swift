import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class FloorController {

    // MARK: - Public State

    private(set) var currentSpeaker: (id: String, name: String)?
    private(set) var state: PTTState = .idle {
        didSet { onStateChange?(state) }
    }

    // MARK: - Configuration

    let localPeerID: String
    let localPeerName: String

    /// Callback wired by PTTEngine to broadcast control messages to all peers.
    var sendToAllPeers: (@Sendable (FloorControlMessage) -> Void)?

    /// Callback fired on every state change — used to trigger live transcription start/stop.
    var onStateChange: ((PTTState) -> Void)?

    // MARK: - Private

    private let logger = Logger.ptt
    private var localRequestTimestamp: Date?

    // MARK: - Init

    init(localPeerID: String, localPeerName: String) {
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
    }

    // MARK: - Local Actions

    /// Attempt to take the floor. Optimistically transitions to .transmitting
    /// if idle, otherwise sets .denied.
    func requestFloor() {
        guard state == .idle else {
            logger.info("Floor request denied — state is \(String(describing: self.state))")
            state = .denied
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.state == .denied else { return }
                self.state = .idle
            }
            return
        }

        let now = Date()
        localRequestTimestamp = now
        currentSpeaker = (id: localPeerID, name: localPeerName)
        state = .transmitting
        logger.info("Floor requested (optimistic grant)")

        sendToAllPeers?(.floorRequest(senderID: localPeerID, senderName: localPeerName, timestamp: now))
    }

    /// Release the floor and broadcast to peers.
    func releaseFloor() {
        guard state == .transmitting else { return }
        clearSpeaker()
        logger.info("Floor released locally")
        sendToAllPeers?(.floorRelease(senderID: localPeerID))
    }

    // MARK: - Remote Message Handling

    func handleMessage(_ message: FloorControlMessage) {
        switch message {
        case .floorRequest(let senderID, let senderName, let timestamp):
            handleRemoteFloorRequest(peerID: senderID, peerName: senderName, timestamp: timestamp)

        case .floorGranted:
            break // Confirmation — no-op in first-come-first-served

        case .floorRelease(let senderID):
            guard currentSpeaker?.id == senderID else { return }
            clearSpeaker()
            logger.info("Remote peer \(senderID) released the floor")

        case .peerJoin:
            break // Informational

        case .peerLeave(let peerID):
            if currentSpeaker?.id == peerID {
                clearSpeaker()
                logger.info("Speaker \(peerID) left — floor released")
            }

        case .heartbeat:
            break // Handled by PeerTracker
        }
    }

    // MARK: - Private

    private func handleRemoteFloorRequest(peerID: String, peerName: String, timestamp: Date) {
        guard peerID != localPeerID else { return }

        switch state {
        case .idle:
            currentSpeaker = (id: peerID, name: peerName)
            state = .receiving(speakerName: peerName, speakerID: peerID)
            logger.info("Floor granted to \(peerName)")
            sendToAllPeers?(.floorGranted(speakerID: peerID))

        case .transmitting:
            // Collision: compare timestamps, earliest wins
            if let localTS = localRequestTimestamp, localTS <= timestamp {
                logger.info("Floor collision — local wins")
            } else {
                logger.info("Floor collision — remote wins")
                clearSpeaker()
                currentSpeaker = (id: peerID, name: peerName)
                state = .receiving(speakerName: peerName, speakerID: peerID)
                sendToAllPeers?(.floorGranted(speakerID: peerID))
            }

        case .receiving, .denied:
            break // Floor occupied, ignore
        }
    }

    private func clearSpeaker() {
        currentSpeaker = nil
        localRequestTimestamp = nil
        state = .idle
    }
}

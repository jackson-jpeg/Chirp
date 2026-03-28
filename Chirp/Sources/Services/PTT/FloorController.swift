import Foundation
import Observation
import OSLog

@Observable
final class FloorController: @unchecked Sendable {

    // MARK: - Public State

    private(set) var currentSpeaker: (id: String, name: String)?
    private(set) var state: PTTState = .idle

    // MARK: - Configuration

    let localPeerID: String
    let localPeerName: String

    /// Callback wired by PTTEngine to broadcast control messages to all peers.
    var sendToAllPeers: (@Sendable (FloorControlMessage) -> Void)?

    // MARK: - Private

    private let logger = Logger.ptt

    /// Timestamp of the local floor request used for collision resolution.
    private var localRequestTimestamp: Date?

    // MARK: - Init

    init(localPeerID: String, localPeerName: String) {
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
    }

    // MARK: - Local Actions

    /// Attempt to take the floor. Optimistically transitions to `.transmitting`
    /// if idle, otherwise sets `.denied`.
    func requestFloor() {
        guard state == .idle else {
            logger.info("Floor request denied — state is \(String(describing: self.state))")
            state = .denied
            // Auto-clear denied after a short delay so UI can react then reset.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.state == .denied else { return }
                self.state = .idle
            }
            return
        }

        let now = Date()
        localRequestTimestamp = now

        // Optimistic grant — assume we get the floor.
        currentSpeaker = (id: localPeerID, name: localPeerName)
        state = .transmitting
        logger.info("Floor requested (optimistic grant)")

        sendToAllPeers?(.requestFloor(peerID: localPeerID, timestamp: now))
    }

    /// Release the floor and broadcast to peers.
    func releaseFloor() {
        guard state == .transmitting else {
            logger.debug("releaseFloor called but not transmitting — ignoring")
            return
        }

        let now = Date()
        clearSpeaker()
        logger.info("Floor released locally")

        sendToAllPeers?(.releaseFloor(peerID: localPeerID, timestamp: now))
    }

    // MARK: - Remote Message Handling

    func handleMessage(_ message: FloorControlMessage) {
        switch message {

        case .requestFloor(let peerID, let remoteTimestamp):
            handleRemoteFloorRequest(peerID: peerID, timestamp: remoteTimestamp)

        case .grantFloor(let peerID, _):
            // A peer told us our request was granted. If we already optimistically
            // took the floor this is a no-op confirmation.
            if peerID == localPeerID && state != .transmitting {
                currentSpeaker = (id: localPeerID, name: localPeerName)
                state = .transmitting
                logger.info("Floor grant confirmed by remote peer")
            }

        case .releaseFloor(let peerID, _):
            guard currentSpeaker?.id == peerID else { return }
            clearSpeaker()
            logger.info("Remote peer \(peerID) released the floor")

        case .denyFloor(let peerID, let reason):
            if peerID == localPeerID {
                // We lost a collision — revert optimistic state.
                if state == .transmitting && currentSpeaker?.id == localPeerID {
                    clearSpeaker()
                    state = .denied
                    logger.info("Floor denied by remote: \(reason)")
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard let self, self.state == .denied else { return }
                        self.state = .idle
                    }
                }
            }

        case .heartbeat:
            // Heartbeats are handled by PeerTracker, not floor control.
            break

        case .peerJoined:
            // Informational — no floor action needed.
            break

        case .peerLeft(let peerID):
            // If the speaking peer left, release the floor automatically.
            if currentSpeaker?.id == peerID {
                clearSpeaker()
                logger.info("Speaker \(peerID) left — floor released")
            }
        }
    }

    // MARK: - Private Helpers

    private func handleRemoteFloorRequest(peerID: String, timestamp: Date) {
        guard peerID != localPeerID else { return }

        switch state {
        case .idle:
            // Grant floor to the requesting peer.
            currentSpeaker = (id: peerID, name: peerID) // name resolved by PeerTracker elsewhere
            state = .receiving(speakerName: peerID, speakerID: peerID)
            logger.info("Floor granted to remote peer \(peerID)")

            sendToAllPeers?(.grantFloor(peerID: peerID, timestamp: Date()))

        case .transmitting:
            // Collision: we are already transmitting. First-come wins — compare timestamps.
            if let localTS = localRequestTimestamp, localTS <= timestamp {
                // We requested first (or simultaneously) — we keep the floor. Deny remote.
                logger.info("Floor collision — local wins (earlier timestamp)")
                sendToAllPeers?(.denyFloor(peerID: peerID, reason: "collision — earlier request wins"))
            } else {
                // Remote requested first — we must yield.
                logger.info("Floor collision — remote wins (earlier timestamp)")
                clearSpeaker()
                currentSpeaker = (id: peerID, name: peerID)
                state = .receiving(speakerName: peerID, speakerID: peerID)
                sendToAllPeers?(.grantFloor(peerID: peerID, timestamp: Date()))
            }

        case .receiving:
            // Already receiving from someone else — deny this new request.
            sendToAllPeers?(.denyFloor(peerID: peerID, reason: "floor occupied"))

        case .denied:
            // Transient state — deny.
            sendToAllPeers?(.denyFloor(peerID: peerID, reason: "floor occupied"))
        }
    }

    private func clearSpeaker() {
        currentSpeaker = nil
        localRequestTimestamp = nil
        state = .idle
    }
}

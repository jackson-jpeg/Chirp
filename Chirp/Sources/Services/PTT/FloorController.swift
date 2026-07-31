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

    /// Fired when the floor is taken away from this device *while it was
    /// transmitting* — a loss the local user did not initiate by letting go of
    /// the button.
    ///
    /// This is deliberately separate from ``onStateChange``, which is a general
    /// observation hook. This one is a control signal with exactly one correct
    /// response: close the microphone. `PTTEngine` owns capture, so `PTTEngine`
    /// has to be the thing that hears about it.
    var onFloorRevoked: (() -> Void)?

    // MARK: - Private

    private let logger = Logger.ptt
    private var localRequestTimestamp: Date?

    /// When the claim that currently holds the floor was made — whoever holds
    /// it, local or remote.
    ///
    /// First-come-first-served is a *comparison*, so a device that knows only
    /// WHO holds the floor cannot evaluate a challenge to it. Without this, the
    /// only states that could resolve a contested floor were `.idle` and
    /// `.transmitting`; every other device on the mesh discarded the request
    /// unread.
    private var floorHeldSince: Date?

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
                // Return to what the denial interrupted, not to idle.
                //
                // `.denied` overwrites whatever state it interrupted, and
                // dropping to `.idle` afterwards broke both of them:
                //
                //   - Interrupting `.receiving`: this device believed the
                //     channel was free 600ms later, so the next press passed
                //     the `state == .idle` guard below and transmitted straight
                //     over the person still speaking.
                //   - Interrupting `.transmitting`: worse. The microphone is
                //     open, and `releaseFloor()` below is guarded on
                //     `state == .transmitting` — so letting go of the button
                //     did nothing at all. No release went out, every peer went
                //     on believing this device held the floor, and the only
                //     thing that ever ended it was the 120-second watchdog.
                //     Reachable by pressing the button twice.
                switch self.currentSpeaker {
                case let speaker? where speaker.id == self.localPeerID:
                    self.state = .transmitting
                case let speaker?:
                    self.state = .receiving(speakerName: speaker.name, speakerID: speaker.id)
                case nil:
                    self.state = .idle
                }
            }
            return
        }

        let now = Date()
        localRequestTimestamp = now
        floorHeldSince = now
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
            floorHeldSince = timestamp
            state = .receiving(speakerName: peerName, speakerID: peerID)
            logger.info("Floor granted to \(peerName)")
            sendToAllPeers?(.floorGranted(speakerID: peerID))

        case .transmitting:
            // Collision: compare timestamps, earliest wins
            if let localTS = localRequestTimestamp,
               (localTS < timestamp || (localTS == timestamp && localPeerID < peerID)) {
                logger.info("Floor collision — local wins")
                // Restate the claim rather than winning silently.
                //
                // The loser can only work out that it lost by comparing the two
                // requests, so it needs to have seen ours. A peer that never
                // received our original request — it was sent while that peer
                // was in `.denied`, or it was simply dropped — has nothing to
                // compare against, and nothing else on the wire ever mentions a
                // floor session it does not already know about. Before this,
                // that peer transmitted alongside us until one of us let go.
                //
                // Re-sending the *original* request (same ID, same timestamp,
                // not a fresh one) means the peer resolves this with the rule it
                // already applies to every request, instead of needing a second
                // mechanism. The comparison is total and both sides evaluate the
                // same pair, so exactly one of us can be in this branch — a
                // restatement cannot be answered by a counter-restatement.
                sendToAllPeers?(
                    .floorRequest(senderID: localPeerID, senderName: localPeerName, timestamp: localTS)
                )
            } else {
                logger.info("Floor collision — remote wins")
                clearSpeaker()
                currentSpeaker = (id: peerID, name: peerName)
                floorHeldSince = timestamp
                state = .receiving(speakerName: peerName, speakerID: peerID)
                sendToAllPeers?(.floorGranted(speakerID: peerID))
                // The microphone is still open at this point. Losing the floor
                // is the one way to stop transmitting that PTTEngine was not
                // watching for, so tell it explicitly — after the state change,
                // so that a `releaseFloor()` on the way back down is correctly
                // a no-op and does not announce a release we never made.
                onFloorRevoked?()
            }

        case .receiving, .denied:
            // A device that already has a speaker still has to evaluate
            // challenges to it. Discarding them unread meant a request that
            // legitimately predated the current holder — delayed, relayed, or
            // simply reordered by the mesh — never took effect here, so this
            // device displayed a different speaker from the rest of the mesh
            // and stayed that way.
            //
            // `.denied` is included deliberately: it is `.receiving` plus a
            // rejected button press, and there is no reason a local press
            // should make this device deaf to who is speaking for 600ms.
            guard peerID != currentSpeaker?.id else { return }  // holder restating its claim
            guard claimBeatsHeldFloor(peerID: peerID, timestamp: timestamp) else { return }

            logger.info("Floor holder changed to \(peerName) — earlier claim")
            currentSpeaker = (id: peerID, name: peerName)
            floorHeldSince = timestamp
            state = .receiving(speakerName: peerName, speakerID: peerID)
        }
    }

    private func clearSpeaker() {
        currentSpeaker = nil
        localRequestTimestamp = nil
        floorHeldSince = nil
        state = .idle
    }

    /// First-come-first-served: the earliest request wins, ties broken by peer
    /// ID so that every device reaches the same answer from the same pair.
    ///
    /// The single place this rule is written down. It used to be inline in the
    /// collision branch only, which is why the other states could not apply it.
    private func claimBeatsHeldFloor(peerID: String, timestamp: Date) -> Bool {
        guard let heldSince = floorHeldSince, let holder = currentSpeaker else { return true }
        if timestamp != heldSince { return timestamp < heldSince }
        return peerID < holder.id
    }
}

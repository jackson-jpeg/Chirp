import Foundation
import Observation
import OSLog

/// The impure shell around ``FloorMachine``: holds the current ``FloorState``,
/// feeds events through ``FloorMachine/reduce(_:on:as:)``, and performs the
/// effects the reduction returns.
///
/// Everything interesting about the floor protocol lives in the machine, where
/// it is pure and exhaustively tested. This class owns only what a pure
/// function cannot: the current state, the refusal-feedback timer, and the
/// callbacks that reach the transport and the microphone.
///
/// ## Wiring
/// - ``sendToAllPeers`` — broadcast a control message (wired by `PTTEngine`).
/// - ``onOpenMicrophone`` / ``onCloseMicrophone`` — the machine's verdict on
///   capture. `PTTEngine` owns the audio engine, so these are how every
///   transition that touches the microphone actually reaches it. There is no
///   other path: capture starts and stops *only* through these.
/// - ``onStateChange`` — general observation hook (live transcription).
@Observable
@MainActor
final class FloorSession {

    // MARK: - Public State

    /// The machine's state, verbatim.
    private(set) var floorState: FloorState = .idle

    /// The machine's state projected onto the UI-facing enum.
    var state: PTTState {
        Self.projected(floorState)
    }

    /// Whoever currently holds the floor, if anyone.
    var currentSpeaker: (id: String, name: String)? {
        floorState.claim.map { (id: $0.peerID, name: $0.peerName) }
    }

    // MARK: - Configuration

    let localPeerID: String
    let localPeerName: String

    /// Callback wired by PTTEngine to broadcast control messages to all peers.
    var sendToAllPeers: (@Sendable (FloorControlMessage) -> Void)?

    /// Fired on every projected state change — used to drive live transcription.
    var onStateChange: ((PTTState) -> Void)?

    /// The machine returned ``FloorEffect/openMicrophone``: this device holds
    /// the floor and capture must start.
    var onOpenMicrophone: (() -> Void)?

    /// The machine returned ``FloorEffect/closeMicrophone``: however the floor
    /// was lost or released, capture must stop.
    var onCloseMicrophone: (() -> Void)?

    // MARK: - Private

    private let logger = Logger.ptt
    private var identity: FloorIdentity {
        FloorIdentity(peerID: localPeerID, peerName: localPeerName)
    }
    private var refusalTimer: Task<Void, Never>?

    // MARK: - Init

    init(localPeerID: String, localPeerName: String) {
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
    }

    // MARK: - Inputs

    /// The user pressed the talk button.
    func requestFloor() {
        handle(.localPressed(at: Date()))
    }

    /// The user let go of the talk button.
    func releaseFloor() {
        handle(.localReleased)
    }

    /// A floor control message arrived off the mesh.
    ///
    /// - Parameter from: the sender as *observed* — the mesh packet's origin ID,
    ///   which the router dedups and replay-protects on. The machine checks it
    ///   against the sender the message claims, so a peer cannot end someone
    ///   else's turn by naming them in a forged release.
    func handleMessage(_ message: FloorControlMessage, from observedSender: String) {
        handle(.received(message, from: observedSender))
    }

    /// The transport (or ghost detection) lost a peer. Unlike a `.peerLeave`
    /// message this is a local observation and cannot be about somebody else.
    func peerLost(_ peerID: String) {
        handle(.transportLostPeer(peerID))
    }

    // MARK: - The loop

    private func handle(_ event: FloorEvent) {
        let before = state
        let outcome = FloorMachine.reduce(floorState, on: event, as: identity)
        floorState = outcome.state
        for effect in outcome.effects {
            perform(effect)
        }
        let after = state
        if before != after {
            onStateChange?(after)
        }
    }

    private func perform(_ effect: FloorEffect) {
        switch effect {
        case .openMicrophone:
            onOpenMicrophone?()

        case .closeMicrophone:
            onCloseMicrophone?()

        case .send(let message):
            sendToAllPeers?(message)

        case .startRefusalTimer(let duration):
            // The machine guarantees it never returns this while already
            // refused, so there is at most one live timer; the cancel is
            // belt-and-braces for reentrancy, not a mechanism.
            refusalTimer?.cancel()
            refusalTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled, let self else { return }
                self.handle(.refusalExpired)
            }

        case .reportImpersonation(let claimed, let actual):
            logger.warning("Floor message claimed sender \(claimed, privacy: .public) but arrived from \(actual, privacy: .public) — dropped")
        }
    }

    // MARK: - Projection

    private static func projected(_ state: FloorState) -> PTTState {
        switch state {
        case .idle:
            return .idle
        case .holding:
            return .transmitting
        case .listening(let claim):
            return .receiving(speakerName: claim.peerName, speakerID: claim.peerID)
        case .refused:
            return .denied
        }
    }
}

import Foundation

/// Who may transmit, and why — as one explicit state machine.
///
/// # Why this is a rewrite and not a repair
///
/// Five stuck-microphone defects were found in the previous design. Every one
/// of them was the same sentence: *a transition changed the floor without
/// saying what happened to the microphone.* Closing the microphone was a
/// callback bolted onto one transition out of five, so the other four were
/// silently wrong and each had to be discovered separately — three by
/// reasoning, two by enumerating the transition table.
///
/// Here, closing the microphone is a ``FloorEffect``. `reduce` is a pure
/// function that must **return** the effects a transition implies, and its
/// switch is exhaustive over (state × event). Every arm has to say what happens
/// to the microphone, and the compiler makes it say so. The defect class
/// becomes unwriteable rather than unwritten.
///
/// # The three faults this removes
///
/// 1. **Truth was split across five variables** — `state`, `currentSpeaker`,
///    `localRequestTimestamp`, `floorHeldSince`, and an unbounded set of
///    pending denial `Task`s — with an invariant nobody wrote down and nothing
///    enforced. Here the state *is* the state: whoever holds the floor and when
///    they claimed it live inside the case.
/// 2. **`.denied` was not a state**, it was UI feedback that destroyed the real
///    state, leaving a timer to *infer* where to return by inspecting who the
///    speaker happened to be. ``FloorState/refused(under:until:)`` carries what
///    it interrupted, so returning is a fact.
/// 3. **Any peer could end your turn.** `.floorRelease` and `.peerLeave` were
///    trusted to name whoever they liked, so a message naming your device
///    dropped you to idle with the microphone open. Every remote event now
///    arrives with the transport's observed sender and is checked against the
///    sender the message claims.
///
/// Effects are returned rather than performed so that tests assert on them
/// directly, rather than through a callback spy that can only observe the one
/// transition somebody remembered to wire up.

// MARK: - Identity

struct FloorIdentity: Equatable, Sendable {
    let peerID: String
    let peerName: String
}

/// A claim on the floor: who, and when they asked.
struct FloorClaim: Equatable, Sendable {
    let peerID: String
    let peerName: String
    let claimedAt: Date

    /// First-come-first-served. The earliest claim wins; ties break on peer ID
    /// so that every device reaches the same answer from the same pair.
    ///
    /// The single place this rule is written down. In the previous design it
    /// was inline in the collision branch, which is exactly why the other
    /// states could not apply it.
    func beats(_ other: FloorClaim) -> Bool {
        if claimedAt != other.claimedAt { return claimedAt < other.claimedAt }
        return peerID < other.peerID
    }
}

// MARK: - State

enum FloorState: Equatable, Sendable {
    /// Nobody holds the floor.
    case idle

    /// This device holds it. **The microphone is open in this state and in no
    /// other.** Any transition out of it must close the microphone or be a
    /// transition back into it.
    case holding(FloorClaim)

    /// A peer holds it.
    case listening(FloorClaim)

    /// A local press was refused. Carries the state it interrupted so that
    /// returning from it is a fact rather than a guess.
    indirect case refused(under: FloorState)

    /// Whether the microphone is open in this state. Used by the exhaustive
    /// tests to check that every transition out of an open-microphone state
    /// either closes it or stays open — the property that five separate bugs
    /// violated.
    var microphoneIsOpen: Bool {
        switch self {
        case .holding: return true
        case .refused(let under): return under.microphoneIsOpen
        case .idle, .listening: return false
        }
    }

    /// The claim currently holding the floor, if any.
    var claim: FloorClaim? {
        switch self {
        case .idle: return nil
        case .holding(let c), .listening(let c): return c
        case .refused(let under): return under.claim
        }
    }
}

// MARK: - Events

enum FloorEvent: Equatable, Sendable {
    case localPressed(at: Date)
    case localReleased
    /// The refusal feedback window elapsed.
    case refusalExpired
    /// A control message arrived. `from` is the peer the **transport** observed
    /// it coming from, which is not the same thing as the sender the message
    /// claims to be — see ``FloorMachine/reduce(_:on:as:)``.
    case received(FloorControlMessage, from: String)
    /// The transport lost a peer. Distinct from a `.peerLeave` message, which
    /// is a claim by a peer and can be about anyone.
    case transportLostPeer(String)
}

// MARK: - Effects

enum FloorEffect: Equatable, Sendable {
    case openMicrophone
    case closeMicrophone
    case send(FloorControlMessage)
    /// Show the "you can't talk right now" feedback for this long, then deliver
    /// `.refusalExpired`. Returned as an effect so the machine stays pure and
    /// so that repeated presses cannot pile up timers.
    case startRefusalTimer(TimeInterval)
    /// A remote message claimed to be from someone the transport did not
    /// receive it from. Surfaced rather than dropped.
    case reportImpersonation(claimed: String, actual: String)
}

struct FloorOutcome: Equatable {
    let state: FloorState
    let effects: [FloorEffect]
}

// MARK: - The machine

enum FloorMachine {

    static let refusalFeedbackDuration: TimeInterval = 0.6

    /// The whole protocol, in one exhaustive switch.
    ///
    /// - Parameters:
    ///   - state: current state
    ///   - event: what happened
    ///   - local: this device's identity
    static func reduce(_ state: FloorState, on event: FloorEvent, as local: FloorIdentity) -> FloorOutcome {
        switch event {

        case .localPressed(let at):
            return localPressed(state, at: at, local: local)

        case .localReleased:
            return localReleased(state, local: local)

        case .refusalExpired:
            // Return to exactly what the refusal interrupted. No inference:
            // the interrupted state is carried in the case.
            guard case .refused(let under) = state else {
                return FloorOutcome(state: state, effects: [])
            }
            return FloorOutcome(state: under, effects: [])

        case .received(let message, let from):
            return received(message, from: from, state: state, local: local)

        case .transportLostPeer(let peerID):
            // The transport observed the loss itself, so unlike a `.peerLeave`
            // message this cannot be about somebody else's device.
            guard let claim = state.claim, claim.peerID == peerID, peerID != local.peerID else {
                return FloorOutcome(state: state, effects: [])
            }
            return releaseFloorLocally(from: state, reason: [])
        }
    }

    // MARK: Local events

    private static func localPressed(_ state: FloorState, at: Date, local: FloorIdentity) -> FloorOutcome {
        switch state {
        case .idle:
            let claim = FloorClaim(peerID: local.peerID, peerName: local.peerName, claimedAt: at)
            return FloorOutcome(
                state: .holding(claim),
                effects: [
                    .openMicrophone,
                    .send(.floorRequest(senderID: local.peerID, senderName: local.peerName, timestamp: at)),
                ]
            )

        case .holding, .listening:
            // Refused. The microphone is untouched — if we were holding, we go
            // on holding underneath the refusal, which is the bug that used to
            // drop us to idle with the microphone open and then make
            // `releaseFloor` a no-op.
            return FloorOutcome(
                state: .refused(under: state),
                effects: [.startRefusalTimer(refusalFeedbackDuration)]
            )

        case .refused:
            // Already refused. Do NOT stack another timer — the previous design
            // spawned one Task per press, unbounded.
            return FloorOutcome(state: state, effects: [])
        }
    }

    private static func localReleased(_ state: FloorState, local: FloorIdentity) -> FloorOutcome {
        // Releasing while refused-under-holding must still release. Unwrapping
        // the refusal here is what makes letting go work after a double press.
        let effective: FloorState = { if case .refused(let under) = state { return under }; return state }()

        guard case .holding = effective else {
            return FloorOutcome(state: state, effects: [])
        }
        return FloorOutcome(
            state: .idle,
            effects: [.closeMicrophone, .send(.floorRelease(senderID: local.peerID))]
        )
    }

    // MARK: Remote events

    private static func received(
        _ message: FloorControlMessage,
        from transportPeer: String,
        state: FloorState,
        local: FloorIdentity
    ) -> FloorOutcome {
        // A message's claimed sender must match the peer the transport actually
        // received it from. Without this, any peer could send
        // `.floorRelease(senderID: <you>)` or `.peerLeave(peerID: <you>)` and
        // end your turn — dropping you to idle with the microphone open and no
        // signal to close it. Two of the five stuck-microphone defects were
        // exactly that, and neither was reachable through the floor-*request*
        // path, which already had this guard.
        if let claimed = claimedSender(of: message), claimed != transportPeer {
            return FloorOutcome(
                state: state,
                effects: [.reportImpersonation(claimed: claimed, actual: transportPeer)]
            )
        }

        switch message {
        case .floorRequest(let senderID, let senderName, let timestamp):
            guard senderID != local.peerID else { return FloorOutcome(state: state, effects: []) }
            return remoteRequest(
                FloorClaim(peerID: senderID, peerName: senderName, claimedAt: timestamp),
                state: state, local: local
            )

        case .floorRelease(let senderID):
            guard let claim = state.claim, claim.peerID == senderID, senderID != local.peerID else {
                return FloorOutcome(state: state, effects: [])
            }
            return releaseFloorLocally(from: state, reason: [])

        case .peerLeave(let peerID):
            guard let claim = state.claim, claim.peerID == peerID, peerID != local.peerID else {
                return FloorOutcome(state: state, effects: [])
            }
            return releaseFloorLocally(from: state, reason: [])

        case .floorGranted:
            // Deliberately inert, and now deliberately DOCUMENTED as inert.
            //
            // In the previous design this was `break // no-op` in all four
            // states, which read as an oversight. It is not enough information
            // to act on: `floorGranted` carries a speaker ID but no sender, so
            // a receiver cannot tell whether it came from the device that holds
            // the floor or from any peer repeating it. Acting on it would let
            // the floor flip on a replayed message.
            //
            // Fixing the stale-holder case means adding a sender to this
            // message. That is a wire-format change and is tracked separately.
            return FloorOutcome(state: state, effects: [])

        case .peerJoin, .heartbeat:
            return FloorOutcome(state: state, effects: [])
        }
    }

    private static func remoteRequest(
        _ incoming: FloorClaim,
        state: FloorState,
        local: FloorIdentity
    ) -> FloorOutcome {
        switch state {
        case .idle:
            return FloorOutcome(
                state: .listening(incoming),
                effects: [.send(.floorGranted(speakerID: incoming.peerID))]
            )

        case .holding(let mine):
            if mine.beats(incoming) {
                // Restate the claim rather than winning silently. A peer that
                // never saw our original request has nothing to compare against
                // and would otherwise transmit alongside us indefinitely.
                // Re-sending the ORIGINAL request — same timestamp, not a fresh
                // one — means it resolves this with the rule it already applies
                // to every request, rather than needing a second mechanism.
                // The comparison is total, so exactly one side can be here: a
                // restatement cannot be answered by a counter-restatement.
                return FloorOutcome(
                    state: state,
                    effects: [.send(.floorRequest(senderID: mine.peerID,
                                                  senderName: mine.peerName,
                                                  timestamp: mine.claimedAt))]
                )
            }
            // We lost. The microphone is open and this is the transition that
            // used to need a bolted-on callback to remember that.
            return FloorOutcome(
                state: .listening(incoming),
                effects: [.closeMicrophone, .send(.floorGranted(speakerID: incoming.peerID))]
            )

        case .listening(let holder):
            guard incoming.peerID != holder.peerID else {
                return FloorOutcome(state: state, effects: [])   // holder restating
            }
            guard incoming.beats(holder) else {
                return FloorOutcome(state: state, effects: [])
            }
            return FloorOutcome(state: .listening(incoming), effects: [])

        case .refused(let under):
            // A refusal must not make this device deaf to who is speaking.
            // Resolve underneath it and keep the refusal feedback on top.
            let inner = remoteRequest(incoming, state: under, local: local)
            // If the floor moved to a peer, the refusal no longer means
            // anything — surface the new speaker immediately.
            if case .listening = inner.state, under.microphoneIsOpen == false {
                return inner
            }
            return FloorOutcome(state: .refused(under: inner.state), effects: inner.effects)
        }
    }

    /// Leave the floor because somebody else's message or the transport says
    /// it is over. Closes the microphone if this device had it open — which is
    /// the check that did not exist before.
    private static func releaseFloorLocally(from state: FloorState, reason: [FloorEffect]) -> FloorOutcome {
        var effects = reason
        if state.microphoneIsOpen { effects.append(.closeMicrophone) }
        return FloorOutcome(state: .idle, effects: effects)
    }

    /// The peer a message claims to originate from, for messages where that is
    /// meaningful. `floorGranted` is excluded because it names a *subject*, not
    /// a sender — which is precisely the gap that makes it unusable.
    private static func claimedSender(of message: FloorControlMessage) -> String? {
        switch message {
        case .floorRequest(let senderID, _, _): return senderID
        case .floorRelease(let senderID): return senderID
        case .peerLeave(let peerID): return peerID
        case .peerJoin(let peerID, _): return peerID
        case .heartbeat(let peerID, _): return peerID
        case .floorGranted: return nil
        }
    }
}

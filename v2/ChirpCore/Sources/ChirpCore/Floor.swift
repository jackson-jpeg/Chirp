import Foundation

// Who may talk on a channel, as a pure reducer that returns its effects.
//
// Kept from 1.0 (audit section 7, the best-tested code there): one exhaustive
// switch, effects returned rather than performed so every arm must say what
// happens to the microphone, a refusal that carries the state it interrupted,
// first-come-first-served with a total tie-break, and a check that a message's
// claimed sender is the sender we verified.
//
// Changed for 2.0:
// - Scoped to one channel. A floor message for another channel changes nothing
//   (audit defect 1, claim H6).
// - A listening timeout. 1.0 had none, so a lost release left listeners stuck
//   "receiving" for up to 120 s (H15). Here a speaker who goes quiet for
//   `silenceTimeout` loses the floor on every listener.
// - A talk cap, so a stuck button cannot hold a channel forever.
// - No `floorGranted` (sent, documented as ignored: dead wire traffic).
// - `from` is the packet's verified origin, not the link it arrived on, so a
//   floor request relayed through a third phone is not taken for an impersonation.

public struct FloorClaim: Equatable, Sendable {
    public let peer: PeerID
    public let name: String
    public let claimedAt: Date
    /// Last time anything was heard from the holder (audio or floor message).
    public var lastHeard: Date

    public init(peer: PeerID, name: String, claimedAt: Date, lastHeard: Date? = nil) {
        self.peer = peer
        self.name = name
        self.claimedAt = claimedAt
        self.lastHeard = lastHeard ?? claimedAt
    }

    /// Earliest claim wins; ties break on peer ID so every device agrees.
    public func beats(_ other: FloorClaim) -> Bool {
        if claimedAt != other.claimedAt { return claimedAt < other.claimedAt }
        return peer < other.peer
    }
}

public enum FloorState: Equatable, Sendable {
    case idle
    /// This device holds the floor. The microphone is open here and nowhere else.
    case holding(FloorClaim)
    case listening(FloorClaim)
    /// A local press was refused; carries what it interrupted.
    indirect case refused(under: FloorState)

    public var microphoneIsOpen: Bool {
        switch self {
        case .holding: return true
        case .refused(let under): return under.microphoneIsOpen
        case .idle, .listening: return false
        }
    }

    public var claim: FloorClaim? {
        switch self {
        case .idle: return nil
        case .holding(let c), .listening(let c): return c
        case .refused(let under): return under.claim
        }
    }

    /// Who is talking, if it is someone else.
    public var speaker: FloorClaim? {
        if case .listening(let c) = self { return c }
        if case .refused(let under) = self { return under.speaker }
        return nil
    }
}

public enum FloorMessage: Equatable, Sendable {
    case request(sender: PeerID, name: String, claimedAt: Date)
    case release(sender: PeerID)

    public var sender: PeerID {
        switch self {
        case .request(let s, _, _), .release(let s): return s
        }
    }

    public func encode() -> Data {
        var out = Data()
        switch self {
        case .request(let sender, let name, let at):
            out.append(1)
            out.append(sender.bytes)
            out.appendBigEndian(UInt64(max(0, at.timeIntervalSince1970 * 1000)))
            out.appendString(name, maxBytes: 64)
        case .release(let sender):
            out.append(2)
            out.append(sender.bytes)
        }
        return out
    }

    public static func decode(_ data: Data) -> FloorMessage? {
        var r = ByteReader(data)
        guard let tag = r.u8(), let s = r.bytes(16), let sender = PeerID(bytes: s) else { return nil }
        switch tag {
        case 1:
            guard let ms = r.u64(), let name = r.string(), r.isAtEnd else { return nil }
            return .request(sender: sender, name: name, claimedAt: Date(timeIntervalSince1970: Double(ms) / 1000))
        case 2:
            guard r.isAtEnd else { return nil }
            return .release(sender: sender)
        default:
            return nil
        }
    }
}

public enum FloorEvent: Equatable, Sendable {
    case localPressed(at: Date)
    case localReleased
    case refusalExpired
    /// A floor message on `channel`, from the verified origin `from`.
    case received(FloorMessage, from: PeerID, channel: ChannelID, at: Date)
    /// An audio frame on `channel` from `from`: keeps the speaker's claim alive.
    case heardAudio(from: PeerID, channel: ChannelID, at: Date)
    /// The roster lost this peer.
    case peerGone(PeerID)
    /// Time passed. Applies the silence timeout and the talk cap.
    case tick(Date)
}

public enum FloorEffect: Equatable, Sendable {
    case openMicrophone
    case closeMicrophone
    case send(FloorMessage)
    case startRefusalTimer(TimeInterval)
    case reportImpersonation(claimed: PeerID, actual: PeerID)
}

public struct FloorOutcome: Equatable, Sendable {
    public let state: FloorState
    public let effects: [FloorEffect]
    init(_ state: FloorState, _ effects: [FloorEffect] = []) {
        self.state = state
        self.effects = effects
    }
}

public enum FloorMachine {
    public static let refusalFeedback: TimeInterval = 0.6
    /// A speaker unheard for this long has lost the floor.
    public static let silenceTimeout: TimeInterval = 3
    /// The longest one turn may last.
    public static let talkCap: TimeInterval = 60

    public static func reduce(_ state: FloorState, on event: FloorEvent,
                              me: PeerID, myName: String, channel: ChannelID) -> FloorOutcome {
        switch event {
        case .localPressed(let at):
            switch state {
            case .idle:
                let claim = FloorClaim(peer: me, name: myName, claimedAt: at)
                return FloorOutcome(.holding(claim), [.openMicrophone,
                                                      .send(.request(sender: me, name: myName, claimedAt: at))])
            case .holding, .listening:
                return FloorOutcome(.refused(under: state), [.startRefusalTimer(refusalFeedback)])
            case .refused:
                return FloorOutcome(state)
            }

        case .localReleased:
            let effective: FloorState = { if case .refused(let u) = state { return u }; return state }()
            guard case .holding = effective else { return FloorOutcome(state) }
            return FloorOutcome(.idle, [.closeMicrophone, .send(.release(sender: me))])

        case .refusalExpired:
            guard case .refused(let under) = state else { return FloorOutcome(state) }
            return FloorOutcome(under)

        case .received(let message, let from, let onChannel, let at):
            guard onChannel == channel else { return FloorOutcome(state) }
            guard message.sender == from else {
                return FloorOutcome(state, [.reportImpersonation(claimed: message.sender, actual: from)])
            }
            guard from != me else { return FloorOutcome(state) }
            switch message {
            case .request(_, let name, let claimedAt):
                return remoteRequest(FloorClaim(peer: from, name: name, claimedAt: claimedAt, lastHeard: at),
                                     state: state, me: me)
            case .release:
                guard state.claim?.peer == from else { return FloorOutcome(state) }
                return release(state)
            }

        case .heardAudio(let from, let onChannel, let at):
            guard onChannel == channel else { return FloorOutcome(state) }
            return FloorOutcome(touch(state, peer: from, at: at))

        case .peerGone(let peer):
            guard peer != me, state.claim?.peer == peer else { return FloorOutcome(state) }
            return release(state)

        case .tick(let now):
            guard let claim = state.claim else { return FloorOutcome(state) }
            if claim.peer == me {
                guard now.timeIntervalSince(claim.claimedAt) >= talkCap else { return FloorOutcome(state) }
                return FloorOutcome(.idle, [.closeMicrophone, .send(.release(sender: me))])
            }
            guard now.timeIntervalSince(claim.lastHeard) >= silenceTimeout else { return FloorOutcome(state) }
            return release(state)
        }
    }

    private static func remoteRequest(_ incoming: FloorClaim, state: FloorState, me: PeerID) -> FloorOutcome {
        switch state {
        case .idle:
            return FloorOutcome(.listening(incoming))
        case .holding(let mine):
            if mine.beats(incoming) {
                // Restate the original claim so the other side resolves it with
                // the same rule. The order is total, so only one side restates.
                return FloorOutcome(state, [.send(.request(sender: me, name: mine.name, claimedAt: mine.claimedAt))])
            }
            return FloorOutcome(.listening(incoming), [.closeMicrophone])
        case .listening(let holder):
            if incoming.peer == holder.peer {
                var refreshed = holder
                refreshed.lastHeard = max(holder.lastHeard, incoming.lastHeard)
                return FloorOutcome(.listening(refreshed))
            }
            return incoming.beats(holder) ? FloorOutcome(.listening(incoming)) : FloorOutcome(state)
        case .refused(let under):
            let inner = remoteRequest(incoming, state: under, me: me)
            if case .listening = inner.state, !under.microphoneIsOpen { return inner }
            return FloorOutcome(.refused(under: inner.state), inner.effects)
        }
    }

    private static func release(_ state: FloorState) -> FloorOutcome {
        FloorOutcome(.idle, state.microphoneIsOpen ? [.closeMicrophone] : [])
    }

    private static func touch(_ state: FloorState, peer: PeerID, at: Date) -> FloorState {
        switch state {
        case .listening(var c) where c.peer == peer:
            c.lastHeard = max(c.lastHeard, at)
            return .listening(c)
        case .refused(let under):
            return .refused(under: touch(under, peer: peer, at: at))
        default:
            return state
        }
    }
}

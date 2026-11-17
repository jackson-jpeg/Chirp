import Foundation

/// Find (scope item 4): point to a friend.
///
/// Precision finding is Nearby Interaction between two iPhones with the UWB
/// chip. Each side needs the other's discovery token before ranging starts,
/// and with no internet the only way to swap tokens is this mesh: a `.find`
/// packet on the whisper channel (sealed pairwise, admitted only from a
/// friend, see `Admission`). The token is opaque bytes here; the app archives
/// and unarchives `NIDiscoveryToken`. The ranging itself, and the Nearby
/// Interaction permission prompt (asked on the first Find tap, never at
/// launch), live in the app.
///
/// Without UWB on either phone, or before ranging starts, the app shows the
/// plain fallback below, which claims no more than the mesh knows. 1.0 showed
/// invented hop counts, signal bars and metres (audit section 4).
public enum Find {
    public static let maxTokenBytes = 2048

    public enum Message: Equatable, Sendable {
        /// "Here is my token; send me yours."
        case offer(token: Data)
        /// "Here is mine back."
        case answer(token: Data)
        /// Stop ranging.
        case stop

        public func encode() -> Data {
            switch self {
            case .offer(let t): var d = Data([1]); d.appendBigEndian(UInt16(t.count)); d.append(t); return d
            case .answer(let t): var d = Data([2]); d.appendBigEndian(UInt16(t.count)); d.append(t); return d
            case .stop: return Data([3])
            }
        }

        public static func decode(_ data: Data) -> Message? {
            var r = ByteReader(data)
            guard let tag = r.u8() else { return nil }
            if tag == 3 { return r.isAtEnd ? .stop : nil }
            guard tag == 1 || tag == 2, let n = r.u16(), n > 0, Int(n) <= maxTokenBytes,
                  let t = r.bytes(Int(n)), r.isAtEnd else { return nil }
            return tag == 1 ? .offer(token: t) : .answer(token: t)
        }
    }

    /// What the app can honestly say without a UWB fix.
    public enum Fallback: Equatable, Sendable {
        /// Heard directly in the last few seconds: within Wi-Fi or Bluetooth range.
        case inRange
        /// Heard only through a relay: further away, direction unknown.
        case throughOthers
        /// Not heard recently.
        case outOfRange(lastSeen: Date?)
    }

    public static let recent: TimeInterval = 10

    public static func fallback(for person: Roster.Person?, lastSeen: Date?, now: Date) -> Fallback {
        guard let person, now.timeIntervalSince(person.lastSeen) <= recent else {
            return .outOfRange(lastSeen: person?.lastSeen ?? lastSeen)
        }
        return person.hops == 0 ? .inRange : .throughOthers
    }
}

// MARK: - The exchange, as one reducer

/// One Find with one friend, from the first tap to closing the screen.
///
/// Rules held here, each with a test:
/// - Nothing runs until you open Find on a friend (the Nearby Interaction
///   prompt comes from running a session, so it follows that tap, 5.1.1(iv)).
/// - An offer from a friend whose Find you have not opened never starts your
///   session: it becomes a request you can answer by opening Find on them.
/// - Ranging needs both tokens; whoever opens second answers, and the first
///   starts ranging on the answer. A stop or closing the screen ends it.
public struct FindSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        /// Find is open on a phone without precision finding: fallback only.
        case fallbackOnly
        /// Our offer is out; waiting for their answer (or their own offer).
        case offered
        /// Both tokens known; ranging.
        case ranging(peerToken: Data)
    }

    public enum Event: Equatable, Sendable {
        /// You opened Find on `friend`. `myToken` is nil without UWB.
        case opened(myToken: Data?)
        case received(Find.Message)
        /// You closed Find, or the app went to the background.
        case closed
        /// Ranging was refused or ended by iOS (permission denied, invalidated).
        case rangingFailed
    }

    public enum Effect: Equatable, Sendable {
        case send(Find.Message)
        case run(peerToken: Data)
        case invalidate
        /// They are looking for you; show it, and open Find on them to help.
        case showRequest
    }

    public private(set) var phase: Phase = .closed
    /// Their token from an offer that arrived before you opened Find.
    public private(set) var pendingOffer: Data?

    public init() {}

    public mutating func handle(_ event: Event) -> [Effect] {
        switch (phase, event) {
        case (.closed, .opened(nil)):
            phase = .fallbackOnly
            return []
        case (.closed, .opened(let mine?)):
            if let theirs = pendingOffer {
                pendingOffer = nil
                phase = .ranging(peerToken: theirs)
                return [.send(.answer(token: mine)), .run(peerToken: theirs)]
            }
            phase = .offered
            return [.send(.offer(token: mine))]

        case (.closed, .received(.offer(let theirs))):
            let first = pendingOffer == nil
            pendingOffer = theirs
            return first ? [.showRequest] : []
        case (.closed, .received(.stop)):
            pendingOffer = nil
            return []

        case (.offered, .received(.answer(let theirs))):
            phase = .ranging(peerToken: theirs)
            return [.run(peerToken: theirs)]
        case (.offered, .received(.offer(let theirs))):
            // Both opened at once: each answers the other's offer. Our own
            // offer already carried our token, so no reply is needed.
            phase = .ranging(peerToken: theirs)
            return [.run(peerToken: theirs)]

        case (.ranging, .received(.offer(let theirs))):
            // They reopened Find (a new session, a new token): rerun on it.
            phase = .ranging(peerToken: theirs)
            return [.run(peerToken: theirs)]

        case (.ranging, .received(.stop)), (.offered, .received(.stop)):
            phase = .offered
            return [.invalidate]
        case (.ranging, .rangingFailed), (.offered, .rangingFailed):
            phase = .fallbackOnly
            return [.invalidate]

        case (.offered, .closed), (.ranging, .closed):
            phase = .closed
            pendingOffer = nil
            return [.send(.stop), .invalidate]
        case (.fallbackOnly, .closed):
            phase = .closed
            pendingOffer = nil
            return []

        default:
            return []
        }
    }
}

extension Find {
    /// A Nearby Interaction fix as the screen shows it: whole metres and a
    /// bearing in degrees from straight ahead (positive to the right). Nil
    /// until there is a distance; a fix with no angle (the friend is behind
    /// you or out of the camera's field) shows distance with no arrow turn.
    public struct Fix: Equatable, Sendable {
        public let meters: Int
        public let bearing: Double?
    }

    public static func fix(distance: Float?, horizontalAngle: Float?) -> Fix? {
        guard let distance, distance.isFinite, distance >= 0 else { return nil }
        let bearing = horizontalAngle.flatMap { $0.isFinite ? Double($0) * 180 / .pi : nil }
        return Fix(meters: Int(distance.rounded()), bearing: bearing)
    }

    /// Seconds between haptic taps: faster as they get closer, 0.15 s at
    /// 1 m or less, 1.2 s at 30 m or more.
    public static func tapInterval(meters: Int) -> TimeInterval {
        let m = Double(min(max(meters, 1), 30))
        return 0.15 + (m - 1) / 29 * (1.2 - 0.15)
    }
}

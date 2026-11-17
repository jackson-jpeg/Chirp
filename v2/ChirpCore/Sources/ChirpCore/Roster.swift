import Foundation

/// A signed "I am here" broadcast, every few seconds, on the nearby channel.
///
/// It is how a peer's keys are learned: the origin in a packet header is just
/// 16 bytes anyone can write, but a presence is accepted only if its signing
/// key hashes to that origin and its signature checks. Floor and text messages
/// are then verified against the key learned here.
///
/// Unlike 1.0's beacon it carries no battery level and no position (a check-in
/// position travels sealed to each recipient, separately).
public struct Presence: Equatable, Sendable {
    public let signingKey: Data
    public let agreementKey: Data
    public let name: String
    public let bird: Bird
    public let sentAt: Date

    public var peer: PeerID { PeerID(signingPublicKey: signingKey) }

    /// How far a presence's clock may be from ours. Phones keep network time,
    /// but a phone in airplane mode for a week does not.
    public static let clockTolerance: TimeInterval = 10 * 60

    public init(signingKey: Data, agreementKey: Data, name: String, bird: Bird = .default, sentAt: Date) {
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        self.name = name
        self.bird = bird
        self.sentAt = sentAt
    }

    public init(identity: LocalIdentity, name: String, bird: Bird = .default, at: Date) {
        self.init(signingKey: identity.signingPublicKey, agreementKey: identity.agreementPublicKey,
                  name: name, bird: bird, sentAt: at)
    }

    private var body: Data {
        var out = Data()
        out.append(signingKey)
        out.append(agreementKey)
        out.appendBigEndian(UInt64(max(0, sentAt.timeIntervalSince1970 * 1000)))
        out.appendString(name, maxBytes: 64)
        out.append(bird.palette)
        out.append(bird.chirp)
        return out
    }

    public func signedPayload(by identity: LocalIdentity) throws -> Data {
        precondition(identity.signingPublicKey == signingKey, "presence must be signed by its own key")
        let b = body
        return b + (try identity.sign(b))
    }

    /// Nil unless well formed, signed by the key it carries, that key belongs
    /// to `origin`, and the time is within tolerance of `now`.
    public static func verify(_ payload: Data, origin: PeerID, now: Date) -> Presence? {
        var r = ByteReader(payload)
        guard let sk = r.bytes(32), let ak = r.bytes(32), let ms = r.u64(), let name = r.string(),
              let palette = r.u8(), let chirp = r.u8(), let bird = Bird(palette: palette, chirp: chirp) else { return nil }
        let bodyLength = 32 + 32 + 8 + 2 + Data(name.utf8).count + 2
        guard let sig = r.bytes(64), r.isAtEnd else { return nil }
        guard PeerID(signingPublicKey: sk) == origin,
              LocalIdentity.verify(signature: sig, of: payload.prefix(bodyLength), signingPublicKey: sk) else { return nil }
        let sentAt = Date(timeIntervalSince1970: Double(ms) / 1000)
        guard abs(sentAt.timeIntervalSince(now)) <= clockTolerance else { return nil }
        return Presence(signingKey: sk, agreementKey: ak, name: name, bird: bird, sentAt: sentAt)
    }
}

/// Who is nearby: one list, keyed by `PeerID`, fed only by verified presences.
///
/// 1.0 had four sources (transport peers by display name, a heartbeat tracker
/// by routing UUID, beacon nodes, channel rosters) that disagreed, and the
/// nearby bubbles were never filtered by the block list (audit section 5).
public struct Roster: Sendable {
    public struct Person: Equatable, Sendable, Identifiable {
        public let id: PeerID
        public var name: String
        public var bird: Bird
        public var signingKey: Data
        public var agreementKey: Data
        public var lastSeen: Date
        /// Links the newest presence crossed: 0 is direct, 1 is through one relay.
        public var hops: UInt8
    }

    /// Gone after this long without a presence or any packet.
    public static let staleAfter: TimeInterval = 15

    private var people: [PeerID: Person] = [:]
    public init() {}

    /// Returns true when this person is new to the list.
    @discardableResult
    public mutating func update(with presence: Presence, hops: UInt8, now: Date) -> Bool {
        let isNew = people[presence.peer] == nil
        people[presence.peer] = Person(id: presence.peer, name: presence.name, bird: presence.bird, signingKey: presence.signingKey,
                                       agreementKey: presence.agreementKey, lastSeen: now, hops: hops)
        return isNew
    }

    /// Any verified traffic from a known person keeps them on the list.
    public mutating func heard(_ peer: PeerID, now: Date) {
        people[peer]?.lastSeen = now
    }

    /// Removes and returns the people not heard from in `staleAfter`.
    public mutating func prune(now: Date) -> [PeerID] {
        let gone = people.values.filter { now.timeIntervalSince($0.lastSeen) > Self.staleAfter }.map(\.id)
        for id in gone { people.removeValue(forKey: id) }
        return gone
    }

    public func person(_ id: PeerID) -> Person? { people[id] }

    /// What the UI shows: never anyone blocked, nearest first, then by name.
    public func visible(excluding blocked: Set<PeerID>) -> [Person] {
        people.values
            .filter { !blocked.contains($0.id) }
            .sorted { ($0.hops, $0.name.lowercased(), $0.id) < ($1.hops, $1.name.lowercased(), $1.id) }
    }
}

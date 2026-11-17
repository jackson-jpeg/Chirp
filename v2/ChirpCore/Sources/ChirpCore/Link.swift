import Foundation

// The link layer under the router: how two phones find each other and pass
// packets, for the Network framework transport (Bonjour with peer-to-peer
// Wi-Fi, TCP). MultipeerConnectivity, which 1.0 used, is deprecated in
// Xcode 27.
//
// Held here so each rule has a test:
// - Every phone advertises its PeerID in its Bonjour service name, and of two
//   phones only the one with the lower PeerID dials: one link per pair, with
//   no invitation race (1.0 needed a tie-break on invitations).
// - Every link opens with a hello frame naming the sender's PeerID; a dialer
//   drops a link whose hello is not the PeerID it dialed.
// - Frames are length-prefixed (4 bytes, big-endian) and capped at the
//   largest packet; anything larger closes the link instead of buffering it.

public enum Link {
    public static let serviceType = "_chirpchirps._tcp"
    static let namePrefix = "chirp-"

    public static func serviceName(for peer: PeerID) -> String { namePrefix + peer.hex }

    public static func peer(fromServiceName name: String) -> PeerID? {
        guard name.hasPrefix(namePrefix) else { return nil }
        return PeerID(hex: String(name.dropFirst(namePrefix.count)))
    }

    /// Of two phones that see each other, only the lower PeerID dials.
    public static func shouldDial(local: PeerID, remote: PeerID) -> Bool { local < remote }

    // MARK: Hello

    static let helloMagic = Data("CHIRPLNK".utf8)
    static let helloVersion: UInt8 = 1

    public static func hello(_ peer: PeerID) -> Data {
        var d = helloMagic
        d.append(helloVersion)
        d.append(peer.bytes)
        return d
    }

    public static func decodeHello(_ data: Data) -> PeerID? {
        var r = ByteReader(data)
        guard r.bytes(helloMagic.count) == helloMagic, r.u8() == helloVersion,
              let b = r.bytes(16), r.isAtEnd else { return nil }
        return PeerID(bytes: b)
    }

    // MARK: Frames

    /// The largest frame a link accepts: one whole packet.
    public static let maxFrame = Packet.headerSize + Packet.maxPayload

    public static func frame(_ body: Data) -> Data {
        var d = Data(capacity: 4 + body.count)
        d.appendBigEndian(UInt32(body.count))
        d.append(body)
        return d
    }
}

/// Cuts a TCP byte stream back into frames. Once it sees an oversized or
/// empty frame it is broken for good, and the link must close.
public struct Deframer: Sendable {
    private var buffer = Data()
    public private(set) var broken = false

    public init() {}

    public mutating func push(_ chunk: Data) -> [Data] {
        guard !broken else { return [] }
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            guard buffer.count >= 4 else { break }
            let n = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard n > 0, n <= Link.maxFrame else {
                broken = true
                buffer = Data()
                return frames
            }
            guard buffer.count >= 4 + n else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(n)))
            buffer = Data(buffer.dropFirst(4 + n))
        }
        return frames
    }
}

/// Which link carries each peer. A newer link to the same peer replaces the
/// older one (the old one is usually dead after a phone came back), and a link
/// that closes removes its peer only if it is still the current one.
public struct LinkTable<ID: Hashable & Sendable>: Sendable {
    public private(set) var byPeer: [PeerID: ID] = [:]

    public init() {}

    /// Returns the link this one replaced, which the caller closes.
    public mutating func add(_ peer: PeerID, _ id: ID) -> ID? {
        let old = byPeer[peer]
        byPeer[peer] = id
        return old == id ? nil : old
    }

    /// Returns the peer that lost its link, if this was its current one.
    @discardableResult
    public mutating func remove(_ id: ID) -> PeerID? {
        guard let peer = byPeer.first(where: { $0.value == id })?.key else { return nil }
        byPeer[peer] = nil
        return peer
    }

    public var peers: Set<PeerID> { Set(byPeer.keys) }
}

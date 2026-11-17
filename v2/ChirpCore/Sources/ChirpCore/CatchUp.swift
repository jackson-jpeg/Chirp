import Foundation

/// Catch up (scope item 3): friends' phones hold texts for someone out of
/// range and hand them over, in order, when that person comes back.
///
/// How it works:
/// - Every phone holds the text-like packets it relays or receives (texts,
///   meet-ups, roll calls, help), exactly as they came off the air: still
///   sealed for a locked channel and still signed, so a holder cannot read a
///   locked channel or change anything it hands back.
/// - A phone that comes back into range sends a `CatchUpRequest` with the
///   channels it is on and the time it last heard each one.
/// - A holder answers with `CatchUpBundle`s of the matching packets, oldest
///   first. The receiver processes each inner packet like a fresh one, except
///   that it skips the router's replay window (a held packet is old by design)
///   and relies on the message ID dedup in the ledgers instead.
///
/// Caps: per origin, in total, and by age, so nobody can fill a friend's phone.
/// 1.0's store-and-forward was dropped by the audit; this is new.
public struct CatchUpStore: Sendable {
    public static let heldKinds: Set<PacketKind> = [.text, .meetup, .rollCall, .help]
    public static let maxAge: TimeInterval = 24 * 60 * 60

    public let maxTotal: Int
    public let maxPerOrigin: Int

    private struct Held { let packet: Packet; let storedAt: Date; let order: UInt64 }
    private var held: [Held] = []
    private var keys: Set<Packet.Key> = []
    private var counter: UInt64 = 0

    public init(maxTotal: Int = 500, maxPerOrigin: Int = 100) {
        self.maxTotal = maxTotal
        self.maxPerOrigin = maxPerOrigin
    }

    public var count: Int { held.count }

    /// Keep a copy of a packet for people who are not here. Returns false when
    /// it is not a kind that is held, or already held. Demo traffic and
    /// whispers are never held (a whisper is for one person, who either got it
    /// or did not).
    @discardableResult
    public mutating func hold(_ packet: Packet, now: Date) -> Bool {
        guard Self.heldKinds.contains(packet.kind), !SendGate.isDemo(packet.channel),
              !keys.contains(packet.key) else { return false }
        expire(now: now)
        counter &+= 1
        held.append(Held(packet: packet, storedAt: now, order: counter))
        keys.insert(packet.key)
        let fromOrigin = held.filter { $0.packet.origin == packet.origin }
        if fromOrigin.count > maxPerOrigin, let oldest = fromOrigin.first { drop(oldest.packet.key) }
        if held.count > maxTotal, let oldest = held.first { drop(oldest.packet.key) }
        return true
    }

    /// What to hand to someone asking about these channels, oldest first.
    /// Never their own packets, never from anyone they or we block.
    public mutating func packets(for request: CatchUpRequest, requester: PeerID, blocked: Set<PeerID>,
                                 now: Date) -> [Packet] {
        expire(now: now)
        let wanted = Dictionary(request.channels.map { ($0.channel, $0.since) }, uniquingKeysWith: max)
        return held.filter { h in
            guard let since = wanted[h.packet.channel] else { return false }
            return h.storedAt > since && h.packet.origin != requester && !blocked.contains(h.packet.origin)
        }
        .sorted { $0.order < $1.order }
        .map(\.packet)
    }

    private mutating func expire(now: Date) {
        let old = held.filter { now.timeIntervalSince($0.storedAt) > Self.maxAge }
        for h in old { drop(h.packet.key) }
    }

    private mutating func drop(_ key: Packet.Key) {
        held.removeAll { $0.packet.key == key }
        keys.remove(key)
    }
}

/// "I'm back: what did I miss on these channels since these times?"
///
/// Note on privacy: this names the channels the requester is on to whoever is
/// in range. Channel IDs are random and say nothing about a channel's name or
/// contents; a locked channel's packets stay sealed. Sent only to friends.
public struct CatchUpRequest: Equatable, Sendable {
    public static let maxChannels = 32
    public let channels: [(channel: ChannelID, since: Date)]

    public init(channels: [(channel: ChannelID, since: Date)]) {
        self.channels = Array(channels.prefix(Self.maxChannels))
    }

    public static func == (l: CatchUpRequest, r: CatchUpRequest) -> Bool {
        l.channels.count == r.channels.count
            && zip(l.channels, r.channels).allSatisfy { $0.channel == $1.channel && $0.since == $1.since }
    }

    public func encode() -> Data {
        var d = Data([1, UInt8(channels.count)])
        for c in channels {
            d.append(c.channel.bytes)
            d.appendBigEndian(UInt64(max(0, c.since.timeIntervalSince1970 * 1000)))
        }
        return d
    }

    public static func decode(_ data: Data) -> CatchUpRequest? {
        var r = ByteReader(data)
        guard r.u8() == 1, let n = r.u8(), Int(n) <= maxChannels else { return nil }
        var out: [(ChannelID, Date)] = []
        for _ in 0..<n {
            guard let b = r.bytes(16), let id = ChannelID(bytes: b), let ms = r.u64() else { return nil }
            out.append((id, Date(timeIntervalSince1970: Double(ms) / 1000)))
        }
        guard r.isAtEnd else { return nil }
        return CatchUpRequest(channels: out)
    }
}

/// Held packets, each length-prefixed, packed to fit one packet's payload.
public enum CatchUpBundle {
    /// Split `packets` (oldest first) into payloads no bigger than `limit`.
    /// A packet too big for any bundle is skipped.
    public static func pack(_ packets: [Packet], limit: Int = Packet.maxPayload) -> [Data] {
        var bundles: [Data] = []
        var current = Data([2])
        for p in packets {
            let wire = p.encode()
            guard 1 + 2 + wire.count <= limit else { continue }
            if current.count + 2 + wire.count > limit {
                bundles.append(current)
                current = Data([2])
            }
            current.appendBigEndian(UInt16(wire.count))
            current.append(wire)
        }
        if current.count > 1 { bundles.append(current) }
        return bundles
    }

    /// The packets in a bundle, in order. Nil if the bundle is malformed;
    /// inner packets that do not decode, or are not a held kind, are skipped.
    public static func unpack(_ data: Data) -> [Packet]? {
        var r = ByteReader(data)
        guard r.u8() == 2 else { return nil }
        var out: [Packet] = []
        while !r.isAtEnd {
            guard let n = r.u16(), let wire = r.bytes(Int(n)) else { return nil }
            if let p = Packet.decode(wire), CatchUpStore.heldKinds.contains(p.kind) { out.append(p) }
        }
        return out
    }
}

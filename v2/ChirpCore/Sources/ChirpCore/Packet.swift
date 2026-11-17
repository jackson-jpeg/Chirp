import Foundation

// The 2.0 wire format. Changes from 1.0 (audit sections 2, 4, 7):
// - An explicit `kind` byte. 1.0 sniffed the first four payload bytes for magic
//   strings ("ACK!", "BCN!", ...) and fell through to "try to decrypt as text,
//   then as file" for anything unknown.
// - Every packet carries a channel. 1.0 sent audio and floor messages with no
//   channel, so channels did not separate voice and one speaker blocked the
//   button for everyone in range.
// - A real hop count, incremented on relay. 1.0 inferred hops from the TTL and
//   showed "2 hops" between two phones side by side.
// - A per-launch `epoch`. Sequence numbers restart at 0 on every launch; the
//   epoch makes a relaunched sender a new stream instead of a replay, in the
//   router and in the jitter buffer (audit defect 2, claim H5).
// - No packet UUID: (origin, epoch, kind, sequence) is already unique, and 16
//   bytes saved is a quarter of an Opus frame.
//
// Layout, big-endian, 44-byte header:
//   [version:1][kind:1][ttl:1][hops:1][origin:16][epoch:4][sequence:4][channel:16][payload]

public struct ChannelID: Hashable, Sendable, CustomStringConvertible {
    public let uuid: UUID
    public init(_ uuid: UUID) { self.uuid = uuid }
    public static func random() -> ChannelID { ChannelID(UUID()) }

    /// The open channel everyone nearby is on. All zero bytes.
    public static let nearby = ChannelID(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)))
    public var isNearby: Bool { self == .nearby }

    public var bytes: Data { withUnsafeBytes(of: uuid.uuid) { Data($0) } }
    public init?(bytes: Data) {
        guard bytes.count == 16 else { return nil }
        let b = [UInt8](bytes)
        self.uuid = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
    public var description: String { uuid.uuidString }
}

public enum PacketKind: UInt8, Sendable, CaseIterable {
    case audio = 1
    case floor = 2
    case text = 3
    case ack = 4
    case presence = 5
    /// Roll call: "is everyone OK?" and its answers.
    case rollCall = 6
    /// "I need help." Its own kind so a relay can see it in the header, even on
    /// a locked channel, and send it first.
    case help = 7
    /// A meet-up spot and the replies saying who is coming.
    case meetup = 8
    /// Make a friend's phone chirp. Only on a whisper channel.
    case ping = 9
    /// Battery level. Only on a whisper channel, so only to friends.
    case battery = 10
    /// Catch-up request or bundle of held packets. One link only.
    case catchUp = 11
    /// One chunk of a small photo.
    case photo = 12
    /// Find: a Nearby Interaction discovery token for one friend. Only on a whisper channel.
    case find = 13
    /// "I am on this channel": an empty signed body, sealed with a locked
    /// channel's key, so only someone holding the key can send one. It is how
    /// the people on a locked channel become friends (`Dispatch.friends`)
    /// before they have said anything.
    case member = 14

    /// How many links a new packet of this kind may cross. Floor control has
    /// the same reach as audio on purpose: a device that cannot hear a speaker
    /// must not be told the floor is taken.
    public var initialTTL: UInt8 {
        switch self {
        case .audio, .floor, .presence, .photo: return 2   // at most one relay
        case .text, .ack, .rollCall, .help, .meetup, .ping, .battery, .find, .member: return 4
        case .catchUp: return 1   // between two phones in range, never relayed
        }
    }

    /// Whether the transport should send it reliably on the first link.
    public var reliable: Bool {
        switch self {
        case .audio: return false
        default: return true
        }
    }

    /// Send order when the radio is busy: lower goes first. Help beats
    /// everything; live voice and its floor beat stored traffic; presence and
    /// battery go last.
    public var sendPriority: Int {
        switch self {
        case .help: return 0
        case .floor: return 1
        case .audio: return 2
        case .rollCall, .ping, .find: return 3
        case .text, .ack, .meetup: return 4
        case .presence, .battery, .catchUp, .member: return 5
        case .photo: return 6
        }
    }
}

public struct Packet: Equatable, Sendable {
    public static let version: UInt8 = 2
    public static let headerSize = 44
    public static let maxTTL: UInt8 = 4
    /// MultipeerConnectivity handles larger messages, but nothing in 2.0 needs
    /// more, and a cap keeps a hostile peer from making us allocate.
    public static let maxPayload = 16 * 1024

    public let kind: PacketKind
    public var ttl: UInt8
    public var hops: UInt8
    public let origin: PeerID
    public let epoch: UInt32
    public let sequence: UInt32
    public let channel: ChannelID
    public let payload: Data

    public init(kind: PacketKind, ttl: UInt8? = nil, hops: UInt8 = 0, origin: PeerID, epoch: UInt32,
                sequence: UInt32, channel: ChannelID, payload: Data) {
        self.kind = kind
        self.ttl = min(ttl ?? kind.initialTTL, Self.maxTTL)
        self.hops = hops
        self.origin = origin
        self.epoch = epoch
        self.sequence = sequence
        self.channel = channel
        self.payload = payload
    }

    /// Identifies this packet for dedup. Unique because a sender's sequence
    /// counter is per (epoch, kind) and only goes up.
    public struct Key: Hashable, Sendable {
        public let origin: PeerID
        public let epoch: UInt32
        public let kind: PacketKind
        public let sequence: UInt32
    }
    public var key: Key { Key(origin: origin, epoch: epoch, kind: kind, sequence: sequence) }

    /// The copy a relay sends on: one fewer hop left, one more hop taken.
    /// Nil when this was the last hop.
    public func relayed() -> Packet? {
        guard ttl > 1 else { return nil }
        var copy = self
        copy.ttl -= 1
        copy.hops = hops &+ 1
        return copy
    }

    public func encode() -> Data {
        var out = Data(capacity: Self.headerSize + payload.count)
        out.append(Self.version)
        out.append(kind.rawValue)
        out.append(ttl)
        out.append(hops)
        out.append(origin.bytes)
        out.appendBigEndian(epoch)
        out.appendBigEndian(sequence)
        out.append(channel.bytes)
        out.append(payload)
        return out
    }

    /// Nil for anything malformed, of another version, over the size cap, or
    /// with a TTL above the ceiling. Never traps, whatever the input.
    public static func decode(_ data: Data) -> Packet? {
        var r = ByteReader(data)
        guard data.count >= headerSize, data.count <= headerSize + maxPayload,
              r.u8() == version,
              let kindByte = r.u8(), let kind = PacketKind(rawValue: kindByte),
              let ttl = r.u8(), ttl >= 1, ttl <= maxTTL,
              let hops = r.u8(),
              let originBytes = r.bytes(16), let origin = PeerID(bytes: originBytes),
              let epoch = r.u32(), let sequence = r.u32(),
              let channelBytes = r.bytes(16), let channel = ChannelID(bytes: channelBytes)
        else { return nil }
        return Packet(kind: kind, ttl: ttl, hops: hops, origin: origin, epoch: epoch,
                      sequence: sequence, channel: channel, payload: r.rest())
    }
}

// MARK: - Byte helpers

/// Reads by offset from the start, so it is safe on a `Data` slice (1.0 once
/// crashed on `data[0]` of a slice).
struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0
    init(_ data: Data) { self.bytes = [UInt8](data) }

    mutating func u8() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func u16() -> UInt16? {
        guard let b = self.bytes(2) else { return nil }
        return b.reduce(0) { $0 << 8 | UInt16($1) }
    }
    mutating func u32() -> UInt32? {
        guard let b = self.bytes(4) else { return nil }
        return b.reduce(0) { $0 << 8 | UInt32($1) }
    }
    mutating func u64() -> UInt64? {
        guard let b = self.bytes(8) else { return nil }
        return b.reduce(0) { $0 << 8 | UInt64($1) }
    }
    mutating func bytes(_ n: Int) -> Data? {
        guard n >= 0, offset + n <= bytes.count else { return nil }
        defer { offset += n }
        return Data(bytes[offset..<offset + n])
    }
    /// A length-prefixed (UInt16) UTF-8 string.
    mutating func string() -> String? {
        guard let n = u16(), let b = self.bytes(Int(n)) else { return nil }
        return String(data: b, encoding: .utf8)
    }
    mutating func rest() -> Data {
        defer { offset = bytes.count }
        return Data(bytes[min(offset, bytes.count)...])
    }
    var isAtEnd: Bool { offset >= bytes.count }
}

extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
    /// A length-prefixed (UInt16) UTF-8 string, truncated to fit.
    mutating func appendString(_ s: String, maxBytes: Int = 256) {
        var utf8 = Data(s.utf8)
        if utf8.count > maxBytes {
            // Cut on a character boundary so the far side can decode it.
            var cut = ""
            for ch in s { if Data((cut + String(ch)).utf8).count > maxBytes { break }; cut.append(ch) }
            utf8 = Data(cut.utf8)
        }
        appendBigEndian(UInt16(utf8.count))
        append(utf8)
    }
}

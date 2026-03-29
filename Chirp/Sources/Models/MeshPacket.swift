import Foundation

/// Mesh-aware packet that can be relayed through intermediate devices.
/// Every ChirpChirp device forwards packets it receives to extend range.
///
/// Wire format (fixed header = 46 bytes + variable channel + payload):
///   [type:1][ttl:1][originID:16][packetID:16][sequence:4][timestamp:8]
///   [channelLen:2][channelUTF8:N][payload:remaining]
struct MeshPacket: Sendable {

    // MARK: - Header (46 bytes fixed)

    /// Distinguishes audio data from control messages.
    let type: PacketType       // 1 byte
    /// Hops remaining before the packet is dropped.
    var ttl: UInt8             // 1 byte
    /// Original sender -- never changes across relays.
    let originID: UUID         // 16 bytes
    /// Unique per packet, used for deduplication.
    let packetID: UUID         // 16 bytes
    /// Monotonic sequence number within a PTT session.
    let sequenceNumber: UInt32 // 4 bytes big-endian
    /// Milliseconds since Unix epoch when the packet was created.
    let timestamp: UInt64      // 8 bytes big-endian

    // MARK: - Payload

    /// Target channel identifier. Empty string means broadcast.
    let channelID: String
    /// Opus-encoded audio or JSON-encoded control message.
    let payload: Data

    // MARK: - Types

    enum PacketType: UInt8, Sendable {
        case audio   = 0x01
        case control = 0x02
    }

    /// Priority level for relay decisions and adaptive TTL computation.
    enum MessagePriority: UInt8, Comparable, Sendable {
        case low = 0        // Audio relay
        case normal = 1     // Beacons
        case high = 2       // Text messages, location shares
        case critical = 3   // SOS / Emergency

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Constants

    /// Default hop count for new packets.
    static let defaultTTL: UInt8 = 4
    /// Absolute ceiling -- packets created with a higher TTL are clamped.
    static let maxTTL: UInt8 = 8
    /// Minimum valid wire-format size (header + 2-byte channel length + 0 channel + 0 payload).
    private static let minWireSize = 48 // 46 header + 2 channel-length

    // MARK: - Adaptive TTL

    /// Compute a TTL tailored to the packet's type and priority.
    /// Higher-priority messages propagate further through the mesh.
    static func adaptiveTTL(for type: PacketType, priority: MessagePriority) -> UInt8 {
        switch priority {
        case .critical: return 8   // SOS: max reach
        case .high:     return 6   // Text: wide propagation
        case .normal:   return 4   // Beacons: medium
        case .low:      return 2   // Audio: real-time, no point relaying far
        }
    }

    /// Infer priority from packet content heuristics.
    static func inferPriority(type: PacketType, payload: Data) -> MessagePriority {
        switch type {
        case .audio:
            return .low
        case .control:
            // Check for SOS marker in the payload (JSON key "sos" or beacon magic)
            if payload.count >= 4 {
                // Look for SOS marker -- matches {"type":"SOS"}, {"sos":...}, etc.
                if let text = String(data: payload, encoding: .utf8),
                   text.localizedCaseInsensitiveContains("\"sos\"") {
                    return .critical
                }
                // Beacons start with "BCN!" magic
                let magic: [UInt8] = [0x42, 0x43, 0x4E, 0x21]
                if Array(payload.prefix(4)) == magic {
                    return .normal
                }
                // Sound alerts: SND! magic
                let sndMagic: [UInt8] = [0x53, 0x4E, 0x44, 0x21]
                if Array(payload.prefix(4)) == sndMagic {
                    return .high
                }
                // Delivery ACKs: ACK! magic -- lightweight, relay at normal priority
                let ackMagic: [UInt8] = [0x41, 0x43, 0x4B, 0x21]
                if Array(payload.prefix(4)) == ackMagic {
                    return .normal
                }
                // File transfer prefixes: FIL!, FLC!, FNK!
                let filMagic: [UInt8] = [0x46, 0x49, 0x4C, 0x21]
                let flcMagic: [UInt8] = [0x46, 0x4C, 0x43, 0x21]
                let fnkMagic: [UInt8] = [0x46, 0x4E, 0x4B, 0x21]
                let prefix4 = Array(payload.prefix(4))
                if prefix4 == filMagic || prefix4 == flcMagic || prefix4 == fnkMagic {
                    return .normal
                }
                // Mesh Cloud: BCK! (backup chunk) — not urgent
                let bckMagic: [UInt8] = [0x42, 0x43, 0x4B, 0x21]
                if prefix4 == bckMagic {
                    return .normal
                }
                // Mesh Cloud: BRQ! (backup retrieval request) — user waiting
                let brqMagic: [UInt8] = [0x42, 0x52, 0x51, 0x21]
                if prefix4 == brqMagic {
                    return .high
                }
            }
            return .high
        }
    }

    // MARK: - Serialization

    /// Encode the packet into its binary wire format.
    func serialize() -> Data {
        var data = Data()
        data.reserveCapacity(Self.minWireSize + channelID.utf8.count + payload.count)

        // Type (1)
        data.append(type.rawValue)

        // TTL (1)
        data.append(ttl)

        // Origin ID (16)
        data.append(contentsOf: uuidBytes(originID))

        // Packet ID (16)
        data.append(contentsOf: uuidBytes(packetID))

        // Sequence number (4, big-endian)
        var seq = sequenceNumber.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &seq) { Array($0) })

        // Timestamp (8, big-endian)
        var ts = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &ts) { Array($0) })

        // Channel ID length (2, big-endian) + UTF-8 bytes
        let channelData = Data(channelID.utf8)
        guard channelData.count <= UInt16.max else {
            // Truncate silently -- should never happen in practice.
            let truncated = Data(channelData.prefix(Int(UInt16.max)))
            var len = UInt16(truncated.count).bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &len) { Array($0) })
            data.append(truncated)
            data.append(payload)
            return data
        }
        var channelLen = UInt16(channelData.count).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &channelLen) { Array($0) })
        data.append(channelData)

        // Payload (remaining)
        data.append(payload)

        return data
    }

    /// Decode a packet from its binary wire format.
    /// Returns `nil` if the data is malformed or too short.
    static func deserialize(_ data: Data) -> MeshPacket? {
        guard data.count >= minWireSize else { return nil }

        var offset = 0

        // Type (1)
        guard let packetType = PacketType(rawValue: data[offset]) else { return nil }
        offset += 1

        // TTL (1)
        let ttl = data[offset]
        guard ttl <= maxTTL else { return nil }
        offset += 1

        // Origin ID (16)
        guard let originID = uuid(from: data, at: offset) else { return nil }
        offset += 16

        // Packet ID (16)
        guard let packetID = uuid(from: data, at: offset) else { return nil }
        offset += 16

        // Sequence number (4)
        let seq: UInt32 = readBigEndian(data, at: offset)
        offset += 4

        // Timestamp (8)
        let ts: UInt64 = readBigEndian(data, at: offset)
        offset += 8

        // Channel ID length (2)
        guard offset + 2 <= data.count else { return nil }
        let channelLen: UInt16 = readBigEndian(data, at: offset)
        offset += 2

        // Channel ID (N)
        guard offset + Int(channelLen) <= data.count else { return nil }
        let channelData = data[offset ..< offset + Int(channelLen)]
        guard let channelID = String(data: channelData, encoding: .utf8) else { return nil }
        offset += Int(channelLen)

        // Payload (remaining)
        let payload = data[offset...]

        return MeshPacket(
            type: packetType,
            ttl: ttl,
            originID: originID,
            packetID: packetID,
            sequenceNumber: seq,
            timestamp: ts,
            channelID: channelID,
            payload: Data(payload)
        )
    }

    // MARK: - Forwarding

    /// Create a relay copy with TTL decremented by one.
    /// Returns `nil` when the packet has no remaining hops.
    func forwarded() -> MeshPacket? {
        guard ttl > 1 else { return nil }
        return MeshPacket(
            type: type,
            ttl: ttl - 1,
            originID: originID,
            packetID: packetID,
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            channelID: channelID,
            payload: payload
        )
    }

    // MARK: - Private helpers

    /// Convert a UUID to its 16-byte representation.
    private func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let u = uuid.uuid
        return [
            u.0, u.1, u.2,  u.3,  u.4,  u.5,  u.6,  u.7,
            u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15
        ]
    }

    /// Reconstruct a UUID from 16 raw bytes in `data` starting at `offset`.
    private static func uuid(from data: Data, at offset: Int) -> UUID? {
        guard offset + 16 <= data.count else { return nil }
        let bytes = data[offset ..< offset + 16]
        let b = Array(bytes)
        return UUID(uuid: (
            b[0],  b[1],  b[2],  b[3],
            b[4],  b[5],  b[6],  b[7],
            b[8],  b[9],  b[10], b[11],
            b[12], b[13], b[14], b[15]
        ))
    }

    /// Read a fixed-width big-endian integer from `data` at `offset`.
    private static func readBigEndian<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
        let size = MemoryLayout<T>.size
        var value: T = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data[offset ..< offset + size].copyBytes(to: dest)
        }
        return T(bigEndian: value)
    }
}

import Foundation

/// Lightweight delivery acknowledgment sent back along the relay path.
/// When a message is successfully delivered, the recipient sends this ACK
/// so relay nodes can strengthen their pheromone trails.
struct DeliveryACK: Codable, Sendable {
    /// The packet ID that was successfully delivered.
    let ackedPacketID: UUID
    /// The original sender's peer ID (destination for the ACK's return path).
    let originalSenderID: String
    /// The acknowledging peer's ID.
    let ackerID: String
    /// Channel the original message was on.
    let channelID: String
    /// Hop count: incremented each relay hop on the return path.
    var hopCount: UInt8

    /// Magic prefix: ACK! (0x41 0x43 0x4B 0x21)
    static let magicPrefix: [UInt8] = [0x41, 0x43, 0x4B, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> DeliveryACK? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(DeliveryACK.self, from: Data(json))
    }
}

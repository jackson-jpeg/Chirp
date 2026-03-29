import Foundation

/// Scan results shared across the mesh network.
struct MeshScanReport: Codable, Sendable {
    let senderID: String
    let senderName: String
    let devices: [BLEDevice]
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    /// ASCII "SCN!" — 0x53 0x43 0x4E 0x21
    static let magicPrefix: [UInt8] = [0x53, 0x43, 0x4E, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> MeshScanReport? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(MeshScanReport.self, from: Data(json))
    }
}

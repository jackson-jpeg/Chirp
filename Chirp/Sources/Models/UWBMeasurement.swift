import Foundation
import simd

/// A single UWB distance + direction measurement between two peers.
/// Produced by UWBService from NearbyInteraction NISession updates.
struct UWBMeasurement: Codable, Sendable, Identifiable {
    let id: UUID
    let localPeerID: String
    let remotePeerID: String
    /// Distance in meters between the two devices.
    let distanceMeters: Float
    /// Unit vector in the local device's coordinate frame pointing toward the remote peer.
    /// Nil when direction is unavailable (some older devices only provide distance).
    let directionX: Float?
    let directionY: Float?
    let directionZ: Float?
    let timestamp: Date

    init(
        localPeerID: String,
        remotePeerID: String,
        distanceMeters: Float,
        direction: SIMD3<Float>? = nil,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.localPeerID = localPeerID
        self.remotePeerID = remotePeerID
        self.distanceMeters = distanceMeters
        self.directionX = direction?.x
        self.directionY = direction?.y
        self.directionZ = direction?.z
        self.timestamp = timestamp
    }

    /// Reconstructed direction vector, nil if components unavailable.
    var direction: SIMD3<Float>? {
        guard let x = directionX, let y = directionY, let z = directionZ else { return nil }
        return SIMD3<Float>(x, y, z)
    }
}

/// Token exchange packet for bootstrapping UWB sessions.
/// Sent as mesh control packet with UWB! magic prefix, TTL 1 (direct peers only).
struct UWBTokenExchange: Codable, Sendable {
    let peerID: String
    let discoveryToken: Data    // NIDiscoveryToken serialized
    let timestamp: Date

    /// Magic prefix for UWB token exchange packets.
    static let magicPrefix: [UInt8] = [0x55, 0x57, 0x42, 0x21] // "UWB!"

    func wirePayload() -> Data {
        var payload = Data(Self.magicPrefix)
        if let json = try? MeshCodable.encoder.encode(self) {
            payload.append(json)
        }
        return payload
    }

    static func from(payload: Data) -> UWBTokenExchange? {
        guard payload.count > magicPrefix.count else { return nil }
        let prefix = Array(payload.prefix(magicPrefix.count))
        guard prefix == magicPrefix else { return nil }
        let jsonData = payload.dropFirst(magicPrefix.count)
        return try? MeshCodable.decoder.decode(UWBTokenExchange.self, from: Data(jsonData))
    }
}

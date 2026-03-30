import Foundation

/// A WiFi/BLE signal observation at a known position.
/// Used by LIGHTHOUSE for crowd-sourced indoor positioning.
struct WiFiFingerprint: Codable, Sendable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let floorLevel: Int?
    let observations: [RadioObservation]
    let timestamp: Date
    let contributorPeerID: String

    init(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        floorLevel: Int? = nil,
        observations: [RadioObservation],
        contributorPeerID: String,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.floorLevel = floorLevel
        self.observations = observations
        self.timestamp = timestamp
        self.contributorPeerID = contributorPeerID
    }

    /// Reconstruct from persisted storage with a known ID.
    init(
        storedID: UUID,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        floorLevel: Int?,
        observations: [RadioObservation],
        contributorPeerID: String,
        timestamp: Date
    ) {
        self.id = storedID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.floorLevel = floorLevel
        self.observations = observations
        self.timestamp = timestamp
        self.contributorPeerID = contributorPeerID
    }
}

/// A single radio signal observation (WiFi BSSID or BLE beacon).
struct RadioObservation: Codable, Sendable {
    /// MAC address of WiFi AP or BLE beacon UUID.
    let identifier: String
    /// Signal type for disambiguation.
    let type: RadioType
    /// Signal strength in dBm.
    let rssi: Int
    /// WiFi SSID (may be nil for hidden networks or BLE beacons).
    let ssid: String?
    /// WiFi channel or BLE major/minor encoded.
    let channel: Int?

    enum RadioType: String, Codable, Sendable {
        case wifi
        case bleBeacon
    }
}

/// LIGHTHOUSE mesh sharing packets.
enum LighthousePacket {
    /// Query for LIGHTHOUSE data near a geohash.
    struct Query: Codable, Sendable {
        let requestID: UUID
        let geohashPrefix: String   // 4-6 char geohash for area of interest
        let requestorPeerID: String
        let timestamp: Date

        static let magicPrefix: [UInt8] = [0x4C, 0x48, 0x51, 0x21] // "LHQ!"

        func wirePayload() -> Data {
            var payload = Data(Self.magicPrefix)
            if let json = try? MeshCodable.encoder.encode(self) {
                payload.append(json)
            }
            return payload
        }

        static func from(payload: Data) -> Query? {
            guard payload.count > magicPrefix.count else { return nil }
            let prefix = Array(payload.prefix(magicPrefix.count))
            guard prefix == magicPrefix else { return nil }
            return try? MeshCodable.decoder.decode(Query.self, from: Data(payload.dropFirst(magicPrefix.count)))
        }
    }

    /// Response with LIGHTHOUSE data for a region.
    struct Record: Codable, Sendable {
        let requestID: UUID
        let regionHash: String          // Geohash of the area center
        let fingerprints: [WiFiFingerprint]
        let breadcrumbCount: Int        // Summary, not full trail data
        let version: UInt32
        let lastUpdated: Date

        static let magicPrefix: [UInt8] = [0x4C, 0x48, 0x52, 0x21] // "LHR!"

        func wirePayload() -> Data {
            var payload = Data(Self.magicPrefix)
            if let json = try? MeshCodable.encoder.encode(self) {
                payload.append(json)
            }
            return payload
        }

        static func from(payload: Data) -> Record? {
            guard payload.count > magicPrefix.count else { return nil }
            let prefix = Array(payload.prefix(magicPrefix.count))
            guard prefix == magicPrefix else { return nil }
            return try? MeshCodable.decoder.decode(Record.self, from: Data(payload.dropFirst(magicPrefix.count)))
        }
    }
}

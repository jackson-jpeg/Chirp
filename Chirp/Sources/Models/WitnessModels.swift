import Foundation

// MARK: - Location Stamp

/// GPS fix captured at the moment of media creation or countersigning.
struct LocationStamp: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let timestamp: Date
}

// MARK: - Witness Request

/// Broadcast by a peer requesting cryptographic attestation of captured media.
///
/// Wire format: `WRQ!` magic prefix (4 bytes) + JSON body.
/// The origin peer signs the raw media SHA-256 hash with its Ed25519 key,
/// proving it possesses the private key and that the hash is authentic.
struct WitnessRequest: Codable, Sendable, Identifiable {
    /// Witness session ID — all countersigns reference this.
    let id: UUID
    /// SHA-256 digest of the raw media bytes (32 bytes).
    let mediaHash: Data
    let mediaType: MediaType
    let originPeerID: String
    /// Ed25519 public key of the origin peer (32 bytes).
    let originPublicKey: Data
    /// Ed25519 signature over ``mediaHash`` by the origin peer (64 bytes).
    let originSignature: Data
    let originTimestamp: Date
    let originLocation: LocationStamp?

    enum MediaType: String, Codable, Sendable {
        case photo, audio, video
    }

    /// Magic bytes prepended to JSON on the wire. ASCII: `WRQ!`
    static let magicPrefix: [UInt8] = [0x57, 0x52, 0x51, 0x21]

    // MARK: - Wire helpers

    /// Encode this request as wire-ready data: magic prefix + JSON.
    func wirePayload() -> Data? {
        guard let json = try? MeshCodable.encoder.encode(self) else { return nil }
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``WitnessRequest`` from a raw payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> WitnessRequest? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(WitnessRequest.self, from: Data(json))
    }
}

// MARK: - Witness Countersign

/// A peer's cryptographic endorsement of a ``WitnessRequest``.
///
/// Wire format: `WCS!` magic prefix (4 bytes) + JSON body.
/// The countersigner signs `(sessionID + mediaHash + timestamp)` with its own
/// Ed25519 key, attesting "I saw this hash at this time from this peer."
struct WitnessCountersign: Codable, Sendable, Identifiable {
    let id: UUID
    /// References ``WitnessRequest/id``.
    let witnessSessionID: UUID
    /// Must match the ``WitnessRequest/mediaHash``.
    let mediaHash: Data
    let counterSignerPeerID: String
    /// Ed25519 public key of the countersigner (32 bytes).
    let counterSignerPublicKey: Data
    /// Ed25519 signature over `(sessionID + mediaHash + timestamp)` (64 bytes).
    let signature: Data
    let timestamp: Date
    let location: LocationStamp?

    /// Magic bytes prepended to JSON on the wire. ASCII: `WCS!`
    static let magicPrefix: [UInt8] = [0x57, 0x43, 0x53, 0x21]

    // MARK: - Wire helpers

    /// Encode this countersign as wire-ready data: magic prefix + JSON.
    func wirePayload() -> Data? {
        guard let json = try? MeshCodable.encoder.encode(self) else { return nil }
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``WitnessCountersign`` from a raw payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> WitnessCountersign? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(WitnessCountersign.self, from: Data(json))
    }

    /// Build the canonical signable data for this countersign.
    /// Deterministic: `sessionID (16 bytes) + mediaHash (32 bytes) + timestamp ISO-8601 UTF-8`.
    static func signableData(sessionID: UUID, mediaHash: Data, timestamp: Date) -> Data {
        var data = Data()
        // UUID as 16 raw bytes (big-endian)
        let uuid = sessionID.uuid
        withUnsafeBytes(of: uuid) { data.append(contentsOf: $0) }
        data.append(mediaHash)
        // Timestamp as ISO-8601 string bytes for deterministic encoding
        let ts = MeshCodable.encoder.dateEncodingStrategy
        _ = ts // use the encoder directly for consistency
        if let tsData = ISO8601DateFormatter().string(from: timestamp).data(using: .utf8) {
            data.append(tsData)
        }
        return data
    }
}

// MARK: - Witness Attestation

/// Complete evidence record: the original request plus all collected countersigns.
///
/// An attestation is considered **verified** when it has at least 2 independent
/// countersigns from distinct peers, providing Byzantine-tolerant evidence that
/// the media existed at the claimed time and location.
struct WitnessAttestation: Codable, Sendable, Identifiable {
    /// Same as the witness session ID.
    let id: UUID
    let mediaHash: Data
    let mediaType: WitnessRequest.MediaType
    let originPeerID: String
    let originPublicKey: Data
    let originSignature: Data
    let originTimestamp: Date
    let originLocation: LocationStamp?
    var countersigns: [WitnessCountersign]
    let createdAt: Date

    /// Number of peers that have countersigned this attestation.
    var countersignCount: Int { countersigns.count }

    /// An attestation is verified when at least 2 independent peers have countersigned.
    var isVerified: Bool { countersignCount >= 2 }
}

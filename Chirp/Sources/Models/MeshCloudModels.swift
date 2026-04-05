import Foundation

/// Metadata for a mesh backup.
struct BackupMetadata: Codable, Sendable, Identifiable {
    let id: UUID  // backupID
    let ownerPeerID: String
    let ownerFingerprint: String
    let fileName: String
    let totalSize: UInt64
    let chunkCount: UInt16
    let threshold: Int  // k -- minimum shares to reconstruct
    let totalShares: Int  // n
    let timestamp: Date
    let fileHash: Data?  // SHA-256 of original plaintext for integrity verification
}

/// A backup chunk carrying an encrypted file piece + key shard.
struct BackupChunk: Codable, Sendable {
    let backupID: UUID
    let chunkIndex: UInt16
    let encryptedData: Data
    let keyShard: ShamirSplitter.Share?  // Only first chunk carries the shard for each peer
    let metadata: BackupMetadata?  // Only first chunk carries metadata
    let expiresAt: Date

    static let magicPrefix: [UInt8] = [0x42, 0x43, 0x4B, 0x21] // BCK!

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> BackupChunk? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(BackupChunk.self, from: Data(json))
    }
}

/// Request to retrieve a backup from the mesh.
struct BackupRetrievalRequest: Codable, Sendable {
    let backupID: UUID
    let requestingPeerID: String
    let requestingFingerprint: String

    static let magicPrefix: [UInt8] = [0x42, 0x52, 0x51, 0x21] // BRQ!

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> BackupRetrievalRequest? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(BackupRetrievalRequest.self, from: Data(json))
    }
}

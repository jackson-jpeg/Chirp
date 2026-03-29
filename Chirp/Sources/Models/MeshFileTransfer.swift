import Foundation
import CryptoKit

/// Metadata sent before file chunks begin. Uses FIL! magic prefix.
struct FileTransferMetadata: Codable, Sendable, Identifiable {
    let id: UUID           // transferID
    let senderID: String
    let senderName: String
    let channelID: String
    let fileName: String
    let mimeType: String
    let totalSize: UInt64
    let chunkCount: UInt16
    let fileSHA256: Data   // 32 bytes
    let timestamp: Date

    /// ASCII "FIL!" -- 0x46 0x49 0x4C 0x21
    static let magicPrefix: [UInt8] = [0x46, 0x49, 0x4C, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> FileTransferMetadata? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(FileTransferMetadata.self, from: Data(json))
    }
}

/// Individual file chunk. Uses FLC! magic prefix + binary header for efficiency.
struct FileChunk: Sendable {
    let transferID: UUID
    let chunkIndex: UInt16
    let data: Data

    /// ASCII "FLC!" -- 0x46 0x4C 0x43 0x21
    static let magicPrefix: [UInt8] = [0x46, 0x4C, 0x43, 0x21]

    /// Max chunk data size in bytes.
    static let maxChunkSize = 2048

    /// Wire: [FLC!:4][transferID:16][chunkIndex:2 BE][data:remaining]
    func wirePayload() -> Data {
        var payload = Data(Self.magicPrefix)
        // transferID as 16 bytes
        let uuid = transferID.uuid
        payload.append(contentsOf: [
            uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ])
        // chunkIndex big-endian
        var idx = chunkIndex.bigEndian
        payload.append(contentsOf: withUnsafeBytes(of: &idx) { Array($0) })
        // data
        payload.append(data)
        return payload
    }

    static func from(payload: Data) -> FileChunk? {
        let prefix = Data(magicPrefix)
        // 4 magic + 16 UUID + 2 index = 22 header minimum
        guard payload.count > 22,
              payload.prefix(4) == prefix else { return nil }

        var offset = 4
        // transferID
        let uuidBytes = Array(payload[offset..<offset+16])
        let uuid = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        offset += 16

        // chunkIndex
        var rawIndex: UInt16 = 0
        _ = withUnsafeMutableBytes(of: &rawIndex) { dest in
            payload[offset..<offset+2].copyBytes(to: dest)
        }
        let chunkIndex = UInt16(bigEndian: rawIndex)
        offset += 2

        let data = Data(payload[offset...])
        return FileChunk(transferID: uuid, chunkIndex: chunkIndex, data: data)
    }
}

/// Request for missing chunks (NACK). Uses FNK! magic.
struct FileChunkRequest: Codable, Sendable {
    let transferID: UUID
    let requestingPeerID: String
    let missingIndices: [UInt16]

    static let magicPrefix: [UInt8] = [0x46, 0x4E, 0x4B, 0x21] // FNK!

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> FileChunkRequest? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else { return nil }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(FileChunkRequest.self, from: Data(json))
    }
}

import Foundation

// MARK: - ChorusPipelineOffer

/// A peer's offer to participate in a distributed pipeline inference session.
///
/// Sent in response to a pipeline request broadcast. The coordinator collects
/// offers and partitions model layers weighted by ``computeCapability``.
struct ChorusPipelineOffer: Codable, Sendable {
    let peerID: String
    let modelID: String
    let availableMemoryMB: Int
    /// Rough TFLOPS estimate for scheduling layer assignments.
    let computeCapability: Int
    let batteryLevel: Float
    let isCharging: Bool

    /// ASCII: `CHO!`
    static let magicPrefix: [UInt8] = [0x43, 0x48, 0x4F, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> ChorusPipelineOffer? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(ChorusPipelineOffer.self, from: Data(json))
    }
}

// MARK: - ChorusPipelineConfig

/// Configuration for a distributed pipeline, assigning layer ranges to peers.
///
/// Each ``PipelineStage`` maps a contiguous range of model layers to a specific
/// peer. Activations flow sequentially through stages.
struct ChorusPipelineConfig: Codable, Sendable, Identifiable {
    let id: UUID
    let modelID: String
    let stages: [PipelineStage]
    let totalLayers: Int

    struct PipelineStage: Codable, Sendable {
        let peerID: String
        let startLayer: Int
        let endLayer: Int
    }

    /// ASCII: `CHC!`
    static let magicPrefix: [UInt8] = [0x43, 0x48, 0x43, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> ChorusPipelineConfig? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(ChorusPipelineConfig.self, from: Data(json))
    }
}

// MARK: - ChorusActivation

/// Intermediate tensor data flowing between pipeline stages.
///
/// Uses a compact binary wire format (not JSON) for efficiency since tensor
/// payloads can be large and benefit from zero-copy semantics.
///
/// Wire format:
/// ```
/// [CHR!:4][pipelineID:16][stageIndex:1][inputIndex:4]
/// [shapeCount:2][shapes:N*4][dataType:1][tensorData:remaining]
/// ```
struct ChorusActivation: Sendable {
    let pipelineID: UUID
    let stageIndex: UInt8
    let inputIndex: UInt32
    let tensorData: Data
    let shape: [Int]
    let dataType: TensorDataType

    enum TensorDataType: UInt8, Sendable {
        case float16 = 0
        case float32 = 1
    }

    /// ASCII: `CHR!`
    static let magicPrefix: [UInt8] = [0x43, 0x48, 0x52, 0x21]

    /// Encode to binary wire format.
    func wirePayload() -> Data {
        var data = Data()
        let estimatedSize = 4 + 16 + 1 + 4 + 2 + shape.count * 4 + 1 + tensorData.count
        data.reserveCapacity(estimatedSize)

        // Magic prefix (4 bytes)
        data.append(contentsOf: Self.magicPrefix)

        // Pipeline ID (16 bytes)
        let uuid = pipelineID.uuid
        data.append(contentsOf: [
            uuid.0, uuid.1, uuid.2,  uuid.3,  uuid.4,  uuid.5,  uuid.6,  uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15
        ])

        // Stage index (1 byte)
        data.append(stageIndex)

        // Input index (4 bytes, big-endian)
        var idx = inputIndex.bigEndian
        withUnsafeBytes(of: &idx) { data.append(contentsOf: $0) }

        // Shape count (2 bytes, big-endian)
        var shapeCount = UInt16(clamping: shape.count).bigEndian
        withUnsafeBytes(of: &shapeCount) { data.append(contentsOf: $0) }

        // Shape dimensions (N * 4 bytes, big-endian int32)
        for dim in shape {
            var d = Int32(clamping: dim).bigEndian
            withUnsafeBytes(of: &d) { data.append(contentsOf: $0) }
        }

        // Data type (1 byte)
        data.append(dataType.rawValue)

        // Tensor data (remaining bytes)
        data.append(tensorData)

        return data
    }

    /// Decode from binary wire format.
    static func from(payload: Data) -> ChorusActivation? {
        // Minimum size: magic(4) + uuid(16) + stage(1) + input(4) + shapeCount(2) + dataType(1) = 28
        let minSize = 28
        guard payload.count >= minSize else { return nil }

        // Verify magic
        guard Array(payload.prefix(4)) == magicPrefix else { return nil }

        var offset = 4

        // Pipeline ID (16 bytes)
        guard offset + 16 <= payload.count else { return nil }
        let uuidBytes = Array(payload[offset..<offset + 16])
        let pipelineID = UUID(uuid: (
            uuidBytes[0],  uuidBytes[1],  uuidBytes[2],  uuidBytes[3],
            uuidBytes[4],  uuidBytes[5],  uuidBytes[6],  uuidBytes[7],
            uuidBytes[8],  uuidBytes[9],  uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
        offset += 16

        // Stage index (1 byte)
        let stageIndex = payload[offset]
        offset += 1

        // Input index (4 bytes, big-endian)
        guard offset + 4 <= payload.count else { return nil }
        let inputIndex = readBigEndianUInt32(payload, at: offset)
        offset += 4

        // Shape count (2 bytes, big-endian)
        guard offset + 2 <= payload.count else { return nil }
        let shapeCount = readBigEndianUInt16(payload, at: offset)
        offset += 2

        // Shape dimensions
        guard offset + Int(shapeCount) * 4 <= payload.count else { return nil }
        var shape: [Int] = []
        shape.reserveCapacity(Int(shapeCount))
        for _ in 0..<shapeCount {
            let dim = readBigEndianInt32(payload, at: offset)
            shape.append(Int(dim))
            offset += 4
        }

        // Data type (1 byte)
        guard offset + 1 <= payload.count else { return nil }
        guard let dataType = TensorDataType(rawValue: payload[offset]) else { return nil }
        offset += 1

        // Tensor data (remaining)
        let tensorData = Data(payload[offset...])

        return ChorusActivation(
            pipelineID: pipelineID,
            stageIndex: stageIndex,
            inputIndex: inputIndex,
            tensorData: tensorData,
            shape: shape,
            dataType: dataType
        )
    }

    // MARK: - Private Helpers

    private static func readBigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 { value = (value << 8) | UInt32(data[offset + i]) }
        return value
    }

    private static func readBigEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readBigEndianInt32(_ data: Data, at offset: Int) -> Int32 {
        var value: Int32 = 0
        for i in 0..<4 { value = (value << 8) | Int32(data[offset + i]) }
        return value
    }
}

// MARK: - ChorusResult

/// Final result from a completed pipeline inference pass.
struct ChorusResult: Codable, Sendable {
    let pipelineID: UUID
    let inputIndex: UInt32
    let resultData: Data
    let timestamp: Date

    /// ASCII: `CHX!`
    static let magicPrefix: [UInt8] = [0x43, 0x48, 0x58, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> ChorusResult? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(ChorusResult.self, from: Data(json))
    }
}

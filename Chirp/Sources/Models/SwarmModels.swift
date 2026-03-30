import Foundation

// MARK: - SwarmJob

/// A distributed compute job that can be parallelized across mesh peers.
///
/// The originator splits work into units, advertises the job, and collects
/// results from participating nodes.
struct SwarmJob: Codable, Sendable, Identifiable {
    let id: UUID
    let originatorID: String
    let modelID: String
    let description: String
    let totalUnits: UInt32
    let priority: SwarmPriority
    let createdAt: Date
    let deadline: Date?

    enum SwarmPriority: String, Codable, Sendable {
        /// BGProcessingTask — hours of latency acceptable.
        case background
        /// Real-time — users are actively waiting for results.
        case foreground
    }
}

// MARK: - SwarmWorkUnit

/// A single unit of work within a ``SwarmJob``.
///
/// Assigned to a specific peer for execution. The peer loads the referenced
/// CoreML model, runs inference on ``inputData``, and returns a ``SwarmWorkResult``.
struct SwarmWorkUnit: Codable, Sendable, Identifiable {
    let id: UUID
    let jobID: UUID
    let unitIndex: UInt32
    let assignedPeerID: String
    let modelID: String
    let inputData: Data
    let timestamp: Date

    /// ASCII: `SWM!`
    static let magicPrefix: [UInt8] = [0x53, 0x57, 0x4D, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        // Sub-type byte: 0x01 = work unit
        data.append(0x01)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> SwarmWorkUnit? {
        let prefixLen = magicPrefix.count + 1 // magic + sub-type byte
        guard payload.count > prefixLen,
              Array(payload.prefix(magicPrefix.count)) == magicPrefix,
              payload[magicPrefix.count] == 0x01 else {
            return nil
        }
        let json = payload.dropFirst(prefixLen)
        return try? MeshCodable.decoder.decode(SwarmWorkUnit.self, from: Data(json))
    }
}

// MARK: - SwarmWorkResult

/// Result of executing a ``SwarmWorkUnit`` on a peer node.
struct SwarmWorkResult: Codable, Sendable {
    let jobID: UUID
    let unitIndex: UInt32
    let workerPeerID: String
    let resultData: Data
    let computeTimeMs: UInt64
    let timestamp: Date

    /// ASCII: `SWR!`
    static let magicPrefix: [UInt8] = [0x53, 0x57, 0x52, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        // Sub-type byte: 0x02 = work result
        data.append(0x02)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> SwarmWorkResult? {
        let prefixLen = magicPrefix.count + 1
        guard payload.count > prefixLen,
              Array(payload.prefix(magicPrefix.count)) == magicPrefix,
              payload[magicPrefix.count] == 0x02 else {
            return nil
        }
        let json = payload.dropFirst(prefixLen)
        return try? MeshCodable.decoder.decode(SwarmWorkResult.self, from: Data(json))
    }
}

// MARK: - SwarmNodeCapability

/// Advertises a peer's hardware capabilities for swarm compute scheduling.
///
/// The swarm coordinator uses these to weight work distribution and reject
/// nodes that are thermally throttled or low on battery.
struct SwarmNodeCapability: Codable, Sendable {
    let peerID: String
    let availableModels: [String]
    let batteryLevel: Float
    let isCharging: Bool
    /// `ProcessInfo.ThermalState.rawValue`
    let thermalState: Int
    let availableMemoryMB: Int
    let acceptsBackground: Bool
    let acceptsForeground: Bool

    /// ASCII: `SWC!`
    static let magicPrefix: [UInt8] = [0x53, 0x57, 0x43, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> SwarmNodeCapability? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(SwarmNodeCapability.self, from: Data(json))
    }
}

// MARK: - SwarmJobAdvertise

/// Broadcast advertisement for a new swarm job.
///
/// Peers that receive this evaluate whether they can contribute and respond
/// with a ``SwarmNodeCapability`` packet if willing.
struct SwarmJobAdvertise: Codable, Sendable {
    let job: SwarmJob

    /// ASCII: `SWA!`
    static let magicPrefix: [UInt8] = [0x53, 0x57, 0x41, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> SwarmJobAdvertise? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(SwarmJobAdvertise.self, from: Data(json))
    }
}

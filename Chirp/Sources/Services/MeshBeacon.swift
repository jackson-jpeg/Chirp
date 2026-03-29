import Foundation
import OSLog
import UIKit

/// Lightweight mesh presence beacon broadcast every 2 seconds.
///
/// Every ChirpChirp device periodically announces its presence so the mesh
/// can build a topology map. Beacons include the peer's channels, hop count,
/// and battery level. Stale nodes (not seen in 10 seconds) are pruned
/// automatically.
@Observable
final class MeshBeacon: @unchecked Sendable {

    // MARK: - Types

    struct BeaconInfo: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        let channels: [String]
        let hopCount: UInt8
        let batteryLevel: Float
        let timestamp: Date
        var lastSeen: Date
        /// IDs of this node's direct peers -- used to build topology in MeshIntelligence.
        var neighborIDs: [String]

        /// True if this node was heard directly (1 hop away).
        var isDirect: Bool { hopCount <= 1 }

        enum CodingKeys: String, CodingKey {
            case id, name, channels, hopCount, batteryLevel, timestamp, lastSeen, neighborIDs
        }

        init(
            id: String,
            name: String,
            channels: [String],
            hopCount: UInt8,
            batteryLevel: Float,
            timestamp: Date,
            lastSeen: Date,
            neighborIDs: [String] = []
        ) {
            self.id = id
            self.name = name
            self.channels = channels
            self.hopCount = hopCount
            self.batteryLevel = batteryLevel
            self.timestamp = timestamp
            self.lastSeen = lastSeen
            self.neighborIDs = neighborIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            channels = try container.decode([String].self, forKey: .channels)
            hopCount = try container.decode(UInt8.self, forKey: .hopCount)
            batteryLevel = try container.decode(Float.self, forKey: .batteryLevel)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            lastSeen = try container.decode(Date.self, forKey: .lastSeen)
            // Backwards compatible: older beacons may omit neighborIDs
            neighborIDs = try container.decodeIfPresent([String].self, forKey: .neighborIDs) ?? []
        }
    }

    // MARK: - Public State

    /// All known nodes in the mesh (direct + relayed), keyed by peer ID.
    private(set) var knownNodes: [String: BeaconInfo] = [:]

    /// How many unique nodes in the mesh (excluding self).
    var meshNodeCount: Int { knownNodes.count }

    /// Maximum hop depth observed from any beacon.
    var maxHopDepth: UInt8 {
        knownNodes.values.map(\.hopCount).max() ?? 0
    }

    /// Estimated mesh range in meters (~80m per hop).
    var estimatedRange: Int { Int(maxHopDepth) * 80 }

    /// Nodes sorted by hop count (nearest first), then name.
    var sortedNodes: [BeaconInfo] {
        knownNodes.values.sorted { a, b in
            if a.hopCount != b.hopCount { return a.hopCount < b.hopCount }
            return a.name < b.name
        }
    }

    /// Direct peers (hop count 1).
    var directPeers: [BeaconInfo] {
        knownNodes.values.filter { $0.hopCount <= 1 }
    }

    /// Relayed peers (hop count > 1).
    var relayedPeers: [BeaconInfo] {
        knownNodes.values.filter { $0.hopCount > 1 }
    }

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshBeacon")
    private var broadcastTimer: Timer?
    private var pruneTimer: Timer?
    private var localID: String?
    private var localName: String?
    private var cachedBatteryLevel: Float = 0
    private var localChannels: [String] = []

    /// Magic bytes prepended to beacon payloads.
    static let beaconMagic: [UInt8] = [0x42, 0x43, 0x4E, 0x21] // "BCN!"

    /// Stale threshold: nodes not seen for this duration are pruned.
    private static let staleThreshold: TimeInterval = 10.0

    /// Base broadcast interval in seconds.
    private static let baseBroadcastInterval: TimeInterval = 2.0

    /// Maximum broadcast interval under high mesh density.
    private static let maxBroadcastInterval: TimeInterval = 8.0

    /// Current broadcast interval, adjusted for mesh density.
    /// Set via ``updateBroadcastInterval(forPeerCount:)`` to slow beacons
    /// when many peers are visible, reducing airtime chatter.
    private(set) var currentBroadcastInterval: TimeInterval = baseBroadcastInterval

    // MARK: - Init

    init() {}

    // MARK: - Broadcasting

    /// Start broadcasting presence beacons every 2 seconds.
    ///
    /// - Parameters:
    ///   - localID: This device's stable peer ID.
    ///   - localName: This device's display name / callsign.
    ///   - channels: Channel IDs this device is currently on.
    @MainActor
    func startBroadcasting(localID: String, localName: String, channels: [String]) {
        self.localID = localID
        self.localName = localName
        self.localChannels = channels
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.cachedBatteryLevel = max(0, UIDevice.current.batteryLevel)

        stopBroadcasting()

        logger.info("Mesh beacon broadcasting started as \(localName, privacy: .public)")

        // Broadcast timer.
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: currentBroadcastInterval,
            repeats: true
        ) { [weak self] _ in
            self?.broadcastBeacon()
        }
        if let timer = broadcastTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Prune timer runs at half the stale threshold.
        pruneTimer = Timer.scheduledTimer(
            withTimeInterval: Self.staleThreshold / 2,
            repeats: true
        ) { [weak self] _ in
            self?.pruneStale()
        }
        if let timer = pruneTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        // Fire immediately.
        broadcastBeacon()
    }

    /// Stop broadcasting beacons.
    func stopBroadcasting() {
        broadcastTimer?.invalidate()
        broadcastTimer = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    /// Update the channel list for future beacon broadcasts.
    func updateChannels(_ channels: [String]) {
        localChannels = channels
    }

    /// Adjust the beacon broadcast interval based on mesh density.
    /// In a dense mesh (many peers) we back off to reduce airtime chatter.
    /// In a sparse mesh we beacon at the base rate to aid discovery.
    @MainActor
    func updateBroadcastInterval(forPeerCount peerCount: Int) {
        let newInterval: TimeInterval
        if peerCount > 10 {
            // Scale linearly: 10 peers -> 2s, 20 peers -> 8s, capped at max
            let scale = min(1.0, Double(peerCount - 10) / 10.0)
            newInterval = Self.baseBroadcastInterval
                + scale * (Self.maxBroadcastInterval - Self.baseBroadcastInterval)
        } else {
            newInterval = Self.baseBroadcastInterval
        }

        // Only reschedule the timer if the interval actually changed
        guard abs(newInterval - currentBroadcastInterval) > 0.5 else { return }
        currentBroadcastInterval = newInterval
        logger.info("Beacon interval adjusted to \(newInterval, format: .fixed(precision: 1))s for \(peerCount) peers")

        // Reschedule the broadcast timer with the new interval
        broadcastTimer?.invalidate()
        broadcastTimer = Timer.scheduledTimer(
            withTimeInterval: currentBroadcastInterval,
            repeats: true
        ) { [weak self] _ in
            self?.broadcastBeacon()
        }
        if let timer = broadcastTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Receiving

    /// Handle a beacon payload received from the mesh.
    /// Call this from the mesh router's local delivery path.
    func handleBeacon(_ data: Data) {
        // Verify magic header.
        guard data.count > Self.beaconMagic.count else { return }
        let magic = Array(data.prefix(Self.beaconMagic.count))
        guard magic == Self.beaconMagic else { return }

        let jsonData = data.dropFirst(Self.beaconMagic.count)

        do {
            var beacon = try JSONDecoder().decode(BeaconInfo.self, from: Data(jsonData))

            // Ignore our own beacons.
            if beacon.id == localID { return }

            // Update lastSeen to local time.
            beacon.lastSeen = Date()

            // If we already know this node, only update if the incoming beacon
            // has equal or fewer hops (shorter path) or is newer.
            if let existing = knownNodes[beacon.id] {
                if beacon.hopCount <= existing.hopCount || beacon.timestamp > existing.timestamp {
                    knownNodes[beacon.id] = beacon
                }
            } else {
                knownNodes[beacon.id] = beacon
                logger.info("Discovered mesh node: \(beacon.name, privacy: .public) hops=\(beacon.hopCount) channels=\(beacon.channels.count) neighbors=\(beacon.neighborIDs.count)")
            }

            // Publish neighbor topology for MeshIntelligence to consume
            if !beacon.neighborIDs.isEmpty {
                NotificationCenter.default.post(
                    name: .meshTopologyUpdate,
                    object: nil,
                    userInfo: [
                        "peerID": beacon.id,
                        "neighborIDs": beacon.neighborIDs
                    ]
                )
            }
        } catch {
            logger.debug("Failed to decode beacon: \(error.localizedDescription)")
        }
    }

    // MARK: - Pruning

    /// Remove nodes that haven't been seen within the stale threshold.
    func pruneStale() {
        let cutoff = Date().addingTimeInterval(-Self.staleThreshold)
        let staleIDs = knownNodes.filter { $0.value.lastSeen < cutoff }.map(\.key)

        for id in staleIDs {
            if let node = knownNodes.removeValue(forKey: id) {
                logger.info("Pruned stale node: \(node.name, privacy: .public) (\(id, privacy: .public))")
            }
        }
    }

    // MARK: - Encoding

    /// Encode a beacon into a payload suitable for mesh broadcast.
    func encodeBeacon(_ beacon: BeaconInfo) -> Data? {
        guard let json = try? JSONEncoder().encode(beacon) else { return nil }
        var payload = Data(Self.beaconMagic)
        payload.append(json)
        return payload
    }

    // MARK: - Private

    private func broadcastBeacon() {
        guard let localID, let localName else { return }

        // Battery level cached from main actor context
        let batteryLevel: Float = cachedBatteryLevel

        // Include IDs of our direct peers so remote nodes can build topology
        let neighborIDs = Array(directPeers.map(\.id).prefix(20)) // cap to keep payload small

        let beacon = BeaconInfo(
            id: localID,
            name: localName,
            channels: localChannels,
            hopCount: 0,
            batteryLevel: batteryLevel,
            timestamp: Date(),
            lastSeen: Date(),
            neighborIDs: neighborIDs
        )

        guard let payload = encodeBeacon(beacon) else {
            logger.error("Failed to encode beacon")
            return
        }

        // Use adaptive TTL for beacons (normal priority).
        let ttl = MeshPacket.adaptiveTTL(for: .control, priority: .normal)

        let packet = MeshPacket(
            type: .control,
            ttl: ttl,
            originID: UUID(uuidString: localID) ?? UUID(),
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        // Post for the mesh router to distribute.
        NotificationCenter.default.post(
            name: .meshBeaconBroadcast,
            object: nil,
            userInfo: ["packet": packet.serialize()]
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when a mesh beacon packet is ready for mesh broadcast.
    /// The `userInfo` dictionary contains key `"packet"` with serialized `Data`.
    static let meshBeaconBroadcast = Notification.Name("com.chirpchirp.meshBeaconBroadcast")

    /// Posted when a beacon carries neighbor topology information.
    /// `userInfo` contains `"peerID"` (String) and `"neighborIDs"` ([String]).
    static let meshTopologyUpdate = Notification.Name("com.chirpchirp.meshTopologyUpdate")
}

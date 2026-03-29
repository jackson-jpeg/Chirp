import Foundation
import OSLog

/// Routes mesh packets: delivers locally and forwards to other peers.
/// Every ChirpChirp device is a relay node in the mesh.
///
/// Thread safety is guaranteed by the `actor` isolation -- all mutable
/// state lives inside the actor and is accessed sequentially.
actor MeshRouter {

    // MARK: - Private state

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "MeshRouter")

    /// Our own peer identity -- used to discard our own packets that bounce back.
    private let localPeerID: UUID

    /// Ring buffer of recently-seen packet IDs for deduplication.
    /// Entries older than `packetExpirySeconds` are pruned lazily.
    private var seenPackets: [(id: UUID, time: Date)] = []
    private let maxSeenPackets = 10_000
    private let packetExpirySeconds: TimeInterval = 5.0

    // MARK: - Stats

    private(set) var packetsRelayed: UInt64 = 0
    private(set) var packetsDelivered: UInt64 = 0
    private(set) var packetsDeduplicated: UInt64 = 0
    private(set) var maxHopsObserved: UInt8 = 0

    // MARK: - Callbacks

    /// Called when a packet should be played / processed by the local device.
    var onLocalDelivery: ((MeshPacket) -> Void)?

    /// Called when a packet should be forwarded to peers.
    /// The `String` parameter is the peer ID the packet arrived from
    /// so the transport layer can exclude it (no point echoing back).
    var onForward: ((MeshPacket, String) -> Void)?

    /// Set both callbacks at once (convenience for actor isolation).
    func setCallbacks(
        onLocalDelivery: @escaping @Sendable (MeshPacket) -> Void,
        onForward: @escaping @Sendable (MeshPacket, String) -> Void
    ) {
        self.onLocalDelivery = onLocalDelivery
        self.onForward = onForward
    }

    // MARK: - Init

    init(localPeerID: UUID) {
        self.localPeerID = localPeerID
    }

    // MARK: - Packet handling

    /// Process an incoming mesh packet received from `fromPeer`.
    ///
    /// Returns `true` if the packet was new and processed,
    /// `false` if it was dropped (own echo, duplicate, or expired TTL).
    @discardableResult
    func handleIncoming(packet: MeshPacket, fromPeer: String) -> Bool {

        // 1. Drop our own packets that bounced back through the mesh.
        if packet.originID == localPeerID {
            logger.trace("Dropped own packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // 2. Lazily prune expired entries before the dedup check.
        cleanExpired()

        // 3. Duplicate detection.
        if seenPackets.contains(where: { $0.id == packet.packetID }) {
            packetsDeduplicated += 1
            logger.trace("Deduplicated packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // 4. TTL exhausted.
        if packet.ttl == 0 {
            logger.trace("Dropped TTL-0 packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // -- Packet is valid and new --

        // 4a. Record in seen set.
        seenPackets.append((id: packet.packetID, time: Date()))
        if seenPackets.count > maxSeenPackets {
            // Evict oldest quarter to amortise removal cost.
            let evictCount = maxSeenPackets / 4
            seenPackets.removeFirst(evictCount)
            logger.debug("Evicted \(evictCount) oldest seen-packet entries")
        }

        // 4b. Deliver to local audio / control pipeline.
        packetsDelivered += 1
        onLocalDelivery?(packet)

        // 4c. Forward to other peers if hops remain.
        if packet.ttl > 1, let forwarded = packet.forwarded() {
            packetsRelayed += 1
            onForward?(forwarded, fromPeer)
            logger.trace("Forwarded packet \(packet.packetID.uuidString, privacy: .public) TTL \(forwarded.ttl)")
        }

        // 4d. Track the deepest hop depth we've observed.
        //     With adaptive TTL the original TTL is unknown, so use maxTTL as ceiling.
        let hopsUsed = MeshPacket.maxTTL >= packet.ttl
            ? MeshPacket.maxTTL - packet.ttl
            : 0
        if hopsUsed > maxHopsObserved {
            maxHopsObserved = hopsUsed
            logger.info("New max hops observed: \(hopsUsed)")
        }

        return true
    }

    // MARK: - Packet creation

    /// Build a fresh mesh packet originating from this device.
    ///
    /// - Parameters:
    ///   - type: Audio or control.
    ///   - payload: The encoded payload bytes.
    ///   - channelID: Target channel (empty string = broadcast).
    ///   - sequenceNumber: Monotonic sequence within a PTT session.
    ///   - priority: Message priority used to compute adaptive TTL.
    ///               When `nil`, priority is inferred from the packet content.
    func createPacket(
        type: MeshPacket.PacketType,
        payload: Data,
        channelID: String,
        sequenceNumber: UInt32,
        priority: MeshPacket.MessagePriority? = nil
    ) -> MeshPacket {
        let resolvedPriority = priority ?? MeshPacket.inferPriority(type: type, payload: payload)
        let ttl = min(
            MeshPacket.adaptiveTTL(for: type, priority: resolvedPriority),
            MeshPacket.maxTTL
        )
        let packet = MeshPacket(
            type: type,
            ttl: ttl,
            originID: localPeerID,
            packetID: UUID(),
            sequenceNumber: sequenceNumber,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: payload
        )
        // Pre-register so we don't process our own packet if it echoes back
        // before the expiry window closes.
        seenPackets.append((id: packet.packetID, time: Date()))
        logger.trace("Created packet priority=\(resolvedPriority.rawValue) ttl=\(ttl)")
        return packet
    }

    // MARK: - Stats

    /// Snapshot of current mesh statistics.
    var stats: MeshStats {
        MeshStats(
            relayed: packetsRelayed,
            delivered: packetsDelivered,
            deduplicated: packetsDeduplicated,
            maxHops: maxHopsObserved,
            estimatedRangeMeters: Int(maxHopsObserved) * 80,
            seenPacketCount: seenPackets.count
        )
    }

    // MARK: - Private

    /// Remove entries older than `packetExpirySeconds`.
    private func cleanExpired() {
        let cutoff = Date().addingTimeInterval(-packetExpirySeconds)
        // seenPackets is append-only (sorted by time), so we can
        // binary-drop the prefix that's expired.
        if let firstValidIndex = seenPackets.firstIndex(where: { $0.time >= cutoff }) {
            if firstValidIndex > 0 {
                seenPackets.removeFirst(firstValidIndex)
            }
        } else {
            // Everything is expired.
            seenPackets.removeAll()
        }
    }
}

// MARK: - MeshStats

/// Immutable snapshot of mesh routing statistics.
struct MeshStats: Sendable {
    let relayed: UInt64
    let delivered: UInt64
    let deduplicated: UInt64
    let maxHops: UInt8
    /// Rough estimate: each hop ~80 m BLE range.
    let estimatedRangeMeters: Int
    let seenPacketCount: Int
}

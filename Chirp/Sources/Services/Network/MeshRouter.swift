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
    private var seenPacketSet: Set<UUID> = []
    private let maxSeenPackets = 10_000
    private let packetExpirySeconds: TimeInterval = 120.0

    /// Per-(origin, type) highest-seen sequence number for replay protection.
    /// Audio and control are tracked separately: they are stamped from
    /// independent counters and travel over channels of different
    /// reliability, so one stream racing ahead must never invalidate the
    /// other.
    private struct OriginStream: Hashable {
        let origin: UUID
        let type: MeshPacket.PacketType
    }
    private var originSequenceMap: [OriginStream: (sequence: UInt32, lastSeen: Date)] = [:]
    private let originSequenceExpirySeconds: TimeInterval = 300.0

    /// Anti-replay window: a packet this far (or further) behind the
    /// origin's high-water mark is rejected as stale. Distinct packets
    /// closer than this are legitimate reordering (unreliable delivery,
    /// divergent mesh paths); exact duplicates are caught by packetID dedup
    /// regardless of sequence.
    private let replayWindow: Int32 = 64

    /// Monotonic outgoing sequence per packet type, stamped in
    /// `createPacket`. Per-type so each stream's sequence space stays dense —
    /// interleaved traffic of the other type must not open gaps wider than
    /// the receiver's replay window.
    private var outgoingSequences: [MeshPacket.PacketType: UInt32] = [:]

    /// Origins the user has blocked. Their packets are dropped entirely —
    /// not delivered locally and not relayed. Kept in sync with the
    /// user-facing `BlockList` by AppState.
    private var blockedOrigins: Set<UUID> = []

    // MARK: - Stats

    private(set) var packetsRelayed: UInt64 = 0
    private(set) var packetsDelivered: UInt64 = 0
    private(set) var packetsDeduplicated: UInt64 = 0
    private(set) var packetsBlocked: UInt64 = 0
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

    /// Replace the set of blocked origins. Non-UUID IDs are ignored.
    func setBlockedOrigins(_ peerIDs: Set<String>) {
        blockedOrigins = Set(peerIDs.compactMap(UUID.init(uuidString:)))
        logger.info("Blocked origins updated: \(self.blockedOrigins.count) peers")
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
            #if DEBUG
            AudioTelemetry.shared.countStage("routerDropOwn")
            #endif
            logger.trace("Dropped own packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // 1b. Drop everything from blocked origins — no delivery, no relay.
        if blockedOrigins.contains(packet.originID) {
            packetsBlocked += 1
            #if DEBUG
            AudioTelemetry.shared.countStage("routerDropBlocked")
            #endif
            logger.trace("Dropped packet from blocked origin \(packet.originID.uuidString, privacy: .public)")
            return false
        }

        // 2. Lazily prune expired entries before the dedup check.
        cleanExpired()

        // 3. Duplicate detection (O(1) via Set).
        if seenPacketSet.contains(packet.packetID) {
            packetsDeduplicated += 1
            #if DEBUG
            AudioTelemetry.shared.countStage("routerDropDuplicate")
            #endif
            logger.trace("Deduplicated packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // 3b. Per-(origin, type) anti-replay window.
        //     Reject only packets far behind the origin's high-water mark.
        //     Uses signed comparison to handle UInt32 wraparound correctly.
        //     Exact duplicates were already caught by packetID dedup above,
        //     and distinct packets slightly out of order are legitimate mesh
        //     reordering. (A strict <= check here, combined with senders
        //     that never incremented the sequence, once dropped every packet
        //     after the first from each origin — no audio, no text.)
        let stream = OriginStream(origin: packet.originID, type: packet.type)
        if let entry = originSequenceMap[stream] {
            let diff = Int32(bitPattern: packet.sequenceNumber &- entry.sequence)
            if diff <= -replayWindow {
                packetsDeduplicated += 1
                #if DEBUG
                AudioTelemetry.shared.countStage("routerDropReplay")
                #endif
                logger.trace("Replay rejected: origin \(packet.originID.uuidString, privacy: .public) seq \(packet.sequenceNumber) far behind \(entry.sequence)")
                return false
            }
        }

        // 4. TTL exhausted.
        if packet.ttl == 0 {
            #if DEBUG
            AudioTelemetry.shared.countStage("routerDropTTL")
            #endif
            logger.trace("Dropped TTL-0 packet \(packet.packetID.uuidString, privacy: .public)")
            return false
        }

        // -- Packet is valid and new --

        // 4a. Record in seen set.
        seenPackets.append((id: packet.packetID, time: Date()))
        seenPacketSet.insert(packet.packetID)
        if seenPackets.count > maxSeenPackets {
            // Evict oldest quarter to amortise removal cost.
            let evictCount = maxSeenPackets / 4
            for i in 0..<evictCount {
                seenPacketSet.remove(seenPackets[i].id)
            }
            seenPackets.removeFirst(evictCount)
            logger.debug("Evicted \(evictCount) oldest seen-packet entries")
        }

        // 4a2. Advance the per-(origin, type) high-water mark. Never move it
        //      backward — an accepted in-window reordered packet must not
        //      re-open the window for stale traffic.
        if let entry = originSequenceMap[stream] {
            let diff = Int32(bitPattern: packet.sequenceNumber &- entry.sequence)
            originSequenceMap[stream] = (
                sequence: diff > 0 ? packet.sequenceNumber : entry.sequence,
                lastSeen: Date()
            )
        } else {
            originSequenceMap[stream] = (sequence: packet.sequenceNumber, lastSeen: Date())
        }

        // 4b. Deliver to local audio / control pipeline.
        packetsDelivered += 1
        #if DEBUG
        AudioTelemetry.shared.countStage(
            packet.type == .audio ? "routerDeliverAudio" : "routerDeliverControl")
        #endif
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
    /// The sequence number is stamped here, from a monotonic per-type
    /// counter owned by the actor. Callers must not supply their own:
    /// senders that all passed a constant once tripped the receiver's
    /// replay protection on every packet after the first.
    ///
    /// - Parameters:
    ///   - type: Audio or control.
    ///   - payload: The encoded payload bytes.
    ///   - channelID: Target channel (empty string = broadcast).
    ///   - priority: Message priority used to compute adaptive TTL.
    ///               When `nil`, priority is inferred from the packet content.
    func createPacket(
        type: MeshPacket.PacketType,
        payload: Data,
        channelID: String,
        priority: MeshPacket.MessagePriority? = nil
    ) -> MeshPacket {
        let resolvedPriority = priority ?? MeshPacket.inferPriority(type: type, payload: payload)
        let ttl = min(
            MeshPacket.adaptiveTTL(for: type, priority: resolvedPriority),
            MeshPacket.maxTTL
        )
        let sequence = (outgoingSequences[type] ?? 0) &+ 1
        outgoingSequences[type] = sequence
        let packet = MeshPacket(
            type: type,
            ttl: ttl,
            originID: localPeerID,
            packetID: UUID(),
            sequenceNumber: sequence,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: payload
        )
        // Pre-register so we don't process our own packet if it echoes back
        // before the expiry window closes.
        seenPackets.append((id: packet.packetID, time: Date()))
        seenPacketSet.insert(packet.packetID)
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
                for i in 0..<firstValidIndex {
                    seenPacketSet.remove(seenPackets[i].id)
                }
                seenPackets.removeFirst(firstValidIndex)
            }
        } else {
            // Everything is expired.
            seenPackets.removeAll()
            seenPacketSet.removeAll()
        }

        // Prune stale origin sequence entries (no packets for 5 minutes).
        let originCutoff = Date().addingTimeInterval(-originSequenceExpirySeconds)
        originSequenceMap = originSequenceMap.filter { $0.value.lastSeen >= originCutoff }
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

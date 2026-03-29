import Foundation
import OSLog

/// Analyzes mesh topology and optimizes routing decisions.
/// Tracks link quality, preferred paths, and network health.
/// Used to make smart relay decisions based on battery, signal quality,
/// and network conditions -- critical for emergency/blackout scenarios.
actor MeshIntelligence {
    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "MeshIntel")

    // MARK: - Link Quality Tracking

    struct LinkMetrics: Sendable {
        let peerID: String
        var packetsReceived: UInt64 = 0
        var packetsLost: UInt64 = 0
        var avgLatencyMs: Double = 0
        var lastSeen: Date = Date()
        var signalQuality: Double = 1.0  // 0-1

        var packetLossRate: Double {
            guard packetsReceived + packetsLost > 0 else { return 0 }
            return Double(packetsLost) / Double(packetsReceived + packetsLost)
        }

        var isStale: Bool {
            Date().timeIntervalSince(lastSeen) > 30
        }
    }

    private var linkMetrics: [String: LinkMetrics] = [:]

    // Topology map: peer ID -> set of peer IDs they can reach
    private var topologyMap: [String: Set<String>] = [:]

    // Rate limiting: origin ID -> (count, windowStart)
    private var relayRateTracker: [UUID: (count: Int, windowStart: Date)] = [:]
    private let maxRelaysPerSecond = 100

    // Congestion tracking: number of packets pending in the outbound queue
    private(set) var outboundQueueCount: Int = 0
    private static let congestionThreshold = 50

    /// Number of direct peers currently visible (set by MeshBeacon or transport layer).
    private(set) var visiblePeerCount: Int = 0

    /// Density threshold above which beacon relay rate is reduced.
    private static let highDensityPeerThreshold = 10

    // MARK: - Relay Decision

    /// Determine whether this device should relay a given packet.
    /// Considers battery level, message priority, congestion, mesh density, and rate limits.
    func shouldRelay(
        packet: MeshPacket,
        batteryLevel: Float,
        priority: MeshPacket.MessagePriority
    ) -> Bool {
        // Critical battery (<10%): only relay SOS
        if batteryLevel < 0.10 {
            if priority < .critical {
                logger.info("Skipping relay — battery critical (\(batteryLevel * 100, format: .fixed(precision: 0))%%), priority \(priority.rawValue)")
                return false
            }
        }

        // Low battery (<20%): only relay critical and high priority
        if batteryLevel < 0.20 {
            if priority < .high {
                logger.info("Skipping relay — battery low (\(batteryLevel * 100, format: .fixed(precision: 0))%%), priority \(priority.rawValue)")
                return false
            }
        }

        // Congestion check: drop low-priority packets when queue is overloaded
        if outboundQueueCount > Self.congestionThreshold && priority <= .low {
            logger.info("Dropping low-priority relay — outbound queue congested (\(self.outboundQueueCount) pending)")
            return false
        }

        // Dense mesh: probabilistically skip beacon relays to reduce chatter
        if visiblePeerCount > Self.highDensityPeerThreshold && priority == .normal {
            // In a dense mesh, most beacons are redundant. Skip ~50% of beacon relays.
            if Bool.random() {
                logger.debug("Skipping beacon relay — high mesh density (\(self.visiblePeerCount) peers)")
                return false
            }
        }

        // Rate limit per origin: max 100 relayed packets/second
        let now = Date()
        var entry = relayRateTracker[packet.originID] ?? (count: 0, windowStart: now)
        if now.timeIntervalSince(entry.windowStart) >= 1.0 {
            // Reset window
            entry = (count: 0, windowStart: now)
        }
        if entry.count >= maxRelaysPerSecond {
            logger.debug("Rate limited relay for origin \(packet.originID.uuidString.prefix(8), privacy: .public)")
            return false
        }
        entry.count += 1
        relayRateTracker[packet.originID] = entry

        // Even if the sending peer has high loss rate, still relay --
        // they need help getting their packets through the mesh
        return true
    }

    /// Legacy overload -- infers priority from packet content for callers that
    /// have not been updated yet.
    func shouldRelay(packet: MeshPacket, batteryLevel: Float) -> Bool {
        let priority = MeshPacket.inferPriority(type: packet.type, payload: packet.payload)
        return shouldRelay(packet: packet, batteryLevel: batteryLevel, priority: priority)
    }

    // MARK: - Congestion & Density Updates

    /// Update the outbound queue depth so relay decisions account for congestion.
    func updateOutboundQueueCount(_ count: Int) {
        outboundQueueCount = count
    }

    /// Update the number of directly visible peers for density-aware decisions.
    func updateVisiblePeerCount(_ count: Int) {
        visiblePeerCount = count
    }

    /// Returns extra TTL reduction based on link conditions.
    /// Call this when relaying to decide if TTL should be reduced further.
    func extraTTLReduction(forPeers peerIDs: [String]) -> UInt8 {
        // If average link quality to our peers is poor, reduce TTL by 1 extra
        // to prevent weak links from propagating stale data too far
        guard !peerIDs.isEmpty else { return 0 }
        let avgQuality = peerIDs.compactMap { linkMetrics[$0]?.signalQuality }.reduce(0.0, +)
            / max(1.0, Double(peerIDs.count))
        return avgQuality < 0.3 ? 1 : 0
    }

    // MARK: - Link Metrics Updates

    /// Record a successful packet receive from a peer, updating link quality.
    func recordReceive(fromPeer peerID: String, latencyMs: Double) {
        var metrics = linkMetrics[peerID] ?? LinkMetrics(peerID: peerID)
        metrics.packetsReceived += 1
        metrics.lastSeen = Date()

        // Exponential moving average for latency
        let alpha = 0.2
        metrics.avgLatencyMs = metrics.avgLatencyMs == 0
            ? latencyMs
            : metrics.avgLatencyMs * (1 - alpha) + latencyMs * alpha

        // Derive signal quality from latency and loss rate
        let latencyScore = max(0, 1.0 - (metrics.avgLatencyMs / 500.0))  // 500ms = terrible
        let lossScore = 1.0 - metrics.packetLossRate
        metrics.signalQuality = (latencyScore * 0.4 + lossScore * 0.6).clamped(to: 0...1)

        linkMetrics[peerID] = metrics
    }

    /// Record a packet loss event for a peer.
    func recordLoss(peerID: String) {
        var metrics = linkMetrics[peerID] ?? LinkMetrics(peerID: peerID)
        metrics.packetsLost += 1

        // Recalculate signal quality
        let lossScore = 1.0 - metrics.packetLossRate
        let latencyScore = max(0, 1.0 - (metrics.avgLatencyMs / 500.0))
        metrics.signalQuality = (latencyScore * 0.4 + lossScore * 0.6).clamped(to: 0...1)

        linkMetrics[peerID] = metrics
        logger.debug("Loss recorded for \(peerID.prefix(8), privacy: .public), quality now \(metrics.signalQuality, format: .fixed(precision: 2))")
    }

    // MARK: - Topology

    /// Update the topology map with peer connectivity information.
    func updateTopology(peerID: String, connectedTo neighbors: Set<String>) {
        topologyMap[peerID] = neighbors
    }

    /// Find the best relay path to a destination using BFS on the topology map.
    /// Returns an ordered list of peer IDs to hop through, or nil if unreachable.
    func bestPath(to destination: String) -> [String]? {
        // BFS from our directly-connected peers to the destination
        let directPeers = Set(linkMetrics.keys.filter { !linkMetrics[$0]!.isStale })
        guard !directPeers.isEmpty else { return nil }

        // If the destination is a direct peer, return immediately
        if directPeers.contains(destination) {
            return [destination]
        }

        // BFS through topology map
        var visited = Set<String>()
        var queue: [(node: String, path: [String])] = directPeers.map { ($0, [$0]) }
        visited.formUnion(directPeers)

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()

            guard let neighbors = topologyMap[current] else { continue }
            for neighbor in neighbors {
                if neighbor == destination {
                    return path + [neighbor]
                }
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append((neighbor, path + [neighbor]))
                }
            }
        }

        return nil  // Destination unreachable
    }

    // MARK: - Health Metrics

    /// Overall mesh health score from 0 (dead) to 1 (excellent).
    /// Considers peer count, average link quality, and staleness.
    var meshHealthScore: Double {
        get {
            let activePeers = linkMetrics.values.filter { !$0.isStale }
            guard !activePeers.isEmpty else { return 0 }

            let avgQuality = activePeers.map(\.signalQuality).reduce(0, +) / Double(activePeers.count)
            let peerCountScore = min(1.0, Double(activePeers.count) / 5.0)  // 5+ peers = perfect

            return (avgQuality * 0.6 + peerCountScore * 0.4).clamped(to: 0...1)
        }
    }

    /// Number of nodes reachable through the mesh (direct + transitive).
    var reachableNodeCount: Int {
        get {
            // Direct active peers
            var reachable = Set(linkMetrics.keys.filter { !linkMetrics[$0]!.isStale })

            // Transitive peers from topology map
            var frontier = reachable
            while !frontier.isEmpty {
                var nextFrontier = Set<String>()
                for peer in frontier {
                    if let neighbors = topologyMap[peer] {
                        let newNeighbors = neighbors.subtracting(reachable)
                        nextFrontier.formUnion(newNeighbors)
                        reachable.formUnion(newNeighbors)
                    }
                }
                frontier = nextFrontier
            }

            return reachable.count
        }
    }

    /// Get link metrics for a specific peer, if available.
    func metricsForPeer(_ peerID: String) -> LinkMetrics? {
        linkMetrics[peerID]
    }

    /// Get all active (non-stale) peer IDs.
    var activePeerIDs: [String] {
        linkMetrics.filter { !$0.value.isStale }.map(\.key)
    }

    /// Prune stale entries older than the given interval.
    func pruneStaleEntries(olderThan interval: TimeInterval = 120) {
        let cutoff = Date().addingTimeInterval(-interval)
        linkMetrics = linkMetrics.filter { $0.value.lastSeen >= cutoff }

        // Also prune rate tracker
        let rateCutoff = Date().addingTimeInterval(-2)
        relayRateTracker = relayRateTracker.filter { $0.value.windowStart >= rateCutoff }
    }
}

// MARK: - Double Clamping

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

import Foundation
import OSLog

// MARK: - Packet Intent

/// Classifies outgoing data by its quality-of-service requirements.
enum PacketIntent: String, Sendable {
    /// Voice audio frames -- lowest latency wins.
    case audio
    /// Control messages (floor control, heartbeats, pheromone ACKs) -- reliability wins.
    case control
    /// Bulk data (file transfer chunks, mesh cloud backups) -- throughput wins.
    case bulkData
}

// MARK: - Transport Choice

/// The result of a transport selection decision.
enum TransportChoice: String, Sendable {
    /// Send only via MultipeerConnectivity.
    case multipeerOnly
    /// Send only via Wi-Fi Aware.
    case wifiAwareOnly
    /// Send on both transports (current default behavior).
    case both
}

// MARK: - Transport Preference

/// Determines which transport(s) to use for sending, based on current peer connectivity
/// and optional Wi-Fi Aware link quality metrics.
///
/// Legacy rule (still the fallback): skip a transport if no peers need it.
/// Quality-aware rule: when WALinkMetrics are available, pick the best transport
/// for the packet's QoS requirements (latency, reliability, throughput).
enum TransportPreference {

    private static let logger = Logger.transport

    /// Tracks the last logged transport choice per intent to avoid log spam.
    private static let lastLoggedChoice = OSAllocatedUnfairLock(initialState: [PacketIntent: TransportChoice]())

    // MARK: - Thresholds

    /// Maximum voice latency (ms) to prefer Wi-Fi Aware for audio.
    private static let audioLatencyThresholdMs: Double = 20
    /// Minimum signal strength (dBm) to prefer Wi-Fi Aware for audio.
    private static let audioSignalThresholdDBm: Double = -70
    /// Minimum throughput capacity (bits/s) to prefer Wi-Fi Aware for bulk data.
    private static let bulkThroughputThresholdBps: Double = 1_000_000 // 1 Mbps

    // MARK: - Quality-Aware Selection

    /// Choose the best transport for the given packet type, factoring in Wi-Fi Aware
    /// link metrics when available.
    ///
    /// - Parameters:
    ///   - intent: The QoS category of the packet being sent.
    ///   - wifiAwareMetrics: Aggregated link metrics from the Wi-Fi Aware transport, keyed by peer ID.
    ///                       Pass `nil` or empty when metrics are not yet available.
    ///   - peers: Current peer list from the active channel.
    /// - Returns: Which transport(s) to use.
    static func preferredTransport(
        for intent: PacketIntent,
        wifiAwareMetrics: [String: WALinkMetrics]?,
        peers: [ChirpPeer]
    ) -> TransportChoice {
        // Step 1: Determine baseline reachability (existing logic)
        let hasMCPeers = shouldSendOnMC(peers: peers)
        let hasWAPeers = shouldSendOnWA(peers: peers)

        // If only one transport has peers, use that one regardless of metrics.
        if hasMCPeers && !hasWAPeers { return log(.multipeerOnly, for: intent) }
        if hasWAPeers && !hasMCPeers { return log(.wifiAwareOnly, for: intent) }
        if !hasMCPeers && !hasWAPeers { return log(.both, for: intent) } // discovery mode

        // Step 2: Both transports have peers. If no metrics, fall back to dual send.
        guard let metrics = wifiAwareMetrics, !metrics.isEmpty else {
            return log(.both, for: intent)
        }

        // Step 3: Quality-aware routing based on intent
        let choice: TransportChoice
        switch intent {
        case .audio:
            choice = audioTransportChoice(metrics: metrics)
        case .control:
            // Control messages always go on both for maximum reliability.
            choice = .both
        case .bulkData:
            choice = bulkDataTransportChoice(metrics: metrics, peers: peers)
        }

        return log(choice, for: intent)
    }

    // MARK: - Audio Selection

    /// For audio: prefer Wi-Fi Aware if it has low latency and decent signal.
    private static func audioTransportChoice(metrics: [String: WALinkMetrics]) -> TransportChoice {
        // Check if ANY WA peer has acceptable voice latency and signal
        let hasGoodWALink = metrics.values.contains { m in
            guard let latency = m.voiceLatency,
                  let signal = m.signalStrength else {
                return false
            }
            let latencyMs = Double(latency.components.seconds) * 1000
                + Double(latency.components.attoseconds) / 1_000_000_000_000_000
            return latencyMs < audioLatencyThresholdMs && signal > audioSignalThresholdDBm
        }

        return hasGoodWALink ? .wifiAwareOnly : .both
    }

    // MARK: - Bulk Data Selection

    /// For bulk data: prefer Wi-Fi Aware if throughput capacity exceeds threshold.
    private static func bulkDataTransportChoice(
        metrics: [String: WALinkMetrics],
        peers: [ChirpPeer]
    ) -> TransportChoice {
        let hasHighThroughputWA = metrics.values.contains { m in
            guard let throughput = m.throughputCapacity else { return false }
            return throughput > bulkThroughputThresholdBps
        }

        if hasHighThroughputWA {
            return .wifiAwareOnly
        }

        // If MC has more peers (better fan-out), prefer MC for bulk distribution
        let mcPeerCount = peers.filter { $0.transportType == .multipeer }.count
        let waPeerCount = peers.filter { $0.transportType == .wifiAware || $0.transportType == .both }.count
        if mcPeerCount > waPeerCount {
            return .multipeerOnly
        }

        return .both
    }

    // MARK: - Legacy API (unchanged, used as building blocks)

    /// Returns `true` if at least one peer is only reachable via MultipeerConnectivity.
    static func shouldSendOnMC(peers: [ChirpPeer]) -> Bool {
        guard !peers.isEmpty else { return true } // No peers -> send on both for discovery
        return peers.contains { $0.transportType == .multipeer }
    }

    /// Returns `true` if at least one peer is reachable via Wi-Fi Aware.
    static func shouldSendOnWA(peers: [ChirpPeer]) -> Bool {
        guard !peers.isEmpty else { return true }
        return peers.contains { $0.transportType == .wifiAware || $0.transportType == .both }
    }

    // MARK: - Convenience: apply a TransportChoice

    /// Unpack a `TransportChoice` into MC/WA booleans.
    static func shouldSendOnMC(choice: TransportChoice) -> Bool {
        choice == .multipeerOnly || choice == .both
    }

    static func shouldSendOnWA(choice: TransportChoice) -> Bool {
        choice == .wifiAwareOnly || choice == .both
    }

    // MARK: - Logging

    /// Log only when the transport selection changes for a given intent.
    @discardableResult
    private static func log(_ choice: TransportChoice, for intent: PacketIntent) -> TransportChoice {
        let didChange = lastLoggedChoice.withLock { state -> Bool in
            if state[intent] == choice { return false }
            state[intent] = choice
            return true
        }
        if didChange {
            logger.info("Transport selection changed: \(intent.rawValue, privacy: .public) -> \(choice.rawValue, privacy: .public)")
        }
        return choice
    }
}

import Foundation
import OSLog

/// Bio-inspired pheromone routing overlay for the ChirpChirp mesh network.
///
/// Orchestrates delivery ACK generation, ACK processing at relay nodes,
/// pheromone-guided relay decisions, periodic trail evaporation, and
/// spore-mode discovery. Sits on top of ``MeshRouter`` and ``MeshIntelligence``
/// without replacing the existing broadcast forwarding -- pheromone data
/// is an optimisation layer that lets nodes make smarter relay decisions.
@Observable
@MainActor
final class PheromoneRouter {

    private let logger = Logger(subsystem: Constants.subsystem, category: "Pheromone")

    // MARK: - Callbacks

    /// Send a control payload into the mesh. Parameters: (payload, channelID).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Observable State

    /// True when this node has very few peers and should aggressively discover.
    private(set) var isSporeMode: Bool = false

    /// Number of active pheromone destination trails.
    private(set) var activeTrails: Int = 0

    // MARK: - Private

    private var evaporationTask: Task<Void, Never>?
    private var meshIntelligence: MeshIntelligence?
    private var localPeerID: String = ""
    private var localPeerName: String = ""

    /// Ring buffer of recently forwarded ACK packet IDs for deduplication.
    private var forwardedACKs: [UUID] = []
    private static let forwardedACKsCapacity = 500

    // MARK: - Init

    init() {}

    /// Wire dependencies after construction (avoids init-order issues in AppState).
    func configure(meshIntelligence: MeshIntelligence, localPeerID: String, localPeerName: String) {
        self.meshIntelligence = meshIntelligence
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
        startEvaporationLoop()
    }

    // MARK: - ACK Generation

    /// Call when a message is successfully delivered locally.
    /// Generates a delivery ACK and broadcasts it back toward the sender.
    func acknowledgeDelivery(packetID: UUID, senderID: String, channelID: String) {
        let ack = DeliveryACK(
            ackedPacketID: packetID,
            originalSenderID: senderID,
            ackerID: localPeerID,
            channelID: channelID,
            hopCount: 0
        )

        guard let payload = try? ack.wirePayload() else { return }
        onSendPacket?(payload, "")  // Broadcast channel for ACKs

        // Also deposit pheromone locally -- we successfully reached this channel
        let channelKey = "channel:\(channelID)"
        let intel = meshIntelligence
        let pid = localPeerID
        Task {
            await intel?.depositPheromone(destination: channelKey, viaNeighbor: pid)
        }

        logger.debug("Sent delivery ACK for \(packetID.uuidString.prefix(8))")
    }

    // MARK: - ACK Processing (Relay Node)

    /// Handle incoming ACK -- deposit pheromone and optionally forward.
    /// Returns `true` if the payload was an ACK and was consumed.
    @discardableResult
    func handleACK(_ payload: Data, fromPeer: String) -> Bool {
        guard var ack = DeliveryACK.from(payload: payload) else { return false }

        // Deposit pheromone: the path through `fromPeer` successfully delivered to this channel
        let channelKey = "channel:\(ack.channelID)"
        let intel = meshIntelligence
        Task {
            // Stronger deposit for closer acknowledgments (fewer hops = more reliable path)
            let amount = 1.0 / (1.0 + Double(ack.hopCount))
            await intel?.depositPheromone(destination: channelKey, viaNeighbor: fromPeer, amount: amount)
        }

        // If we're the original sender, consume the ACK (end of backpropagation)
        if ack.originalSenderID == localPeerID {
            logger.debug("Received delivery ACK for our packet \(ack.ackedPacketID.uuidString.prefix(8))")
            return true
        }

        // Deduplicate: skip if we already forwarded this ACK
        if forwardedACKs.contains(ack.ackedPacketID) {
            return true
        }

        // Forward ACK toward original sender with incremented hop count
        ack.hopCount += 1
        if ack.hopCount < 8 { // Cap ACK propagation
            if let forwardPayload = try? ack.wirePayload() {
                onSendPacket?(forwardPayload, "")
            }
        }

        // Track forwarded ACK for dedup
        forwardedACKs.append(ack.ackedPacketID)
        if forwardedACKs.count > Self.forwardedACKsCapacity {
            forwardedACKs.removeFirst()
        }

        return true
    }

    // MARK: - Relay Peer Selection

    /// Get recommended peers to forward a packet to.
    /// Returns nil -> broadcast to all (existing behavior).
    /// Returns [String] -> send only to these peers (pheromone-guided).
    func selectRelayPeers(for packet: MeshPacket, allPeers: [String]) async -> [String]? {
        await meshIntelligence?.selectRelayPeers(for: packet, allPeers: allPeers)
    }

    // MARK: - Spore Mode

    /// Check and update spore mode status.
    func updateSporeMode() async {
        let spore = await meshIntelligence?.isInSporeMode() ?? false
        isSporeMode = spore
    }

    // MARK: - Beacon Integration

    /// Get pheromone summary for inclusion in beacon broadcasts.
    func pheromoneSummaryForBeacon() async -> [String: Double] {
        await meshIntelligence?.pheromoneSummary() ?? [:]
    }

    // MARK: - Evaporation

    private func startEvaporationLoop() {
        evaporationTask?.cancel()
        let intel = meshIntelligence
        evaporationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { break }
                await intel?.evaporatePheromones()
                await self.updateSporeMode()
                // Update trail count for UI
                let summary = await intel?.pheromoneSummary() ?? [:]
                self.activeTrails = summary.count
            }
        }
    }
}

import Foundation
import os

actor PeerTracker {
    private let logger = Logger(subsystem: "com.chirp.ptt", category: "PeerTracker")
    private var peers: [String: ChirpPeer] = [:]
    private var healthCheckTask: Task<Void, Never>?

    // MARK: - Peer Management

    func updatePeer(id: String, name: String) {
        if var existing = peers[id] {
            existing.name = name
            existing.isConnected = true
            existing.lastHeartbeat = Date()
            peers[id] = existing
            logger.debug("Updated peer: \(name) (\(id))")
        } else {
            let peer = ChirpPeer(
                id: id,
                name: name,
                isConnected: true,
                signalStrength: 2,
                lastHeartbeat: Date()
            )
            peers[id] = peer
            logger.info("Added peer: \(name) (\(id))")
        }
    }

    func removePeer(id: String) {
        if let removed = peers.removeValue(forKey: id) {
            logger.info("Removed peer: \(removed.name) (\(id))")
        }
    }

    func handleHeartbeat(peerID: String, timestamp: Date) {
        guard var peer = peers[peerID] else { return }
        peer.lastHeartbeat = timestamp
        peer.isConnected = true
        peers[peerID] = peer
    }

    var connectedPeers: [ChirpPeer] {
        Array(peers.values.filter(\.isConnected))
    }

    var allPeers: [ChirpPeer] {
        Array(peers.values)
    }

    // MARK: - Health Check

    func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self.runHealthCheck()
            }
        }
    }

    func stopHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    private func runHealthCheck() {
        let now = Date()
        let staleThreshold: TimeInterval = 15.0

        for (id, var peer) in peers {
            if peer.isConnected && now.timeIntervalSince(peer.lastHeartbeat) > staleThreshold {
                peer.isConnected = false
                peers[id] = peer
                logger.warning("Peer \(peer.name) (\(id)) marked disconnected — no heartbeat for >\(staleThreshold)s")
            }
        }
    }
}

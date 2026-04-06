import Foundation
import MultipeerConnectivity
import OSLog

/// MultipeerConnectivity-based transport for local Wi-Fi/Bluetooth PTT.
/// Works TODAY on any two iPhones on the same network -- no entitlements needed.
/// Acts as a bridge until Wi-Fi Aware entitlement is granted.
///
/// ALL packets are wrapped in MeshPacket format via the mesh router.
/// There is no legacy code path -- every byte on the wire starts with meshMagic 0xAA.
///
/// `@unchecked Sendable` is required because MCSessionDelegate methods run on arbitrary
/// internal queues. Mutable state (`peers`, `previousPeerCount`, `reconnectBackoff`) is
/// dispatched to main queue via `updatePeerList()` to prevent data races with UI reads.
/// Auto-reconnection uses exponential backoff (2s→4s→8s→16s→30s) with jitter.
final class MultipeerTransport: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "Multipeer")
    private let serviceType = "chirp-ptt" // max 15 chars, lowercase + hyphens
    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var peers: [ChirpPeer] = []

    // Callback for peer changes
    var onPeersChanged: (([ChirpPeer]) -> Void)?

    // MARK: - Auto-Reconnection

    private var reconnectTask: Task<Void, Never>?
    private var previousPeerCount: Int = 0
    private var reconnectAttempt: Int = 0
    private static let maxBackoff: TimeInterval = 30.0
    private static let initialBackoff: TimeInterval = 2.0
    private static let maxReconnectAttempts: Int = 10

    /// Called when reconnection fails after all attempts are exhausted.
    var onReconnectFailed: (() -> Void)?

    // MARK: - Mesh Networking

    /// Required mesh router -- all packets flow through it.
    let meshRouter: MeshRouter

    /// Magic byte prefix that identifies mesh packets on the wire.
    private static let meshMagic: UInt8 = 0xAA

    /// Stable local peer identity for control messages.
    let localPeerID: String
    let localPeerName: String

    // MARK: - Init

    init(displayName: String, meshRouter: MeshRouter, localPeerID: String, localPeerName: String) {
        myPeerID = MCPeerID(displayName: displayName)
        self.meshRouter = meshRouter
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName

        super.init()

        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
    }

    // MARK: - Start / Stop

    func start() {
        // Advertise ourselves
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        // Browse for others
        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()

        logger.info("MultipeerTransport started -- advertising + browsing as '\(self.myPeerID.displayName)'")
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        peers.removeAll()
        previousPeerCount = 0
        reconnectAttempt = 0
        logger.info("MultipeerTransport stopped")
    }

    // MARK: - Send

    func sendAudio(_ data: Data, sequenceNumber: UInt32 = 0, channelID: String? = nil) throws {
        guard !session.connectedPeers.isEmpty else { return }

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .audio,
                payload: data,
                channelID: channelID ?? "",
                sequenceNumber: sequenceNumber
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                try self.session.send(wireData, toPeers: self.session.connectedPeers, with: .unreliable)
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    /// Send pre-built wire data (meshMagic + serialized MeshPacket).
    /// Used when the caller has already created the packet to avoid duplicate packet IDs
    /// when sending on multiple transports.
    func sendRawWireData(_ wireData: Data, reliable: Bool = false) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(wireData, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
        }
    }

    func sendControl(_ message: FloorControlMessage, channelID: String? = nil) throws {
        guard !session.connectedPeers.isEmpty else { return }
        let payload = try MeshCodable.encoder.encode(message)

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .control,
                payload: payload,
                channelID: channelID ?? "",
                sequenceNumber: 0
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                try self.session.send(wireData, toPeers: self.session.connectedPeers, with: .reliable)
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    /// Send pre-encoded control data (e.g. text messages already wrapped with TXT! prefix).
    /// The data is wrapped in a MeshPacket and sent reliably to all peers.
    func sendControlData(_ data: Data, channelID: String? = nil) throws {
        guard !session.connectedPeers.isEmpty else { return }

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .control,
                payload: data,
                channelID: channelID ?? "",
                sequenceNumber: 0
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                try self.session.send(wireData, toPeers: self.session.connectedPeers, with: .reliable)
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mesh Forwarding

    /// Forward a pre-serialized mesh packet to all connected peers except the one it came from.
    func forwardPacket(_ packet: Data, excludePeer: String) {
        let targets = session.connectedPeers.filter { $0.displayName != excludePeer }
        guard !targets.isEmpty else { return }

        var wireData = Data([Self.meshMagic])
        wireData.append(packet)

        // Use unreliable for forwarded packets -- they're already best-effort mesh traffic
        do {
            try session.send(wireData, toPeers: targets, with: .unreliable)
        } catch {
            logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
        }
        logger.debug("Mesh forwarded packet to \(targets.count) peers (excluded '\(excludePeer)')")
    }

    // MARK: - Helpers

    /// Update the peer list. Called from MCSession delegate (arbitrary queue),
    /// so dispatches to main to avoid data races with UI reads.
    private func updatePeerList() {
        let connectedPeers = session.connectedPeers
        let currentCount = connectedPeers.count
        let newPeers = connectedPeers.map { mcPeer in
            ChirpPeer(
                id: mcPeer.displayName,
                name: mcPeer.displayName,
                isConnected: true,
                signalStrength: 3
            )
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.peers = newPeers
            self.onPeersChanged?(newPeers)
            self.logger.info("Peers updated: \(newPeers.count) connected")

            // Auto-reconnection: if we had peers but now have none, start reconnect loop
            if currentCount == 0 && self.previousPeerCount > 0 {
                self.startReconnectLoop()
            } else if currentCount > 0 {
                // We have peers again — cancel any pending reconnect and reset attempt counter
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.reconnectAttempt = 0
            }

            self.previousPeerCount = currentCount
        }
    }

    // MARK: - Auto-Reconnection

    /// Compute backoff delay for a given attempt: min(2^attempt * 2, 30) + jitter(0…1s).
    private static func backoffDelay(attempt: Int) -> TimeInterval {
        let base = min(pow(2.0, Double(attempt)) * initialBackoff, maxBackoff)
        let jitter = Double.random(in: 0...1.0)
        return base + jitter
    }

    /// Start an exponential-backoff reconnection loop after all peers are lost.
    /// Each iteration restarts advertising + browsing. The loop cancels automatically
    /// when a peer connects (via `updatePeerList`) or after `maxReconnectAttempts`.
    private func startReconnectLoop() {
        reconnectTask?.cancel()
        reconnectAttempt = 0

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && self.reconnectAttempt < Self.maxReconnectAttempts {
                let attempt = self.reconnectAttempt
                let delay = Self.backoffDelay(attempt: attempt)
                self.logger.info("All peers lost — reconnect attempt \(attempt + 1)/\(Self.maxReconnectAttempts) in \(String(format: "%.1f", delay))s")

                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return  // Cancelled (peer reconnected or stop() called)
                }
                guard !Task.isCancelled else { return }

                self.logger.info("Reconnecting: restarting advertising + browsing (attempt \(attempt + 1))")

                // Stop and restart discovery
                self.advertiser?.stopAdvertisingPeer()
                self.browser?.stopBrowsingForPeers()
                self.advertiser?.startAdvertisingPeer()
                self.browser?.startBrowsingForPeers()

                self.reconnectAttempt += 1

                // Brief grace period for peers to appear before next iteration
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }

                // If peers appeared during grace period, updatePeerList cancels this task
                if !self.session.connectedPeers.isEmpty {
                    return
                }
            }

            // Exhausted all attempts
            if !Task.isCancelled {
                self.logger.warning("Reconnection failed after \(Self.maxReconnectAttempts) attempts")
                await MainActor.run {
                    self.onReconnectFailed?()
                }
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateName: String
        switch state {
        case .notConnected: stateName = "disconnected"
        case .connecting: stateName = "connecting"
        case .connected: stateName = "connected"
        @unknown default: stateName = "unknown"
        }
        logger.info("Peer '\(peerID.displayName)' -> \(stateName)")
        updatePeerList()

        // Broadcast peer join/leave control messages so the mesh can track liveness
        switch state {
        case .connected:
            try? sendControl(.peerJoin(peerID: localPeerID, peerName: localPeerName))
        case .notConnected:
            try? sendControl(.peerLeave(peerID: localPeerID))
        default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // All packets must start with the mesh magic byte
        guard data.count >= 2, data[0] == Self.meshMagic else {
            logger.warning("Dropped non-mesh packet from '\(peerID.displayName)' (\(data.count) bytes)")
            return
        }

        let meshData = Data(data.dropFirst())
        guard let meshPacket = MeshPacket.deserialize(meshData) else {
            logger.warning("Failed to deserialize mesh packet from '\(peerID.displayName)'")
            return
        }

        let peerName = peerID.displayName
        let router = meshRouter
        Task {
            let _ = await router.handleIncoming(packet: meshPacket, fromPeer: peerName)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("Received invitation from '\(peerID.displayName)' -- auto-accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logger.error("Advertising failed: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard peerID != myPeerID else { return }
        logger.info("Found peer '\(peerID.displayName)' -- inviting")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("Lost peer '\(peerID.displayName)'")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        logger.error("Browsing failed: \(error.localizedDescription)")
    }
}

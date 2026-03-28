import Foundation
import MultipeerConnectivity
import OSLog

/// MultipeerConnectivity-based transport for local Wi-Fi/Bluetooth PTT.
/// Works TODAY on any two iPhones on the same network — no entitlements needed.
/// Acts as a bridge until Wi-Fi Aware entitlement is granted.
final class MultipeerTransport: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.chirp.app", category: "Multipeer")
    private let serviceType = "chirp-ptt" // max 15 chars, lowercase + hyphens
    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var peers: [ChirpPeer] = []

    // Streams
    private let audioContinuation: AsyncStream<Data>.Continuation
    let audioPackets: AsyncStream<Data>

    private let controlContinuation: AsyncStream<FloorControlMessage>.Continuation
    let controlMessages: AsyncStream<FloorControlMessage>

    // Callback for peer changes
    var onPeersChanged: (([ChirpPeer]) -> Void)?

    // MARK: - Packet framing

    private enum PacketType: UInt8 {
        case audio = 0x01
        case control = 0x02
    }

    // MARK: - Init

    init(displayName: String) {
        myPeerID = MCPeerID(displayName: displayName)

        var audioCont: AsyncStream<Data>.Continuation!
        audioPackets = AsyncStream { audioCont = $0 }
        audioContinuation = audioCont

        var controlCont: AsyncStream<FloorControlMessage>.Continuation!
        controlMessages = AsyncStream { controlCont = $0 }
        controlContinuation = controlCont

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

        logger.info("MultipeerTransport started — advertising + browsing as '\(self.myPeerID.displayName)'")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
        peers.removeAll()
        audioContinuation.finish()
        controlContinuation.finish()
        logger.info("MultipeerTransport stopped")
    }

    // MARK: - Send

    func sendAudio(_ data: Data) throws {
        guard !session.connectedPeers.isEmpty else { return }
        var packet = Data([PacketType.audio.rawValue])
        packet.append(data)
        try session.send(packet, toPeers: session.connectedPeers, with: .unreliable)
    }

    func sendControl(_ message: FloorControlMessage) throws {
        guard !session.connectedPeers.isEmpty else { return }
        let payload = try JSONEncoder().encode(message)
        var packet = Data([PacketType.control.rawValue])
        packet.append(payload)
        try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - Helpers

    private func updatePeerList() {
        peers = session.connectedPeers.map { mcPeer in
            ChirpPeer(
                id: mcPeer.displayName,
                name: mcPeer.displayName,
                isConnected: true,
                signalStrength: 3
            )
        }
        onPeersChanged?(peers)
        logger.info("Peers updated: \(self.peers.count) connected")
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
        logger.info("Peer '\(peerID.displayName)' → \(stateName)")
        updatePeerList()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count >= 2 else { return }
        let typeByte = data[0]
        let payload = data.dropFirst()

        switch PacketType(rawValue: typeByte) {
        case .audio:
            audioContinuation.yield(Data(payload))
        case .control:
            if let message = try? JSONDecoder().decode(FloorControlMessage.self, from: Data(payload)) {
                controlContinuation.yield(message)
            }
        case .none:
            break
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("Received invitation from '\(peerID.displayName)' — auto-accepting")
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
        logger.info("Found peer '\(peerID.displayName)' — inviting")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("Lost peer '\(peerID.displayName)'")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        logger.error("Browsing failed: \(error.localizedDescription)")
    }
}

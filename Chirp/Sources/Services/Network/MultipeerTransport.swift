import Foundation
import MultipeerConnectivity
import os
import OSLog

// MARK: - Radio seam

/// The part of `MCSession` the transport sends through: who is connected, and
/// how to put bytes on the air. `MCSession` is the only production conformer.
/// It exists so a test can stand in for the radio and count exactly what the
/// transport would have transmitted. See `DemoTransportIsolationTests`.
protocol MeshRadio: AnyObject {
    var connectedPeers: [MCPeerID] { get }
    func send(_ data: Data, toPeers peerIDs: [MCPeerID], with mode: MCSessionSendDataMode) throws
}

extension MCSession: MeshRadio {}

/// MultipeerConnectivity-based transport for local Wi-Fi/Bluetooth PTT.
/// Works TODAY on any two iPhones on the same network -- no entitlements needed.
/// Acts as a bridge until Wi-Fi Aware entitlement is granted.
///
/// ALL packets are wrapped in MeshPacket format via the mesh router.
/// There is no legacy code path -- every byte on the wire starts with meshMagic 0xAA.
///
/// `@unchecked Sendable` is required because MCSessionDelegate methods run on arbitrary
/// internal queues. Mutable state (`peers`, `previousPeerCount`, `reconnectAttempt`,
/// `reconnectTask`, `advertiser`, `browser`) is confined to the main actor: delegate
/// callbacks hop there via `updatePeerList()`, and `start()`/`stop()`/the reconnect
/// loop are all `@MainActor`, so lifecycle and reconnect state have one isolation
/// domain instead of racing pull-to-refresh restarts against the backoff task.
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

    /// Where outbound bytes go. The session itself unless a test injected a
    /// spy. Every send in this file goes through ``emit(_:to:mode:)``, which
    /// is the only caller of `radio.send`.
    private var radio: MeshRadio!

    // MARK: - Demo sandbox

    /// While sandboxed (Demo Mode), nothing leaves or enters this device:
    /// discovery is stopped, every outbound packet is dropped in ``emit``, and
    /// every inbound packet is dropped before the router sees it. Read from
    /// the audio and session queues as well as the main actor, hence the lock.
    private let sandboxState = OSAllocatedUnfairLock(initialState: false)

    /// Outbound packets refused by the sandbox or the demo-channel check.
    /// Diagnostics and tests only.
    private let droppedCounter = OSAllocatedUnfairLock(initialState: 0)

    var isSandboxed: Bool { sandboxState.withLock { $0 } }

    var droppedOutboundCount: Int { droppedCounter.withLock { $0 } }

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

    /// - Parameter radio: test seam only. Production passes nothing and the
    ///   transport sends through its own `MCSession`.
    init(
        displayName: String,
        meshRouter: MeshRouter,
        localPeerID: String,
        localPeerName: String,
        radio: MeshRadio? = nil
    ) {
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
        self.radio = radio ?? session
    }

    // MARK: - Sandbox

    /// Enter or leave the Demo Mode sandbox. Entering stops discovery and
    /// drops every connection, so the device is invisible to real peers for
    /// as long as simulated ones are on screen; leaving restarts discovery.
    @MainActor
    func setSandboxed(_ sandboxed: Bool) {
        let changed = sandboxState.withLock { state -> Bool in
            defer { state = sandboxed }
            return state != sandboxed
        }
        guard changed else { return }
        if sandboxed {
            stop()
            logger.info("MultipeerTransport sandboxed — radio silent for Demo Mode")
        } else {
            start()
            logger.info("MultipeerTransport left sandbox")
        }
    }

    // MARK: - Start / Stop

    @MainActor
    func start() {
        guard !isSandboxed else {
            logger.info("MultipeerTransport start ignored — sandboxed for Demo Mode")
            return
        }
        startDiscovery()
        logger.info("MultipeerTransport started -- advertising + browsing as '\(self.myPeerID.displayName)'")
    }

    @MainActor
    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stopDiscovery()
        session.disconnect()
        peers.removeAll()
        previousPeerCount = 0
        reconnectAttempt = 0
        logger.info("MultipeerTransport stopped")
    }

    /// Advertiser and browser are single-use: a restarted
    /// MCNearbyServiceBrowser re-cancels its underlying CFNetServiceBrowser's
    /// runloop source, and after enough stop/start cycles that source is
    /// already dead and CFRunLoopSourceInvalidate traps with a mismatched-
    /// TypeID assert (crash on Sacre Bleu, 2026-09-10 18:20, main thread in
    /// _BrowserCancel — the reconnect loop had been cycling one instance).
    /// So every restart gets FRESH instances and the old ones are fully
    /// detached before they go away.
    @MainActor
    private func startDiscovery() {
        // The reconnect loop restarts discovery directly, not through start(),
        // so the sandbox has to hold here too.
        guard !isSandboxed else { return }
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    @MainActor
    private func stopDiscovery() {
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    // MARK: - Send

    func sendAudio(_ data: Data, channelID: String? = nil) throws {
        // Capture the recipients now. The send happens inside a Task, after an
        // await — re-reading session.connectedPeers there meant the last peer
        // dropping in that window turned the send into a silent no-op.
        let targets = radio.connectedPeers
        guard !targets.isEmpty else { return }

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .audio,
                payload: data,
                channelID: channelID ?? ""
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                guard try self.emit(wireData, to: targets, mode: .unreliable) else { return }
                #if DEBUG
                AudioTelemetry.shared.countStage("audioPacketSend", bytes: wireData.count)
                #endif
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    /// Send pre-built wire data (meshMagic + serialized MeshPacket).
    /// Used when the caller has already created the packet to avoid duplicate packet IDs
    /// when sending on multiple transports.
    func sendRawWireData(_ wireData: Data, reliable: Bool = false) {
        let targets = radio.connectedPeers
        guard !targets.isEmpty else { return }
        do {
            try emit(wireData, to: targets, mode: reliable ? .reliable : .unreliable)
        } catch {
            logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
        }
    }

    func sendControl(_ message: FloorControlMessage, channelID: String? = nil) throws {
        // See sendAudio: recipients are captured before the async hop so a
        // peer dropping mid-flight surfaces as a logged send error, not a
        // message that silently went nowhere.
        let targets = radio.connectedPeers
        guard !targets.isEmpty else { return }
        let payload = try MeshCodable.encoder.encode(message)

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .control,
                payload: payload,
                channelID: channelID ?? ""
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                try self.emit(wireData, to: targets, mode: .reliable)
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    /// Send pre-encoded control data (e.g. text messages already wrapped with TXT! prefix).
    /// The data is wrapped in a MeshPacket and sent reliably to all peers.
    func sendControlData(_ data: Data, channelID: String? = nil) throws {
        // See sendAudio: recipients are captured before the async hop so a
        // peer dropping mid-flight surfaces as a logged send error, not a
        // message that silently went nowhere.
        let targets = radio.connectedPeers
        guard !targets.isEmpty else { return }

        let router = meshRouter
        Task {
            let meshPacket = await router.createPacket(
                type: .control,
                payload: data,
                channelID: channelID ?? ""
            )
            let serialized = meshPacket.serialize()
            var wireData = Data([Self.meshMagic])
            wireData.append(serialized)
            do {
                try self.emit(wireData, to: targets, mode: .reliable)
            } catch {
                self.logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mesh Forwarding

    /// Forward a pre-serialized mesh packet to all connected peers except the one it came from.
    func forwardPacket(_ packet: Data, excludePeer: String) {
        let targets = radio.connectedPeers.filter { $0.displayName != excludePeer }
        guard !targets.isEmpty else { return }

        var wireData = Data([Self.meshMagic])
        wireData.append(packet)

        // Use unreliable for forwarded packets -- they're already best-effort mesh traffic
        do {
            guard try emit(wireData, to: targets, mode: .unreliable) else { return }
        } catch {
            logger.error("MultipeerTransport send failed: \(error.localizedDescription)")
        }
        logger.debug("Mesh forwarded packet to \(targets.count) peers (excluded '\(excludePeer)')")
    }

    // MARK: - The outbound gate

    /// The only place in the app that hands bytes to the radio.
    ///
    /// Demo Mode is enforced here, below every service, rather than in the
    /// views or the demo simulator: whatever produced a packet — push-to-talk
    /// audio, a floor request, a heartbeat, a presence beacon with a check-in
    /// coordinate, cover traffic, a text on a simulated channel — it cannot
    /// reach the air while the sandbox is up. Independently of the sandbox, a
    /// packet addressed to a simulated channel is never transmitted either,
    /// so demo traffic that somehow outlived Demo Mode still goes nowhere.
    ///
    /// - Returns: `true` if the bytes were handed to the radio.
    @discardableResult
    private func emit(_ wireData: Data, to targets: [MCPeerID], mode: MCSessionSendDataMode) throws -> Bool {
        if isSandboxed || Self.isDemoTraffic(wireData) {
            droppedCounter.withLock { $0 += 1 }
            return false
        }
        try radio.send(wireData, toPeers: targets, with: mode)
        return true
    }

    /// Whether wire bytes carry a packet addressed to a simulated channel.
    static func isDemoTraffic(_ wireData: Data) -> Bool {
        guard wireData.count >= 2, wireData.first == meshMagic,
              let packet = MeshPacket.deserialize(Data(wireData.dropFirst())) else {
            return false
        }
        return DemoMode.isDemoChannel(packet.channelID)
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
    ///
    /// The loop body runs on the main actor, same as `start()`/`stop()` and the
    /// callers of this method — otherwise its writes to `reconnectAttempt` and
    /// its advertiser/browser restarts race a pull-to-refresh `stop()`/`start()`.
    @MainActor
    private func startReconnectLoop() {
        reconnectTask?.cancel()
        reconnectAttempt = 0

        reconnectTask = Task { @MainActor [weak self] in
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

                // Fresh instances, never a restart of the old ones — see
                // startDiscovery() for the crash this avoids.
                self.stopDiscovery()
                self.startDiscovery()

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
                self.onReconnectFailed?()
            }
        }
    }
}

// MARK: - PTTTransport

/// The transport surface PTTEngine drives. `MultipeerTransport` is the
/// production conformer; the loopback test suite joins nodes with an
/// in-memory conformer so the full audio/control pipeline can run in-process
/// without radios. Keep this to what PTTEngine actually calls — a wider
/// protocol would just be a second copy of MultipeerTransport's API.
protocol PTTTransport: AnyObject, Sendable {
    func sendAudio(_ data: Data, channelID: String?) throws
    func sendControl(_ message: FloorControlMessage, channelID: String?) throws
}

extension MultipeerTransport: PTTTransport {}

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

        // Announce ourselves to a newly connected peer so the mesh can track
        // liveness. There is deliberately no broadcast on `.notConnected`: that
        // event is about the OTHER device, and the old code answered it with
        // `.peerLeave(peerID: localPeerID)` — announcing that WE had left. A
        // peer's departure is not ours to announce (the floor machine drops
        // third-party leave claims as impersonation anyway); each device
        // observes the disconnect through its own session and ghost tracking.
        if state == .connected {
            do {
                try sendControl(.peerJoin(peerID: localPeerID, peerName: localPeerName))
            } catch {
                logger.error("peerJoin announcement failed to encode: \(error.localizedDescription)")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Demo Mode: real traffic must not mix with simulated peers. Discovery
        // is already stopped, so this only catches packets in flight.
        guard !isSandboxed else { return }

        // All packets must start with the mesh magic byte
        guard data.count >= 2, data[0] == Self.meshMagic else {
            logger.warning("Dropped non-mesh packet from '\(peerID.displayName)' (\(data.count) bytes)")
            return
        }

        let meshData = Data(data.dropFirst())
        guard let meshPacket = MeshPacket.deserialize(meshData) else {
            #if DEBUG
            AudioTelemetry.shared.countStage("packetDeserializeFail")
            #endif
            logger.warning("Failed to deserialize mesh packet from '\(peerID.displayName)'")
            return
        }
        #if DEBUG
        AudioTelemetry.shared.countStage(
            meshPacket.type == .audio ? "audioPacketReceive" : "controlPacketReceive",
            bytes: data.count
        )
        #endif

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

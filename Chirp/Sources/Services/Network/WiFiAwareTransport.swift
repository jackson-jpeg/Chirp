import Foundation
import Network
import OSLog
import WiFiAware

/// Wi-Fi Aware transport for paired devices — long range (100-200m), low latency, real-time audio.
///
/// Runs alongside ``MultipeerTransport``. Both feed into the same ``MeshRouter``,
/// which deduplicates packets by `packetID`. Every byte on the wire uses the same
/// `0xAA` mesh magic prefix so both transports speak an identical wire format.
///
/// Uses iOS 26 `NetworkListener` / `NetworkBrowser` / `NetworkConnection` from the
/// WiFiAware + Network frameworks (WWDC25 Session 228).
@Observable
@MainActor
final class WiFiAwareTransport {

    // MARK: - Properties

    private let logger = Logger(subsystem: Constants.subsystem, category: "WiFiAware")

    /// Required mesh router — all packets flow through it (same as MultipeerTransport).
    let meshRouter: MeshRouter

    /// Stable local peer identity.
    let localPeerID: String
    let localPeerName: String

    /// Observable connection state.
    private(set) var pairedDeviceCount: Int = 0
    private(set) var connectedPeerCount: Int = 0
    private(set) var isSupported: Bool = false

    /// Currently connected peers (mirrors MultipeerTransport.peers).
    private(set) var peers: [ChirpPeer] = []

    /// Peer change callback (same pattern as MultipeerTransport).
    var onPeersChanged: (([ChirpPeer]) -> Void)?

    // MARK: - Private State

    /// Active connections keyed by a stable peer identifier.
    private var connections: [String: NWConnection] = [:]

    /// Lifecycle tasks.
    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var deviceObserverTask: Task<Void, Never>?

    /// Wire format: same 0xAA mesh magic as MultipeerTransport.
    private nonisolated static let meshMagic: UInt8 = 0xAA

    // MARK: - Auto-Reconnection

    private var reconnectTask: Task<Void, Never>?
    private var previousPeerCount: Int = 0
    private var reconnectBackoff: TimeInterval = 2.0
    private static let maxBackoff: TimeInterval = 30.0
    private static let initialBackoff: TimeInterval = 2.0

    // MARK: - Init

    init(meshRouter: MeshRouter, localPeerID: String, localPeerName: String) {
        self.meshRouter = meshRouter
        self.localPeerID = localPeerID
        self.localPeerName = localPeerName
        self.isSupported = WACapabilities.supportedFeatures.contains(.wifiAware)
    }

    // MARK: - Lifecycle

    func start() {
        guard isSupported else {
            logger.info("Wi-Fi Aware not supported on this device — transport inactive")
            return
        }

        startDeviceObserver()
        startListener()
        startBrowser()
        logger.info("WiFiAwareTransport started — listening + browsing as '\(self.localPeerName)'")
    }

    func stop() {
        listenerTask?.cancel()
        browserTask?.cancel()
        deviceObserverTask?.cancel()
        reconnectTask?.cancel()

        listenerTask = nil
        browserTask = nil
        deviceObserverTask = nil
        reconnectTask = nil

        connections.removeAll()
        peers.removeAll()
        connectedPeerCount = 0
        previousPeerCount = 0
        reconnectBackoff = Self.initialBackoff

        logger.info("WiFiAwareTransport stopped")
    }

    // MARK: - Paired Device Observation

    private func startDeviceObserver() {
        deviceObserverTask?.cancel()
        deviceObserverTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await devices in WAPairedDevice.allDevices {
                    guard !Task.isCancelled else { break }
                    self.pairedDeviceCount = devices.count
                    self.logger.debug("Paired devices updated: \(devices.count)")
                }
            } catch {
                self.logger.error("Device observation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Listener (Publisher)

    private func startListener() {
        guard let service = WAPublishableService.chirpPTT else {
            logger.error("chirp-ptt publishable service not found in Info.plist WiFiAwareServices")
            return
        }

        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Accept connections from ALL paired devices (.selected([])).
                // Use realtime performance mode + interactiveVoice for PTT audio.
                let listener = try NetworkListener(
                    for: .wifiAware(.connecting(to: service, from: .selected([]))),
                    using: .udp
                )
                .onStateUpdate { [weak self] _, state in
                    Task { @MainActor in
                        self?.logger.info("WiFiAware listener state: \(String(describing: state))")
                    }
                }

                // listener.run blocks until cancelled, yielding inbound connections.
                try await listener.run { [weak self] inboundConnection in
                    guard let self else { return }
                    let peerID = "wa-\(UUID().uuidString.prefix(8))"
                    // Extract the underlying NWConnection for data transfer
                    let nwConnection = inboundConnection.nwConnection
                    Task { @MainActor in
                        self.logger.info("WiFiAware inbound connection from \(peerID)")
                        nwConnection.start(queue: .main)
                        self.handleEstablishedConnection(nwConnection, peerID: peerID)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.logger.error("WiFiAware listener failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Browser (Subscriber)

    private func startBrowser() {
        guard let service = WASubscribableService.chirpPTT else {
            logger.error("chirp-ptt subscribable service not found in Info.plist WiFiAwareServices")
            return
        }

        browserTask?.cancel()
        browserTask = Task { [weak self] in
            guard let self else { return }
            do {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .selected([]), from: service))
                )
                .onStateUpdate { [weak self] _, state in
                    Task { @MainActor in
                        self?.logger.info("WiFiAware browser state: \(String(describing: state))")
                    }
                }

                // browser.run yields discovered endpoints. Connect to the first one found.
                let endpoint = try await browser.run { waEndpoints in
                    if let endpoint = waEndpoints.first {
                        return .finish(endpoint)
                    }
                    return .continue
                }

                // Establish outbound connection to discovered endpoint
                // Create NWConnection to the discovered Wi-Fi Aware endpoint
                let nwConnection = NWConnection(to: endpoint, using: .udp)
                let peerID = "wa-\(UUID().uuidString.prefix(8))"

                nwConnection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    Task { @MainActor in
                        self.logger.info("WiFiAware outbound connection state: \(String(describing: state))")
                    }
                }
                nwConnection.start(queue: .main)

                self.handleEstablishedConnection(nwConnection, peerID: peerID)

            } catch {
                if !Task.isCancelled {
                    self.logger.error("WiFiAware browser failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Connection Handling

    private func handleEstablishedConnection(_ connection: NWConnection, peerID: String) {
        connections[peerID] = connection
        updatePeerList()

        // Announce ourselves
        try? sendControl(.peerJoin(peerID: localPeerID, peerName: localPeerName))

        // Start receive loop
        startReceiveLoop(connection: connection, peerID: peerID)

        logger.info("WiFiAware peer connected: \(peerID) (total: \(self.connections.count))")
    }

    private nonisolated func startReceiveLoop(connection: NWConnection, peerID: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.handleReceivedData(data, from: peerID)
            }

            if let error {
                Task { @MainActor in
                    self.logger.warning("WiFiAware receive error from \(peerID): \(error.localizedDescription)")
                    self.connections.removeValue(forKey: peerID)
                    self.updatePeerList()
                }
                return
            }

            if isComplete {
                Task { @MainActor in
                    self.connections.removeValue(forKey: peerID)
                    self.updatePeerList()
                }
                return
            }

            // Continue receiving
            self.startReceiveLoop(connection: connection, peerID: peerID)
        }
    }

    // MARK: - Receive

    private nonisolated func handleReceivedData(_ data: Data, from peerID: String) {
        // Same wire format as MultipeerTransport: 0xAA + MeshPacket
        let magic = Self.meshMagic
        guard data.count >= 2, data[0] == magic else { return }

        let meshData = Data(data.dropFirst())
        guard let meshPacket = MeshPacket.deserialize(meshData) else { return }

        let router = meshRouter
        Task {
            let _ = await router.handleIncoming(packet: meshPacket, fromPeer: peerID)
        }
    }

    // MARK: - Send

    func sendAudio(_ data: Data, sequenceNumber: UInt32 = 0, channelID: String? = nil) throws {
        guard !connections.isEmpty else { return }

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
            self.broadcastToAll(wireData)
        }
    }

    func sendControl(_ message: FloorControlMessage, channelID: String? = nil) throws {
        guard !connections.isEmpty else { return }
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
            self.broadcastToAll(wireData)
        }
    }

    /// Send pre-encoded control data (e.g. text messages already wrapped with TXT! prefix).
    func sendControlData(_ data: Data, channelID: String? = nil) throws {
        guard !connections.isEmpty else { return }

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
            self.broadcastToAll(wireData)
        }
    }

    // MARK: - Mesh Forwarding

    /// Forward a pre-serialized mesh packet to all connected peers except the one it came from.
    func forwardPacket(_ packet: Data, excludePeer: String) {
        var wireData = Data([Self.meshMagic])
        wireData.append(packet)

        for (peerID, connection) in connections where peerID != excludePeer {
            connection.send(content: wireData, completion: .idempotent)
        }

        let targetCount = connections.keys.filter { $0 != excludePeer }.count
        if targetCount > 0 {
            logger.debug("Mesh forwarded packet to \(targetCount) WiFiAware peers (excluded '\(excludePeer)')")
        }
    }

    // MARK: - Private Helpers

    private func broadcastToAll(_ data: Data) {
        for (_, connection) in connections {
            connection.send(content: data, completion: .idempotent)
        }
    }

    private func updatePeerList() {
        let currentCount = connections.count
        connectedPeerCount = currentCount

        peers = connections.keys.map { id in
            ChirpPeer(
                id: id,
                name: id,
                isConnected: true,
                signalStrength: 3,
                transportType: .wifiAware
            )
        }
        onPeersChanged?(peers)
        logger.info("WiFiAware peers updated: \(currentCount) connected")

        // Auto-reconnection: if we had peers but now have none, schedule reconnect
        if currentCount == 0 && previousPeerCount > 0 {
            scheduleReconnect()
        } else if currentCount > 0 {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectBackoff = Self.initialBackoff
        }

        previousPeerCount = currentCount
    }

    // MARK: - Auto-Reconnection

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = reconnectBackoff
        logger.info("All WiFiAware peers lost — scheduling reconnect in \(delay)s")

        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return // Cancelled
            }
            guard let self, !Task.isCancelled else { return }

            self.logger.info("WiFiAware reconnecting: restarting listener + browser")
            self.listenerTask?.cancel()
            self.browserTask?.cancel()
            self.startListener()
            self.startBrowser()

            self.reconnectBackoff = min(self.reconnectBackoff * 2.0, Self.maxBackoff)
        }
    }
}

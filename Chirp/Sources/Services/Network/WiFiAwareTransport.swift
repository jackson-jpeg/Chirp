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
/// Wi-Fi Aware requires:
/// - iPhone 12+ hardware
/// - iOS 26+
/// - One-time device pairing via `DeviceDiscoveryUI`
/// - `com.apple.developer.wifi-aware` entitlement (already configured)
/// - `WiFiAwareServices` in Info.plist (already configured for `_chirp-ptt._udp`)
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
    private static let meshMagic: UInt8 = 0xAA

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

        for (_, conn) in connections {
            conn.cancel()
        }
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
                // Create Wi-Fi Aware listener — accept connections from all paired devices.
                // .selected([]) means "any paired device"; we don't filter by specific device.
                let parameters = NWParameters()
                parameters.requiredInterfaceType = .wifiAware
                parameters.serviceClass = .interactiveVoice

                let listener = try NWListener(
                    for: .wifiAware(.connecting(to: service, from: .selected([]))),
                    using: parameters
                )

                listener.stateUpdateHandler = { [weak self] state in
                    self?.logger.info("WiFiAware listener state: \(String(describing: state))")
                }

                listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { return }
                    let peerID = "wa-\(connection.endpoint.debugDescription.prefix(16))"
                    self.logger.info("WiFiAware inbound connection from \(peerID)")
                    self.setupConnection(connection, peerID: peerID)
                }

                listener.start(queue: .main)

                // Keep the task alive while the listener runs
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                }

                listener.cancel()
            } catch {
                self.logger.error("WiFiAware listener failed: \(error.localizedDescription)")
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
                let parameters = NWParameters()
                parameters.requiredInterfaceType = .wifiAware
                parameters.serviceClass = .interactiveVoice

                let browser = NWBrowser(
                    for: .wifiAware(.connecting(to: .selected([]), from: service)),
                    using: parameters
                )

                browser.stateUpdateHandler = { [weak self] state in
                    self?.logger.info("WiFiAware browser state: \(String(describing: state))")
                }

                browser.browseResultsChangedHandler = { [weak self] results, changes in
                    guard let self else { return }
                    for result in results {
                        let endpointID = "wa-\(result.endpoint.debugDescription.prefix(16))"
                        // Only connect if we don't already have a connection to this peer
                        guard self.connections[endpointID] == nil else { continue }

                        self.logger.info("WiFiAware discovered endpoint: \(endpointID)")
                        let connection = NWConnection(to: result.endpoint, using: parameters)
                        self.setupConnection(connection, peerID: endpointID)
                    }
                }

                browser.start(queue: .main)

                // Keep the task alive while the browser runs
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                }

                browser.cancel()
            } catch {
                self.logger.error("WiFiAware browser failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Connection Handling

    private func setupConnection(_ connection: NWConnection, peerID: String) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("WiFiAware peer connected: \(peerID)")
                self.connections[peerID] = connection
                self.updatePeerList()

                // Announce ourselves
                try? self.sendControl(.peerJoin(peerID: self.localPeerID, peerName: self.localPeerName))

                // Start receive loop
                self.receiveLoop(connection: connection, peerID: peerID)

            case .failed(let error):
                self.logger.warning("WiFiAware connection failed for \(peerID): \(error.localizedDescription)")
                self.connections.removeValue(forKey: peerID)
                self.updatePeerList()

            case .cancelled:
                self.logger.info("WiFiAware connection cancelled for \(peerID)")
                self.connections.removeValue(forKey: peerID)
                self.updatePeerList()

            case .waiting(let error):
                self.logger.info("WiFiAware connection waiting for \(peerID): \(error.localizedDescription)")

            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    // MARK: - Receive

    private func receiveLoop(connection: NWConnection, peerID: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.handleReceivedData(data, from: peerID)
            }

            if let error {
                self.logger.warning("WiFiAware receive error from \(peerID): \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if isComplete {
                self.logger.info("WiFiAware connection completed for \(peerID)")
                connection.cancel()
                return
            }

            // Continue receiving
            self.receiveLoop(connection: connection, peerID: peerID)
        }
    }

    private func handleReceivedData(_ data: Data, from peerID: String) {
        // Same wire format as MultipeerTransport: 0xAA + MeshPacket
        guard data.count >= 2, data[0] == Self.meshMagic else {
            logger.warning("Dropped non-mesh packet from \(peerID) (\(data.count) bytes)")
            return
        }

        let meshData = Data(data.dropFirst())
        guard let meshPacket = MeshPacket.deserialize(meshData) else {
            logger.warning("Failed to deserialize mesh packet from \(peerID)")
            return
        }

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
            connection.send(content: wireData, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.warning("Forward send error to \(peerID): \(error.localizedDescription)")
                }
            })
        }

        let targetCount = connections.keys.filter { $0 != excludePeer }.count
        if targetCount > 0 {
            logger.debug("Mesh forwarded packet to \(targetCount) WiFiAware peers (excluded '\(excludePeer)')")
        }
    }

    // MARK: - Private Helpers

    private func broadcastToAll(_ data: Data) {
        for (peerID, connection) in connections {
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.logger.warning("Broadcast send error to \(peerID): \(error.localizedDescription)")
                }
            })
        }
    }

    private func updatePeerList() {
        let currentCount = connections.count
        connectedPeerCount = currentCount

        peers = connections.keys.map { id in
            ChirpPeer(
                id: id,
                name: id, // Updated with real name from pairing info when available
                isConnected: true,
                signalStrength: 3 // Wi-Fi Aware = strong signal
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

            // Stop and restart discovery
            self.listenerTask?.cancel()
            self.browserTask?.cancel()
            self.startListener()
            self.startBrowser()

            // Exponential backoff, capped
            self.reconnectBackoff = min(self.reconnectBackoff * 2.0, Self.maxBackoff)
        }
    }
}

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
/// Uses iOS 26 `NetworkListener` / `NetworkBrowser` / `NetworkConnection` from
/// WiFiAware + Network frameworks (WWDC25 Session 228).
///
/// Connection objects are stored opaquely via send/cancel closures to avoid
/// exposing the `NetworkConnection<ApplicationProtocol>` generic parameter.
@Observable
@MainActor
final class WiFiAwareTransport {

    // MARK: - Properties

    private let logger = Logger(subsystem: Constants.subsystem, category: "WiFiAware")

    let meshRouter: MeshRouter
    let localPeerID: String
    let localPeerName: String

    private(set) var pairedDeviceCount: Int = 0
    private(set) var connectedPeerCount: Int = 0
    private(set) var isSupported: Bool = false
    private(set) var peers: [ChirpPeer] = []

    var onPeersChanged: (([ChirpPeer]) -> Void)?

    // MARK: - Connection Tracking

    /// Opaque handle to a Wi-Fi Aware peer connection.
    /// Wraps `NetworkConnection<T>.send` / cancel so we don't leak the generic.
    private struct PeerHandle {
        let id: String
        let send: @Sendable (Data) -> Void
        let cancel: @Sendable () -> Void
    }

    private var activePeers: [String: PeerHandle] = [:]

    // MARK: - Tasks

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var deviceObserverTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Constants

    nonisolated static let meshMagic: UInt8 = 0xAA

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
            logger.info("Wi-Fi Aware not supported — transport inactive")
            return
        }
        startDeviceObserver()
        startListener()
        startBrowser()
        logger.info("WiFiAwareTransport started")
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

        for (_, handle) in activePeers { handle.cancel() }
        activePeers.removeAll()
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
                    self.logger.debug("Paired devices: \(devices.count)")
                }
            } catch {
                self.logger.error("Device observation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Listener (Publisher)

    private func startListener() {
        guard let service = WAPublishableService.chirpPTT else {
            logger.error("chirp-ptt publishable service not found in Info.plist")
            return
        }

        listenerTask?.cancel()
        listenerTask = Task { [weak self] in
            guard let self else { return }
            do {
                let listener = try NetworkListener(
                    for: .wifiAware(.connecting(to: service, from: .selected([]))),
                    using: .parameters { TLS() }
                )
                .onStateUpdate { [weak self] _, state in
                    Task { @MainActor in
                        self?.logger.info("WiFiAware listener: \(String(describing: state))")
                    }
                }

                try await listener.run { [weak self] connection in
                    guard let self else { return }
                    let peerID = "wa-in-\(UUID().uuidString.prefix(8))"
                    self.registerConnection(connection, peerID: peerID)
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
            logger.error("chirp-ptt subscribable service not found in Info.plist")
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
                        self?.logger.info("WiFiAware browser: \(String(describing: state))")
                    }
                }

                let endpoint = try await browser.run { waEndpoints in
                    if let ep = waEndpoints.first {
                        return .finish(ep)
                    }
                    return .continue
                }

                let connection = NetworkConnection(
                    to: endpoint,
                    using: .parameters { TLS() }
                )
                .onStateUpdate { [weak self] _, state in
                    Task { @MainActor in
                        self?.logger.info("WiFiAware outbound: \(String(describing: state))")
                    }
                }

                let peerID = "wa-out-\(UUID().uuidString.prefix(8))"
                self.registerConnection(connection, peerID: peerID)

            } catch {
                if !Task.isCancelled {
                    self.logger.error("WiFiAware browser failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Connection Registration

    /// Register any `NetworkConnection<T>` by capturing its send/cancel as closures.
    /// This erases the generic parameter so we can store handles uniformly.
    private func registerConnection<T>(_ connection: NetworkConnection<T>, peerID: String) {
        // Capture send and cancel as type-erased closures
        let handle = PeerHandle(
            id: peerID,
            send: { data in connection.send(data) },
            cancel: { connection.cancel() }
        )

        activePeers[peerID] = handle
        updatePeerList()

        // Announce ourselves
        try? sendControl(.peerJoin(peerID: localPeerID, peerName: localPeerName))

        // Start receive loop
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await message in connection.messages {
                    self.handleReceivedData(message, from: peerID)
                }
            } catch {
                self.logger.info("WiFiAware connection closed: \(peerID)")
            }
            self.activePeers.removeValue(forKey: peerID)
            self.updatePeerList()
        }

        logger.info("WiFiAware peer registered: \(peerID) (total: \(self.activePeers.count))")
    }

    // MARK: - Receive

    private func handleReceivedData(_ data: Data, from peerID: String) {
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
        guard !activePeers.isEmpty else { return }
        let router = meshRouter
        Task {
            let packet = await router.createPacket(
                type: .audio, payload: data,
                channelID: channelID ?? "", sequenceNumber: sequenceNumber
            )
            var wireData = Data([Self.meshMagic])
            wireData.append(packet.serialize())
            self.broadcastToAll(wireData)
        }
    }

    func sendControl(_ message: FloorControlMessage, channelID: String? = nil) throws {
        guard !activePeers.isEmpty else { return }
        let payload = try MeshCodable.encoder.encode(message)
        let router = meshRouter
        Task {
            let packet = await router.createPacket(
                type: .control, payload: payload,
                channelID: channelID ?? "", sequenceNumber: 0
            )
            var wireData = Data([Self.meshMagic])
            wireData.append(packet.serialize())
            self.broadcastToAll(wireData)
        }
    }

    func sendControlData(_ data: Data, channelID: String? = nil) throws {
        guard !activePeers.isEmpty else { return }
        let router = meshRouter
        Task {
            let packet = await router.createPacket(
                type: .control, payload: data,
                channelID: channelID ?? "", sequenceNumber: 0
            )
            var wireData = Data([Self.meshMagic])
            wireData.append(packet.serialize())
            self.broadcastToAll(wireData)
        }
    }

    func forwardPacket(_ packet: Data, excludePeer: String) {
        var wireData = Data([Self.meshMagic])
        wireData.append(packet)
        for (peerID, handle) in activePeers where peerID != excludePeer {
            handle.send(wireData)
        }
    }

    // MARK: - Private

    private func broadcastToAll(_ data: Data) {
        for (_, handle) in activePeers {
            handle.send(data)
        }
    }

    private func updatePeerList() {
        let count = activePeers.count
        connectedPeerCount = count
        peers = activePeers.keys.map { id in
            ChirpPeer(id: id, name: id, isConnected: true, signalStrength: 3, transportType: .wifiAware)
        }
        onPeersChanged?(peers)

        if count == 0 && previousPeerCount > 0 {
            scheduleReconnect()
        } else if count > 0 {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectBackoff = Self.initialBackoff
        }
        previousPeerCount = count
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = reconnectBackoff
        logger.info("All WiFiAware peers lost — reconnect in \(delay)s")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.listenerTask?.cancel()
            self.browserTask?.cancel()
            self.startListener()
            self.startBrowser()
            self.reconnectBackoff = min(self.reconnectBackoff * 2.0, Self.maxBackoff)
        }
    }
}

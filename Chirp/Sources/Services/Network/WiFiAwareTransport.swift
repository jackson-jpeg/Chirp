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
/// Uses iOS 26 `NetworkListener` / `NetworkBrowser` / `NetworkConnection` with
/// TLV (Type-Length-Value) framing over TLS for message-based data exchange.
/// (WWDC25 Sessions 228 + 250)
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
    private(set) var realtimeMode = false
    private(set) var linkMetrics: [String: WALinkMetrics] = [:]

    var onPeersChanged: (([ChirpPeer]) -> Void)?

    // MARK: - Connection Tracking

    /// Each peer connection is managed by its own Task. We store send closures
    /// to broadcast mesh packets, type-erasing the NetworkConnection generic.
    private struct PeerHandle: Sendable {
        let id: String
        let send: @Sendable (Data) async throws -> Void
        let fetchPath: @Sendable () -> NWPath?
        let task: Task<Void, Never>
    }

    private var activePeers: [String: PeerHandle] = [:]

    // MARK: - Tasks

    private var listenerTask: Task<Void, Never>?
    private var browserTask: Task<Void, Never>?
    private var deviceObserverTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var metricsPollingTask: Task<Void, Never>?

    nonisolated static let meshMagic: UInt8 = 0xAA

    /// TLV type value for mesh packets (arbitrary, just needs to be consistent).
    private static let meshTLVType: Int = 0x4D45 // "ME" for mesh

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

    // MARK: - Realtime Mode

    /// Toggle realtime (low-latency) Wi-Fi Aware datapath for active PTT transmission.
    /// When enabled, the listener is restarted with `.realtime` datapath parameters
    /// and audio packets are sent with `.interactiveVoice` QoS priority.
    func setRealtimeMode(_ enabled: Bool) {
        guard realtimeMode != enabled else { return }
        realtimeMode = enabled
        logger.info("WiFiAware realtime mode: \(enabled ? "ON" : "OFF")")

        // Restart listener with updated datapath parameters
        if isSupported && listenerTask != nil {
            startListener()
        }
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
        startMetricsPolling()
        logger.info("WiFiAwareTransport started")
    }

    func stop() {
        listenerTask?.cancel()
        browserTask?.cancel()
        deviceObserverTask?.cancel()
        reconnectTask?.cancel()
        metricsPollingTask?.cancel()
        listenerTask = nil
        browserTask = nil
        deviceObserverTask = nil
        reconnectTask = nil
        metricsPollingTask = nil

        for (_, handle) in activePeers { handle.task.cancel() }
        activePeers.removeAll()
        peers.removeAll()
        connectedPeerCount = 0
        previousPeerCount = 0
        linkMetrics.removeAll()
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
                // TLV framing over TLS gives us message boundaries + encryption.
                // Wi-Fi Aware adds Wi-Fi layer encryption on top.
                // Use .realtime datapath during active PTT for low-latency audio.
                let datapathParams: WAPublisherListener.DatapathParameters = self.realtimeMode ? .realtime : .defaults
                try await NetworkListener(
                    for: .wifiAware(.connecting(to: service, from: .selected([]), datapath: datapathParams))
                ) {
                    TLV {
                        TLS()
                    }
                }
                .run { [weak self] connection in
                    guard let self else { return }
                    let peerID = "wa-in-\(UUID().uuidString.prefix(8))"
                    Task { @MainActor in
                        self.registerConnection(connection, peerID: peerID)
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

                let endpoint = try await browser.run { waEndpoints in
                    if let ep = waEndpoints.first {
                        return .finish(ep)
                    }
                    return .continue
                }

                let connection = NetworkConnection(to: endpoint) {
                    TLV {
                        TLS()
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

    /// Register a TLV-framed NetworkConnection by type-erasing it into a PeerHandle.
    private func registerConnection(
        _ connection: NetworkConnection<TLV>,
        peerID: String
    ) {
        // Create send closure that captures the typed connection
        let sendClosure: @Sendable (Data) async throws -> Void = { data in
            try await connection.send(data, type: Self.meshTLVType)
        }
        let fetchPathClosure: @Sendable () -> NWPath? = {
            connection.currentPath
        }

        // Receive task: reads messages and feeds to mesh router
        let receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await (incomingData, _) in connection.messages {
                    self.handleReceivedData(incomingData, from: peerID)
                }
            } catch {
                if !Task.isCancelled {
                    self.logger.info("WiFiAware connection ended: \(peerID) — \(error.localizedDescription)")
                }
            }
            // Connection closed — clean up
            self.activePeers.removeValue(forKey: peerID)
            self.updatePeerList()
        }

        let handle = PeerHandle(id: peerID, send: sendClosure, fetchPath: fetchPathClosure, task: receiveTask)
        activePeers[peerID] = handle
        updatePeerList()

        // Announce ourselves
        Task {
            try? await self.sendControlAsync(.peerJoin(peerID: self.localPeerID, peerName: self.localPeerName))
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

    // MARK: - Send (Public API)

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
            await self.broadcastToAll(wireData)
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
            await self.broadcastToAll(wireData)
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
            await self.broadcastToAll(wireData)
        }
    }

    func forwardPacket(_ packet: Data, excludePeer: String) {
        var wireData = Data([Self.meshMagic])
        wireData.append(packet)
        Task {
            for (peerID, handle) in self.activePeers where peerID != excludePeer {
                try? await handle.send(wireData)
            }
        }
    }

    // MARK: - Private Send Helpers

    private func sendControlAsync(_ message: FloorControlMessage) async throws {
        let payload = try MeshCodable.encoder.encode(message)
        let router = meshRouter
        let packet = await router.createPacket(
            type: .control, payload: payload, channelID: "", sequenceNumber: 0
        )
        var wireData = Data([Self.meshMagic])
        wireData.append(packet.serialize())
        await broadcastToAll(wireData)
    }

    private func broadcastToAll(_ data: Data) async {
        for (_, handle) in activePeers {
            try? await handle.send(data)
        }
    }

    // MARK: - Link Quality Metrics Polling

    private func startMetricsPolling() {
        metricsPollingTask?.cancel()
        metricsPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { break }
                await self.pollMetrics()
            }
        }
    }

    private func pollMetrics() async {
        for (peerID, handle) in activePeers {
            guard let path = handle.fetchPath() else { continue }
            guard let waPath = try? await path.wifiAware else { continue }

            let perf = waPath.performance
            let metrics = WALinkMetrics(
                peerID: peerID,
                deviceName: peerID,
                signalStrength: perf.signalStrength,
                throughputCeiling: perf.throughputCeiling,
                throughputCapacity: perf.throughputCapacity,
                capacityRatio: perf.throughputCapacityRatio,
                voiceLatency: perf.transmitLatency[.interactiveVoice]?.average,
                videoLatency: perf.transmitLatency[.interactiveVideo]?.average,
                bestEffortLatency: perf.transmitLatency[.bestEffort]?.average,
                connectionUptime: waPath.durationActive
            )
            linkMetrics[peerID] = metrics
        }

        // Remove metrics for peers that are no longer active
        let activeIDs = Set(activePeers.keys)
        for key in linkMetrics.keys where !activeIDs.contains(key) {
            linkMetrics.removeValue(forKey: key)
        }
    }

    // MARK: - Peer List

    private func updatePeerList() {
        let count = activePeers.count
        connectedPeerCount = count
        peers = activePeers.keys.map { id in
            let signal = linkMetrics[id]?.signalBars ?? 3
            return ChirpPeer(id: id, name: id, isConnected: true, signalStrength: signal, transportType: .wifiAware)
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

    // MARK: - Auto-Reconnection

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

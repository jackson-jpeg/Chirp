import Foundation
import Network
import os
#if canImport(WiFiAware)
import WiFiAware
#endif

/// Core networking actor. Every Chirp device runs as both publisher (listener) and
/// subscriber (browser) simultaneously, forming a peer-to-peer mesh over Wi-Fi Aware.
actor ConnectionManager: TransportProtocol {

    // MARK: - Types

    private enum PacketType: UInt8 {
        case audio = 0x01
        case control = 0x02
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.chirp.ptt", category: "ConnectionManager")
    private let peerTracker = PeerTracker()

    private var connections: [String: NWConnection] = [:]
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var isRunning = false

    // Stream backing storage
    private let audioContinuation: AsyncStream<Data>.Continuation
    private let controlContinuation: AsyncStream<FloorControlMessage>.Continuation

    nonisolated let audioPackets: AsyncStream<Data>
    nonisolated let controlMessages: AsyncStream<FloorControlMessage>

    // MARK: - Init

    init() {
        var audioCont: AsyncStream<Data>.Continuation!
        audioPackets = AsyncStream<Data> { audioCont = $0 }
        audioContinuation = audioCont

        var controlCont: AsyncStream<FloorControlMessage>.Continuation!
        controlMessages = AsyncStream<FloorControlMessage> { controlCont = $0 }
        controlContinuation = controlCont
    }

    deinit {
        audioContinuation.finish()
        controlContinuation.finish()
    }

    // MARK: - TransportProtocol

    var connectedPeers: [ChirpPeer] {
        get async {
            await peerTracker.connectedPeers
        }
    }

    func sendAudio(_ data: Data) async throws {
        let packet = encodePacket(type: .audio, payload: data)
        // Best-effort: fire to all peers, don't wait for acks
        for (peerID, connection) in connections {
            connection.send(
                content: packet,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { [logger] error in
                    if let error {
                        logger.debug("Audio send to \(peerID) failed: \(error.localizedDescription)")
                    }
                }
            )
        }
    }

    func sendControl(_ message: FloorControlMessage) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(message)
        let packet = encodePacket(type: .control, payload: payload)

        // Reliable: send to all peers
        for (peerID, connection) in connections {
            connection.send(
                content: packet,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { [logger] error in
                    if let error {
                        logger.error("Control send to \(peerID) failed: \(error.localizedDescription)")
                    }
                }
            )
        }
    }

    // MARK: - Lifecycle

    func start(deviceFilter: String? = nil) async {
        guard !isRunning else {
            logger.warning("ConnectionManager already running")
            return
        }
        isRunning = true
        logger.info("Starting ConnectionManager")

        let parameters = makeNWParameters()

        // Start listener (publisher)
        startListener(parameters: parameters)

        // Start browser (subscriber)
        startBrowser(parameters: parameters, deviceFilter: deviceFilter)

        // Start peer health monitoring
        await peerTracker.startHealthCheck()
    }

    func stop() async {
        logger.info("Stopping ConnectionManager")
        isRunning = false

        listener?.cancel()
        listener = nil

        browser?.cancel()
        browser = nil

        for (id, connection) in connections {
            connection.cancel()
            logger.debug("Closed connection to \(id)")
        }
        connections.removeAll()

        await peerTracker.stopHealthCheck()
        audioContinuation.finish()
        controlContinuation.finish()
    }

    // MARK: - NWParameters

    private func makeNWParameters() -> NWParameters {
        #if canImport(WiFiAware)
        return makeWiFiAwareParameters()
        #else
        logger.warning("Wi-Fi Aware not available — using TCP fallback for development")
        return NWParameters.tcp
        #endif
    }

    #if canImport(WiFiAware)
    private func makeWiFiAwareParameters() -> NWParameters {
        // Wi-Fi Aware uses the standard NWParameters with TLS
        // The actual Wi-Fi Aware transport is configured via
        // NetworkListener/NetworkBrowser with .wifiAware descriptors
        let parameters = NWParameters.tcp
        parameters.serviceClass = .interactiveVoice
        return parameters
    }
    #endif

    // MARK: - Listener (Publisher)

    private func startListener(parameters: NWParameters) {
        do {
            let newListener = try NWListener(using: parameters)

            #if canImport(WiFiAware)
            newListener.service = NWListener.Service(type: "_chirp-ptt._udp")
            #else
            newListener.service = NWListener.Service(type: "_chirp-ptt._tcp", domain: "local")
            #endif

            newListener.stateUpdateHandler = { [logger] state in
                switch state {
                case .ready:
                    logger.info("Listener ready")
                case .failed(let error):
                    logger.error("Listener failed: \(error.localizedDescription)")
                case .cancelled:
                    logger.info("Listener cancelled")
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task {
                    await self.handleIncomingConnection(connection)
                }
            }

            newListener.start(queue: DispatchQueue.global(qos: .userInteractive))
            listener = newListener
            logger.info("Listener started")
        } catch {
            logger.error("Failed to create listener: \(error.localizedDescription)")
        }
    }

    // MARK: - Browser (Subscriber)

    private func startBrowser(parameters: NWParameters, deviceFilter: String?) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_chirp-ptt._tcp", domain: "local")

        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [logger] (state: NWBrowser.State) in
            switch state {
            case .ready:
                logger.info("Browser ready")
            case .failed(let error):
                logger.error("Browser failed: \(error.localizedDescription)")
            case .cancelled:
                logger.info("Browser cancelled")
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) in
            guard let self else { return }
            Task {
                await self.handleBrowseResults(results, changes: changes)
            }
        }

        newBrowser.start(queue: DispatchQueue.global(qos: .userInteractive))
        browser = newBrowser
        logger.info("Browser started")
    }

    // MARK: - Connection Handling

    private func handleBrowseResults(
        _ results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>
    ) {
        for change in changes {
            switch change {
            case .added(let result):
                let endpointID = endpointIdentifier(result.endpoint)
                guard connections[endpointID] == nil else { continue }
                logger.info("Discovered peer: \(endpointID)")
                connectToPeer(endpoint: result.endpoint, id: endpointID)

            case .removed(let result):
                let endpointID = endpointIdentifier(result.endpoint)
                logger.info("Peer removed: \(endpointID)")
                disconnectPeer(id: endpointID)

            default:
                break
            }
        }
    }

    private func connectToPeer(endpoint: NWEndpoint, id: String) {
        let parameters = makeNWParameters()
        let connection = NWConnection(to: endpoint, using: parameters)

        connection.stateUpdateHandler = { [weak self, logger] state in
            guard let self else { return }
            switch state {
            case .ready:
                logger.info("Connected to peer: \(id)")
                Task {
                    await self.peerTracker.updatePeer(id: id, name: id)
                    await self.startReceiveLoop(connection: connection, peerID: id)
                }
            case .failed(let error):
                logger.error("Connection to \(id) failed: \(error.localizedDescription)")
                Task { await self.disconnectPeer(id: id) }
            case .cancelled:
                logger.debug("Connection to \(id) cancelled")
            default:
                break
            }
        }

        connections[id] = connection
        connection.start(queue: DispatchQueue.global(qos: .userInteractive))
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        let id = endpointIdentifier(connection.endpoint)
        logger.info("Incoming connection from: \(id)")

        connection.stateUpdateHandler = { [weak self, logger] state in
            guard let self else { return }
            switch state {
            case .ready:
                logger.info("Incoming connection ready: \(id)")
                Task {
                    await self.registerConnection(connection, id: id)
                    await self.peerTracker.updatePeer(id: id, name: id)
                    await self.startReceiveLoop(connection: connection, peerID: id)
                }
            case .failed(let error):
                logger.error("Incoming connection \(id) failed: \(error.localizedDescription)")
                Task { await self.disconnectPeer(id: id) }
            case .cancelled:
                break
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global(qos: .userInteractive))
    }

    private func registerConnection(_ connection: NWConnection, id: String) {
        // Don't overwrite an existing outbound connection
        if connections[id] == nil {
            connections[id] = connection
        }
    }

    private func disconnectPeer(id: String) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        Task { await peerTracker.removePeer(id: id) }
    }

    // MARK: - Receive Loop

    private func startReceiveLoop(connection: NWConnection, peerID: String) {
        Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let data = try await self.receivePacket(on: connection)
                    await self.handleReceivedData(data, from: peerID)
                } catch {
                    await self.logger.debug("Receive loop ended for \(peerID): \(error.localizedDescription)")
                    await self.disconnectPeer(id: peerID)
                    break
                }
            }
        }
    }

    private func receivePacket(on connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: NWError.posix(.ECONNRESET))
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data, from peerID: String) {
        guard data.count >= 1 else {
            logger.warning("Received empty packet from \(peerID)")
            return
        }

        let typeByte = data[data.startIndex]
        let payload = data.dropFirst()

        guard let packetType = PacketType(rawValue: typeByte) else {
            logger.warning("Unknown packet type 0x\(String(typeByte, radix: 16)) from \(peerID)")
            return
        }

        switch packetType {
        case .audio:
            audioContinuation.yield(Data(payload))

        case .control:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let message = try decoder.decode(FloorControlMessage.self, from: Data(payload))
                controlContinuation.yield(message)

                // Handle heartbeats for peer tracking
                if case .heartbeat(let id, let timestamp) = message {
                    Task {
                        await peerTracker.handleHeartbeat(peerID: id, timestamp: timestamp)
                    }
                }
                // Track peer joins
                if case .peerJoin(let id, let name) = message {
                    Task {
                        await peerTracker.updatePeer(id: id, name: name)
                    }
                }
            } catch {
                logger.error("Failed to decode control message from \(peerID): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Packet Encoding

    private func encodePacket(type: PacketType, payload: Data) -> Data {
        var packet = Data(capacity: 1 + payload.count)
        packet.append(type.rawValue)
        packet.append(payload)
        return packet
    }

    // MARK: - Helpers

    private nonisolated func endpointIdentifier(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return endpoint.debugDescription
        }
    }
}

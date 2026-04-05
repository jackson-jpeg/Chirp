import Foundation
import Network
import OSLog

/// Bridges the mesh to the internet.
///
/// When a device has cellular or Wi-Fi connectivity it advertises itself as a
/// **gateway node** via a special beacon (`GW!` magic prefix) over the standard
/// mesh relay path. Other devices in the mesh — even those completely offline —
/// can send text messages (SMS / email) to the outside world by routing a
/// ``GatewayMessage`` to the nearest gateway.
///
/// The actual delivery backend (Twilio, SendGrid, etc.) is a future integration.
/// For now the gateway logs the attempt, increments ``sentCount``, and marks the
/// message as sent so the UI can show progress.
@Observable
@MainActor
final class MeshGateway {

    static let shared = MeshGateway()

    // MARK: - Types

    /// An outbound message destined for the internet via a gateway node.
    struct GatewayMessage: Codable, Sendable, Identifiable {
        let id: UUID
        let fromPeerID: String
        let fromPeerName: String
        let recipientPhone: String?
        let recipientEmail: String?
        let message: String
        let timestamp: Date
    }

    /// Lightweight announcement that a gateway is available in the mesh.
    struct GatewayBeacon: Codable, Sendable {
        let peerID: String
        let peerName: String
        let timestamp: Date
    }

    // MARK: - Public State

    /// True when this device has an active internet path.
    private(set) var hasInternet: Bool = false

    /// True when this device is advertising gateway availability to the mesh.
    private(set) var isGatewayNode: Bool = false

    /// Messages waiting to be delivered by a gateway.
    private(set) var pendingOutbound: [GatewayMessage] = []

    /// Total messages successfully handed off for delivery.
    private(set) var sentCount: Int = 0

    /// Known gateway nodes discovered via mesh beacons (excluding self).
    /// Keyed by peer ID.
    private(set) var knownGateways: [String: GatewayBeacon] = [:]

    /// True if at least one gateway (including self) is reachable.
    var gatewayAvailable: Bool {
        isGatewayNode || !knownGateways.isEmpty
    }

    // MARK: - Constants

    /// Magic bytes prepended to gateway beacon payloads: `GW!`
    static let gatewayMagic: [UInt8] = [0x47, 0x57, 0x21]

    /// Magic bytes prepended to gateway request payloads: `GR!`
    static let requestMagic: [UInt8] = [0x47, 0x52, 0x21]

    /// Stale threshold for gateway beacons (seconds).
    private static let gatewayStaleThreshold: TimeInterval = 15.0

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "Gateway")
    private let monitor = NWPathMonitor()
    private var localPeerID: String = ""
    private var localPeerName: String = ""

    // MARK: - Init

    init() {
        startMonitoring()
    }

    // MARK: - Configuration

    /// Set the local identity so beacons can include peer info.
    func configure(peerID: String, peerName: String) {
        localPeerID = peerID
        localPeerName = peerName
    }

    // MARK: - Network Monitoring

    /// Watch the device's internet connectivity and toggle gateway mode.
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasGateway = self.isGatewayNode
                self.hasInternet = connected
                self.isGatewayNode = connected

                if connected {
                    self.logger.info("Internet available — this device is now a gateway node")
                    self.processOutboundQueue()
                } else {
                    self.logger.info("Internet lost — gateway mode disabled")
                }

                // Broadcast a beacon when gateway status changes
                if connected != wasGateway {
                    self.broadcastGatewayBeacon()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.chirpchirp.gateway.monitor"))
    }

    // MARK: - Outbound Queue

    /// Queue a message for outbound delivery via a gateway.
    func queueOutbound(_ message: GatewayMessage) {
        pendingOutbound.append(message)
        logger.info("Queued outbound message id=\(message.id.uuidString) to \(message.recipientPhone ?? message.recipientEmail ?? "unknown")")

        if isGatewayNode {
            // We have internet — deliver immediately
            processOutboundQueue()
        } else {
            // Route to a known gateway via mesh
            routeToGateway(message)
        }
    }

    /// Process all pending outbound messages.
    /// Called when internet becomes available or a new message is queued locally.
    private func processOutboundQueue() {
        guard hasInternet else { return }
        guard !pendingOutbound.isEmpty else { return }

        let toSend = pendingOutbound
        pendingOutbound.removeAll()

        for message in toSend {
            deliverMessage(message)
        }
    }

    /// Deliver a single message to the outside world via Twilio (SMS) or SendGrid (email).
    private func deliverMessage(_ message: GatewayMessage) {
        if let phone = message.recipientPhone {
            logger.info("GATEWAY SEND [SMS] from=\(message.fromPeerName) to=\(phone) msg=\(message.message.prefix(50))")
        } else if let email = message.recipientEmail {
            logger.info("GATEWAY SEND [Email] from=\(message.fromPeerName) to=\(email) msg=\(message.message.prefix(50))")
        } else {
            logger.warning("Gateway message has no recipient — dropping")
            return
        }

        let delivery = GatewayDeliveryService.shared

        Task { @MainActor in
            let status = await delivery.deliver(message)

            switch status {
            case .sent:
                self.sentCount += 1
                self.logger.info("Gateway delivery succeeded for \(message.id)")
            case .failed:
                self.logger.error("Gateway delivery failed for \(message.id)")
            case .pending:
                break
            }

            // Send a delivery receipt back through the mesh so the sender gets feedback
            self.broadcastDeliveryReceipt(messageID: message.id, status: status)
        }
    }

    /// Broadcast a delivery receipt through the mesh for the original sender.
    private func broadcastDeliveryReceipt(messageID: UUID, status: GatewayDeliveryService.DeliveryStatus) {
        let delivery = GatewayDeliveryService.shared
        guard let payload = delivery.encodeDeliveryReceipt(messageID: messageID, status: status) else { return }

        let packet = MeshPacket(
            type: .control,
            ttl: MeshPacket.adaptiveTTL(for: .control, priority: .normal),
            originID: UUID(uuidString: localPeerID) ?? UUID(),
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        NotificationCenter.default.post(
            name: .meshGatewayDeliveryReceipt,
            object: nil,
            userInfo: ["packet": packet.serialize()]
        )

        logger.info("Broadcast delivery receipt for \(messageID) status=\(status.rawValue)")
    }

    // MARK: - Mesh Routing

    /// Encode a ``GatewayMessage`` as a mesh-routable payload with `GR!` magic.
    private func routeToGateway(_ message: GatewayMessage) {
        guard let json = try? MeshCodable.encoder.encode(message) else {
            logger.error("Failed to encode gateway message for mesh routing")
            return
        }

        var payload = Data(Self.requestMagic)
        payload.append(json)

        // Post for the mesh router to distribute (same pattern as MeshBeacon)
        let packet = MeshPacket(
            type: .control,
            ttl: MeshPacket.adaptiveTTL(for: .control, priority: .high),
            originID: UUID(uuidString: localPeerID) ?? UUID(),
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        NotificationCenter.default.post(
            name: .meshGatewayRequest,
            object: nil,
            userInfo: ["packet": packet.serialize()]
        )

        logger.info("Routed gateway message through mesh for delivery")
    }

    // MARK: - Incoming Handling

    /// Handle a gateway-related payload received from the mesh.
    /// Dispatches to beacon, request, or delivery receipt handling based on magic prefix.
    func handleGatewayPayload(_ data: Data) {
        guard data.count > 3 else { return }
        let magic = Array(data.prefix(3))

        if magic == Self.gatewayMagic {
            handleGatewayBeacon(data)
        } else if magic == Self.requestMagic {
            handleGatewayRequest(data)
        }

        // GDR! is 4 bytes — check separately
        if data.count > 4, Array(data.prefix(4)) == GatewayDeliveryService.receiptMagic {
            GatewayDeliveryService.shared.handleDeliveryReceipt(data)
        }
    }

    /// Handle an incoming gateway beacon from another node.
    private func handleGatewayBeacon(_ data: Data) {
        let jsonData = data.dropFirst(Self.gatewayMagic.count)

        do {
            let beacon = try MeshCodable.decoder.decode(GatewayBeacon.self, from: Data(jsonData))

            // Ignore our own beacons
            guard beacon.peerID != localPeerID else { return }

            knownGateways[beacon.peerID] = beacon
            logger.info("Discovered gateway node: \(beacon.peerName, privacy: .public)")
        } catch {
            logger.debug("Failed to decode gateway beacon: \(error.localizedDescription)")
        }
    }

    /// Handle an incoming gateway request from a mesh peer.
    /// If we have internet, deliver it. Otherwise ignore (another gateway will handle it).
    private func handleGatewayRequest(_ data: Data) {
        guard hasInternet else {
            logger.debug("Received gateway request but no internet — ignoring")
            return
        }

        let jsonData = data.dropFirst(Self.requestMagic.count)

        do {
            let message = try MeshCodable.decoder.decode(GatewayMessage.self, from: Data(jsonData))
            logger.info("Gateway request received from \(message.fromPeerName, privacy: .public) — delivering")
            deliverMessage(message)
        } catch {
            logger.debug("Failed to decode gateway request: \(error.localizedDescription)")
        }
    }

    // MARK: - Beacon Broadcasting

    /// Encode a gateway beacon for mesh broadcast.
    func encodeGatewayBeacon() -> Data? {
        guard isGatewayNode else { return nil }

        let beacon = GatewayBeacon(
            peerID: localPeerID,
            peerName: localPeerName,
            timestamp: Date()
        )

        guard let json = try? MeshCodable.encoder.encode(beacon) else { return nil }
        var payload = Data(Self.gatewayMagic)
        payload.append(json)
        return payload
    }

    /// Broadcast a gateway beacon through the mesh via notification.
    private func broadcastGatewayBeacon() {
        guard let payload = encodeGatewayBeacon() else { return }

        let packet = MeshPacket(
            type: .control,
            ttl: MeshPacket.adaptiveTTL(for: .control, priority: .normal),
            originID: UUID(uuidString: localPeerID) ?? UUID(),
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        NotificationCenter.default.post(
            name: .meshGatewayBeaconBroadcast,
            object: nil,
            userInfo: ["packet": packet.serialize()]
        )

        logger.info("Broadcast gateway beacon")
    }

    // MARK: - Pruning

    /// Remove stale gateway beacons not refreshed within the threshold.
    func pruneStaleGateways() {
        let cutoff = Date().addingTimeInterval(-Self.gatewayStaleThreshold)
        let staleIDs = knownGateways.filter { $0.value.timestamp < cutoff }.map(\.key)

        for id in staleIDs {
            if let gw = knownGateways.removeValue(forKey: id) {
                logger.info("Pruned stale gateway: \(gw.peerName, privacy: .public)")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a gateway request packet is ready for mesh broadcast.
    static let meshGatewayRequest = Notification.Name("com.chirpchirp.meshGatewayRequest")

    /// Posted when a gateway beacon packet is ready for mesh broadcast.
    static let meshGatewayBeaconBroadcast = Notification.Name("com.chirpchirp.meshGatewayBeaconBroadcast")

    /// Posted when a gateway delivery receipt is ready for mesh broadcast.
    static let meshGatewayDeliveryReceipt = Notification.Name("com.chirpchirp.meshGatewayDeliveryReceipt")
}

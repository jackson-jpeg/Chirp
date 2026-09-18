import CoreLocation
import Foundation
import Observation
import OSLog

/// A self-contained, single-device tour of every v1 feature.
///
/// ChirpChirps has no accounts and no servers: everything it does needs a
/// second person standing nearby. Demo Mode supplies four simulated people
/// (``DemoContent``) with chat history, voice messages, map positions and
/// push-to-talk replies, so the whole app can be exercised on one device.
///
/// ## Isolation
/// Demo traffic must never reach a real device, and the guarantee lives at the
/// transport, not here: while Demo Mode is on, ``MultipeerTransport`` is
/// sandboxed — discovery stopped, every outbound packet dropped at its single
/// send gate, every inbound packet ignored — and independently of the sandbox
/// it refuses any packet addressed to a `demo-` channel. This class is only
/// the other half of the conversation: it plays the simulated peers by
/// handing their packets to the same local-delivery handler real packets go
/// through, so what the user sees is the app's real receive path at work.
///
/// Nothing simulated is persisted. Simulated channels overlay the real list
/// in memory, their messages never reach the message database, and the
/// voice-message inbox is overlaid the same way. Turning Demo Mode off
/// restores exactly the real state that was there before.
///
/// The on/off flag itself IS persisted, so an App Review relaunch lands back
/// in Demo Mode rather than on an empty screen.
@Observable
@MainActor
final class DemoMode {

    // MARK: - Identity (usable from any isolation: the transport checks it)

    nonisolated static let channelPrefix = "demo-"
    nonisolated static let defaultsKey = "com.chirpchirp.demoMode"

    nonisolated static func isDemoChannel(_ channelID: String) -> Bool {
        channelID.hasPrefix(channelPrefix)
    }

    // MARK: - State

    /// The user's choice, persisted across launches.
    private(set) var isEnabled: Bool

    /// True once the simulated world is actually on screen.
    private(set) var isActive = false

    /// Simulated peers, for the peer count and rosters. Empty when inactive.
    var peers: [ChirpPeer] { isActive ? DemoContent.chirpPeers : [] }

    // MARK: - Wiring

    /// Set by AppState at the end of its init.
    weak var host: AppState?

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Constants.subsystem, category: "DemoMode")
    private var beaconTask: Task<Void, Never>?
    private var pendingTasks: [Task<Void, Never>] = []
    private var textReplyIndex = 0
    private var pttReplyIndex = 0
    /// Monotonic across every simulated transmission, like a real sender's.
    private var audioSequence: UInt32 = 0
    private var pttReplyInFlight = false
    private var lastFloorState: PTTState = .idle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.defaultsKey)
    }

    // MARK: - On / off

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.defaultsKey)
        if enabled { activate() } else { deactivate() }
    }

    /// Called from `AppState.start()` before the transport starts, so a
    /// relaunch in Demo Mode never opens the radio even briefly.
    func restoreIfEnabled() {
        if isEnabled { activate() }
    }

    private func activate() {
        guard !isActive, let host else { return }
        logger.info("Demo Mode on")

        // 1. Radio silence first, before anything simulated exists.
        host.multipeerTransport.setSandboxed(true)

        // 2. The simulated world, in memory only.
        host.channelManager.enterDemoOverlay(
            channels: DemoContent.channels(),
            activeID: DemoContent.generalID
        )
        seedHistory(into: host)
        seedInbox()

        isActive = true
        host.refreshPeers()

        // 3. Presence: beacons are what draw map pins and the node list, and
        // they go stale after 10 s, so keep them coming.
        beaconTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.deliverBeacons()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func deactivate() {
        guard isActive, let host else { return }
        logger.info("Demo Mode off")

        beaconTask?.cancel()
        beaconTask = nil
        pendingTasks.forEach { $0.cancel() }
        pendingTasks.removeAll()
        pttReplyInFlight = false
        host.voiceClipPlayer.stop()

        // A simulated speaker must not keep the floor after they vanish.
        if let speaker = host.floorSession.currentSpeaker, DemoContent.peerIDs.contains(speaker.id) {
            host.floorSession.peerLost(speaker.id)
        }
        host.audioEngine.resetJitterBuffer()

        host.meshBeacon.forget(ids: DemoContent.peerIDs)
        host.textMessageService.discardChannels(
            [DemoContent.generalID, DemoContent.trailheadID, DemoContent.basecampID]
        )
        host.channelManager.exitDemoOverlay()
        VoiceMessageQueue.shared.exitDemoOverlay()

        isActive = false
        host.refreshPeers()

        // Last: only now may the radio come back.
        host.multipeerTransport.setSandboxed(false)
    }

    // MARK: - Seeding

    private func seedHistory(into host: AppState) {
        let me = host.localPeerID
        let myName = host.callsign
        let now = Date()
        for (channelID, lines) in DemoContent.history {
            let messages: [MeshTextMessage] = lines.compactMap { line in
                switch line {
                case let .text(from, text, minutesAgo, status):
                    return MeshTextMessage(
                        id: UUID(),
                        senderID: from?.id ?? me,
                        senderName: from?.name ?? myName,
                        channelID: channelID,
                        text: text,
                        timestamp: now.addingTimeInterval(-minutesAgo * 60),
                        deliveryStatus: from == nil ? status : .delivered
                    )
                case let .voiceNote(from, clip, _, minutesAgo):
                    guard let url = DemoContent.clipURL(clip, ext: "m4a"),
                          let audio = try? Data(contentsOf: url) else {
                        logger.error("Missing bundled voice note \(clip, privacy: .public)")
                        return nil
                    }
                    return MeshTextMessage(
                        id: UUID(),
                        senderID: from.id,
                        senderName: from.name,
                        channelID: channelID,
                        text: audio.base64EncodedString(),
                        timestamp: now.addingTimeInterval(-minutesAgo * 60),
                        attachmentType: .voiceNote,
                        deliveryStatus: .delivered
                    )
                }
            }
            host.textMessageService.loadDemoHistory(messages, channelID: channelID)
        }
    }

    private func seedInbox() {
        let now = Date()
        var received: [(VoiceMessageQueue.PendingMessage, URL)] = []
        for entry in DemoContent.inbox {
            guard let url = DemoContent.clipURL(entry.clip, ext: "opusframes"),
                  let frames = DemoContent.opusFrames(entry.clip) else {
                logger.error("Missing bundled voice message \(entry.clip, privacy: .public)")
                continue
            }
            let message = VoiceMessageQueue.PendingMessage(
                id: UUID(),
                senderID: entry.peer.id,
                recipientID: host?.localPeerID ?? "",
                recipientName: host?.callsign ?? "",
                timestamp: now.addingTimeInterval(-entry.minutesAgo * 60),
                durationMs: frames.count * Int(Constants.Opus.frameDuration * 1000),
                fileName: url.lastPathComponent,
                delivered: true,
                deliveredAt: now.addingTimeInterval(-entry.minutesAgo * 60),
                senderName: entry.peer.name
            )
            received.append((message, url))
        }
        VoiceMessageQueue.shared.enterDemoOverlay(received: received)
    }

    // MARK: - Presence

    /// Where the simulated people stand: around the user's own position when
    /// the app already has one, otherwise around a fixed default. Reading the
    /// location manager's cached fix never prompts and starts nothing.
    var mapAnchor: CLLocationCoordinate2D {
        if let live = host?.locationService.currentLocation?.coordinate { return live }
        if host?.locationSharing.isAuthorized == true,
           let cached = CLLocationManager().location?.coordinate {
            return cached
        }
        return DemoContent.fallbackAnchor
    }

    private func deliverBeacons() {
        guard isActive, let host else { return }
        let anchor = mapAnchor
        let now = Date()
        for peer in DemoContent.peers {
            let position = DemoContent.coordinate(of: peer, around: anchor)
            let info = MeshBeacon.BeaconInfo(
                id: peer.id,
                name: peer.name,
                channels: host.channelManager.channels
                    .filter { $0.peers.contains { $0.id == peer.id } }
                    .map(\.name),
                hopCount: 1,
                batteryLevel: peer.battery,
                timestamp: now,
                lastSeen: now,
                neighborIDs: peer.neighbors,
                latitude: position.latitude,
                longitude: position.longitude
            )
            guard let payload = host.meshBeacon.encodeBeacon(info) else { continue }
            deliver(.control, payload: payload, from: peer, channelID: "")
        }
    }

    // MARK: - Conversation: text

    /// Every text-service payload the user sends on a simulated channel comes
    /// here instead of the transport (which would drop it anyway). A message
    /// is acknowledged, then answered.
    func handleOutboundText(_ payload: Data, channelID: String) {
        guard isActive, let message = MeshTextMessage.from(payload: payload),
              message.senderID == host?.localPeerID else { return }

        let reply = DemoContent.textReplies[textReplyIndex % DemoContent.textReplies.count]
        textReplyIndex += 1

        schedule(after: .milliseconds(900)) { [weak self] in
            // The same ACK a real peer's text service sends back.
            var ack = Data(MeshTextMessage.ackMagicPrefix)
            ack.append(Data(message.id.uuidString.utf8))
            self?.deliver(.control, payload: ack, from: reply.peer, channelID: channelID)
        }
        schedule(after: .milliseconds(1800)) { [weak self] in
            var typing = Data(MeshTextMessage.typingMagicPrefix)
            typing.append(Data(reply.peer.id.utf8))
            typing.append(0x00)
            typing.append(Data(reply.peer.name.utf8))
            typing.append(0x00)
            typing.append(Data(channelID.utf8))
            self?.deliver(.control, payload: typing, from: reply.peer, channelID: channelID)
        }
        schedule(after: .milliseconds(3600)) { [weak self] in
            let answer = MeshTextMessage(
                id: UUID(),
                senderID: reply.peer.id,
                senderName: reply.peer.name,
                channelID: channelID,
                text: reply.text,
                timestamp: Date(),
                replyToID: message.id
            )
            guard let wire = try? answer.wirePayload() else { return }
            self?.deliver(.control, payload: wire, from: reply.peer, channelID: channelID)
        }
    }

    // MARK: - Conversation: push-to-talk

    /// Observes the floor. When the user lets go of the talk button, somebody
    /// answers a moment later with a bundled clip, delivered as a real floor
    /// request followed by real audio packets.
    func floorStateChanged(_ state: PTTState) {
        defer { lastFloorState = state }
        guard isActive, !pttReplyInFlight else { return }
        guard lastFloorState == .transmitting, state == .idle else { return }

        pttReplyInFlight = true
        let reply = DemoContent.pttReplies[pttReplyIndex % DemoContent.pttReplies.count]
        pttReplyIndex += 1
        schedule(after: .milliseconds(1500)) { [weak self] in
            await self?.transmit(clip: reply.clip, as: reply.peer)
        }
    }

    private func transmit(clip: String, as peer: DemoContent.Peer) async {
        defer { pttReplyInFlight = false }
        guard isActive, let host, let frames = DemoContent.opusFrames(clip) else { return }
        // Someone else already has the floor (the user pressed again): skip
        // this turn rather than talk over them.
        guard host.floorSession.state == .idle else { return }

        let claim = FloorControlMessage.floorRequest(senderID: peer.id, senderName: peer.name, timestamp: Date())
        guard let request = try? MeshCodable.encoder.encode(claim) else { return }
        deliver(.control, payload: request, from: peer, channelID: "")

        // A different speaker's stream: restart the buffer's sequence memory
        // exactly as a receiver hearing a new sender would need to.
        host.audioEngine.resetJitterBuffer()
        let channelID = host.channelManager.activeChannel?.id ?? ""
        let start = ContinuousClock.now
        for (index, frame) in frames.enumerated() {
            guard !Task.isCancelled, isActive else { return }
            audioSequence &+= 1
            let packet = AudioPacket(
                sequenceNumber: audioSequence,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                opusData: frame
            )
            deliver(.audio, payload: packet.serialize(), from: peer, channelID: channelID)
            let due = start + .milliseconds(Int(Double(index + 1) * Constants.Opus.frameDuration * 1000))
            try? await Task.sleep(until: due, clock: .continuous)
        }
        try? await Task.sleep(for: .milliseconds(Constants.JitterBuffer.initialDepthMs + 100))
        guard let release = try? MeshCodable.encoder.encode(FloorControlMessage.floorRelease(senderID: peer.id)) else { return }
        deliver(.control, payload: release, from: peer, channelID: "")
    }

    // MARK: - Delivery

    /// Hand a simulated peer's packet to the local-delivery handler — the
    /// same entry point the mesh router uses for packets off the air.
    private func deliver(_ type: MeshPacket.PacketType, payload: Data, from peer: DemoContent.Peer, channelID: String) {
        guard isActive, let host, let origin = UUID(uuidString: peer.id) else { return }
        let packet = MeshPacket(
            type: type,
            ttl: 1,
            originID: origin,
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: payload
        )
        host.deliverLocally(packet)
    }

    private func schedule(after delay: Duration, _ work: @escaping @MainActor () async -> Void) {
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await work()
        }
        pendingTasks.append(task)
        pendingTasks.removeAll { $0.isCancelled }
    }
}

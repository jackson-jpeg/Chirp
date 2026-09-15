#if DEBUG
import Foundation

/// Populates realistic on-mesh state for App Store screenshot capture.
///
/// Compiled only into DEBUG builds and activated only by the
/// `--screenshot-seed` launch argument, so none of this can run in a
/// shipped binary. Everything goes through the app's real seams: peers
/// join the active channel through ChannelManager, map pins and the
/// node list come from real BCN! payloads fed to MeshBeacon, and the
/// mid-transmit shot uses the real PTTEngine against the simulator mic.
@MainActor
enum ScreenshotSeed {

    private static var beaconTimer: Timer?

    static func applyIfRequested(to appState: AppState) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--screenshot-seed") else { return }

        // Put the capture device on the map the same way a user does — the
        // real check-in, through the real gate — so the Map shot shows the
        // live sharing indicator rather than the checked-out empty state.
        // DEBUG-only and launch-argument gated, like everything else here, so
        // it cannot change what a shipped binary does.
        appState.locationSharing.beginCheckIn()

        let channel = seedChannel(appState)
        seedPeers(appState, channelID: channel.id)
        seedMessages(appState, channelID: channel.id)
        seedVoiceMessages(appState)
        injectBeacons(appState)

        // Beacon nodes go stale after 10s, and a stray transport event can
        // reconcile the roster to "everyone disconnected" or reset the
        // peer-count override, so re-assert all of it every 5s for as long
        // as the capture session runs.
        beaconTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in
                injectBeacons(appState)
                appState.channelManager.reconcilePeers(
                    channelID: channel.id, connected: seedChirpPeers())
                appState.debugOverrideConnectedPeerCount(peers.count)
            }
        }

        if args.contains("--screenshot-transmit") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                appState.pttEngine.startTransmitting()
                try? await Task.sleep(for: .seconds(60))
                appState.pttEngine.stopTransmitting()
            }
        }
    }

    // MARK: - Cast

    private struct SeedPeer {
        let id: String
        let name: String
        let bars: Int
        let hops: UInt8
        let battery: Float
        let lat: Double
        let lon: Double
        let neighbors: [String]
    }

    // Yosemite Valley, spread over roughly a kilometer of trail.
    private static let peers: [SeedPeer] = [
        SeedPeer(id: "seed-ridge-7", name: "Ridge-7", bars: 3, hops: 1,
                 battery: 0.86, lat: 37.7492, lon: -119.5889,
                 neighbors: ["seed-nova-12", "seed-wolf-3"]),
        SeedPeer(id: "seed-nova-12", name: "Nova-12", bars: 2, hops: 1,
                 battery: 0.64, lat: 37.7421, lon: -119.5847,
                 neighbors: ["seed-ridge-7", "seed-ghost-21"]),
        SeedPeer(id: "seed-ghost-21", name: "Ghost-21", bars: 2, hops: 2,
                 battery: 0.71, lat: 37.7387, lon: -119.6012,
                 neighbors: ["seed-nova-12"]),
        SeedPeer(id: "seed-wolf-3", name: "Wolf-3", bars: 1, hops: 2,
                 battery: 0.42, lat: 37.7508, lon: -119.6041,
                 neighbors: ["seed-ridge-7"]),
    ]

    // MARK: - Channel + peers

    private static func seedChannel(_ appState: AppState) -> ChirpChannel {
        // Idempotent across the several launches of a capture session:
        // the channel list persists between runs.
        if let existing = appState.channelManager.channels.first(where: { $0.name == "Basecamp" }) {
            appState.channelManager.joinChannel(id: existing.id)
            return existing
        }
        let channel = appState.channelManager.createChannel(
            name: "Basecamp",
            accessMode: .locked,
            ownerID: appState.localPeerID
        )
        appState.channelManager.joinChannel(id: channel.id)
        return channel
    }

    private static func seedChirpPeers() -> [ChirpPeer] {
        peers.map {
            ChirpPeer(id: $0.id, name: $0.name, isConnected: true, signalStrength: $0.bars)
        }
    }

    private static func seedPeers(_ appState: AppState, channelID: String) {
        for peer in seedChirpPeers() {
            appState.channelManager.addPeerToChannel(channelID: channelID, peer: peer)
        }
        // The channel roster persists across launches with isConnected as
        // saved, and addPeerToChannel skips peers it already knows — so
        // reconcile to force every seeded peer back to connected.
        appState.channelManager.reconcilePeers(channelID: channelID, connected: seedChirpPeers())
        appState.debugOverrideConnectedPeerCount(peers.count)
    }

    // MARK: - Chat

    private static func seedMessages(_ appState: AppState, channelID: String) {
        // Force hydration first: the first messages(for:) call replaces the
        // in-memory cache from the database, which would erase anything
        // injected before it.
        _ = appState.textMessageService.messages(for: channelID)
        guard appState.textMessageService.messages(for: channelID).isEmpty else { return }

        let me = appState.localPeerID
        let myName = appState.callsign
        let now = Date()

        struct Line {
            let peer: SeedPeer?  // nil = local user
            let text: String
            let minutesAgo: Double
        }
        let script: [Line] = [
            Line(peer: peers[0], text: "We just cleared the switchbacks, no cell all day", minutesAgo: 9),
            Line(peer: nil, text: "Copy that. Mesh is holding strong", minutesAgo: 8),
            Line(peer: peers[1], text: "Creek crossing is running high, take the log bridge", minutesAgo: 6),
            Line(peer: nil, text: "Good call. Meet at the overlook in 20", minutesAgo: 5),
            Line(peer: peers[2], text: "Saving you a spot at the fire", minutesAgo: 2),
        ]

        for line in script {
            let message = MeshTextMessage(
                id: UUID(),
                senderID: line.peer?.id ?? me,
                senderName: line.peer?.name ?? myName,
                channelID: channelID,
                text: line.text,
                timestamp: now.addingTimeInterval(-line.minutesAgo * 60),
                replyToID: nil,
                attachmentType: nil,
                deliveryStatus: line.peer == nil ? .delivered : .sent
            )
            appState.textMessageService.injectDemoMessage(message)
        }
    }

    // MARK: - Voice messages

    private static func seedVoiceMessages(_ appState: AppState) {
        let queue = VoiceMessageQueue.shared
        guard queue.pendingMessages.isEmpty && queue.receivedMessages.isEmpty else { return }

        let me = appState.localPeerID
        // 20ms of silence per frame; count controls the displayed duration.
        func frames(seconds: Int) -> [Data] {
            Array(repeating: Data([0x00]), count: seconds * 50)
        }

        _ = queue.queueMessage(
            opusFrames: frames(seconds: 8),
            recipientID: peers[3].id,
            recipientName: peers[3].name,
            senderID: me
        )
        _ = queue.queueMessage(
            opusFrames: frames(seconds: 15),
            recipientID: peers[2].id,
            recipientName: peers[2].name,
            senderID: me
        )

        let now = Date()
        for (peer, seconds, minutesAgo) in [(peers[0], 12, 34.0), (peers[1], 5, 11.0)] {
            let incoming = VoiceMessageQueue.PendingMessage(
                id: UUID(),
                senderID: peer.id,
                recipientID: me,
                recipientName: appState.callsign,
                timestamp: now.addingTimeInterval(-minutesAgo * 60),
                durationMs: seconds * 1000,
                fileName: "seed-placeholder.opus"
            )
            queue.receiveMessage(incoming, audioData: Data([0x00]))
        }
    }

    // MARK: - Beacons (map pins + mesh node list)

    private static func injectBeacons(_ appState: AppState) {
        let now = Date()
        for peer in peers {
            let info = MeshBeacon.BeaconInfo(
                id: peer.id,
                name: peer.name,
                channels: ["Basecamp"],
                hopCount: peer.hops,
                batteryLevel: peer.battery,
                timestamp: now,
                lastSeen: now,
                neighborIDs: peer.neighbors,
                latitude: peer.lat,
                longitude: peer.lon
            )
            guard let payload = appState.meshBeacon.encodeBeacon(info) else { continue }
            appState.meshBeacon.handleBeacon(payload)
        }
    }
}
#endif

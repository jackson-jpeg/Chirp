import ActivityKit
import AVFAudio
import Foundation
import Observation
import OSLog
import UIKit

@Observable
@MainActor
final class AppState {

    // MARK: - Services

    let wifiAwareManager: WiFiAwareManager
    let connectionManager: ConnectionManager
    let audioEngine: AudioEngine
    let floorController: FloorController
    let pttEngine: PTTEngine
    let channelManager: ChannelManager
    let peerTracker: PeerTracker
    let liveActivityManager: LiveActivityManager
    let multipeerTransport: MultipeerTransport
    let friendsManager: FriendsManager
    let meshRouter: MeshRouter
    let meshIntelligence: MeshIntelligence
    let backgroundService: BackgroundMeshService
    let textMessageService: TextMessageService
    let locationService: LocationService
    let storeAndForwardRelay: StoreAndForwardRelay
    let meshBeacon: MeshBeacon

    // MARK: - Identity

    let localPeerID: String
    let localPeerName: String
    private(set) var peerFingerprint: String = ""

    // MARK: - Persisted State

    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "com.chirpchirp.onboardingComplete") {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    var callsign: String = UserDefaults.standard.string(forKey: "com.chirpchirp.callsign") ?? UIDevice.current.name {
        didSet { UserDefaults.standard.set(callsign, forKey: "com.chirpchirp.callsign") }
    }

    // MARK: - Permissions

    private(set) var micPermissionGranted: Bool = false

    func requestMicPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            micPermissionGranted = true
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            micPermissionGranted = granted
        case .denied:
            micPermissionGranted = false
        @unknown default:
            micPermissionGranted = false
        }
    }

    // MARK: - Forwarded State

    var pttState: PTTState { pttEngine.state }
    var inputLevel: Float { audioEngine.inputLevel }
    private(set) var connectedPeerCount: Int = 0
    private(set) var meshStats: MeshStats?

    // MARK: - Private

    private let logger = Logger.ptt

    private enum Keys {
        static let peerID = "com.chirpchirp.localPeerID"
        static let onboardingComplete = "com.chirpchirp.onboardingComplete"
        static let activeChannelID = "com.chirpchirp.activeChannelID"
        static let meshRunning = "com.chirpchirp.meshRunning"
    }

    // MARK: - Init

    init() {
        // Resolve or create a stable local peer ID.
        let storedID = UserDefaults.standard.string(forKey: Keys.peerID)
        let peerID: String
        if let storedID, !storedID.isEmpty {
            peerID = storedID
        } else {
            peerID = UUID().uuidString
            UserDefaults.standard.set(peerID, forKey: Keys.peerID)
        }
        self.localPeerID = peerID
        self.localPeerName = UIDevice.current.name

        // Create subsystems.
        let audioEngine = AudioEngine()
        let peerTracker = PeerTracker()
        let wifiAwareManager = WiFiAwareManager()
        let connectionManager = ConnectionManager()
        let floorController = FloorController(
            localPeerID: peerID,
            localPeerName: self.localPeerName
        )
        let pttEngine = PTTEngine(
            audioEngine: audioEngine,
            floorController: floorController,
            localPeerID: peerID
        )
        let channelManager = ChannelManager()

        self.audioEngine = audioEngine
        self.peerTracker = peerTracker
        self.wifiAwareManager = wifiAwareManager
        self.connectionManager = connectionManager
        self.floorController = floorController
        self.pttEngine = pttEngine
        self.channelManager = channelManager
        self.liveActivityManager = LiveActivityManager()

        self.friendsManager = FriendsManager()

        // Create mesh router using stable local peer ID as origin
        guard let originUUID = UUID(uuidString: peerID) else {
            fatalError("Local peer ID is not a valid UUID: \(peerID)")
        }
        let router = MeshRouter(localPeerID: originUUID)
        self.meshRouter = router
        self.meshIntelligence = MeshIntelligence()
        self.backgroundService = BackgroundMeshService.shared

        // Text messaging service
        let textMessageService = TextMessageService()
        self.textMessageService = textMessageService
        self.locationService = LocationService()
        self.storeAndForwardRelay = StoreAndForwardRelay()
        self.meshBeacon = MeshBeacon()

        // Create transport with mesh router injected at init
        let displayName = UserDefaults.standard.string(forKey: "com.chirpchirp.callsign") ?? UIDevice.current.name
        let transport = MultipeerTransport(displayName: displayName, meshRouter: router, localPeerID: peerID, localPeerName: self.localPeerName)
        self.multipeerTransport = transport

        // Wire multipeer to PTT engine for real peer-to-peer audio
        transport.onPeersChanged = { [weak self] peers in
            guard let self else { return }
            let oldCount = self.connectedPeerCount
            self.connectedPeerCount = peers.count

            // Update active channel peers
            if let activeID = self.channelManager.activeChannel?.id {
                for existingPeer in self.channelManager.activeChannel?.peers ?? [] {
                    self.channelManager.removePeerFromChannel(channelID: activeID, peerID: existingPeer.id)
                }
                for peer in peers {
                    self.channelManager.addPeerToChannel(channelID: activeID, peer: peer)
                }
            }

            // Update friends online status
            let onlinePeerIDs = Set(peers.map { $0.id })
            for friend in self.friendsManager.friends {
                self.friendsManager.updateOnlineStatus(
                    peerID: friend.id,
                    isOnline: onlinePeerIDs.contains(friend.id)
                )
            }

            // Check store-and-forward relay for pending messages to newly connected peers
            for peer in peers {
                let pending = self.storeAndForwardRelay.checkPendingForPeer(peer.id)
                for msg in pending {
                    try? transport.sendControlData(msg.payload, channelID: msg.channelID)
                }
            }

            // Log peer changes
            if peers.count > oldCount {
                let newPeer = peers.last
                Logger.network.info("Peer connected: \(newPeer?.name ?? "unknown") (total: \(peers.count))")
            } else if peers.count < oldCount {
                Logger.network.info("Peer disconnected (total: \(peers.count))")
            }
        }

        // Wire text message service to transport
        let txtService = self.textMessageService
        textMessageService.onSendPacket = { payload, channelID in
            try? transport.sendControlData(payload, channelID: channelID)
        }

        // Wire mesh router callbacks.
        // This is the SOLE delivery path for all incoming audio and control packets.
        let audioEng = self.audioEngine
        let floorCtrl = self.floorController
        let mpTransport = self.multipeerTransport
        let chanMgr = self.channelManager
        let peerTrk = self.peerTracker
        Task {
            await router.setCallbacks(
                onLocalDelivery: { (packet: MeshPacket) in
                    // Channel filtering: drop audio for wrong channel.
                    // Control packets with empty channelID (broadcasts) are always delivered.
                    let activeID = chanMgr.activeChannel?.id ?? ""
                    if !packet.channelID.isEmpty && packet.channelID != activeID {
                        // Wrong channel -- drop audio, but still deliver broadcast controls
                        if packet.type == .audio { return }
                    }

                    switch packet.type {
                    case .audio:
                        if let audioPacket = AudioPacket.deserialize(packet.payload) {
                            audioEng.receiveAudioPacket(audioPacket.opusData, sequenceNumber: audioPacket.sequenceNumber)
                        }
                    case .control:
                        // Try text message first (TXT! prefix)
                        txtService.handlePacket(packet.payload)

                        if let message = try? MeshCodable.decoder.decode(FloorControlMessage.self, from: packet.payload) {
                            floorCtrl.handleMessage(message)

                            // Route heartbeat and peer join/leave to PeerTracker
                            switch message {
                            case .heartbeat(let peerID, let timestamp):
                                Task { await peerTrk.handleHeartbeat(peerID: peerID, timestamp: timestamp) }
                            case .peerJoin(let peerID, let peerName):
                                Task { await peerTrk.updatePeer(id: peerID, name: peerName) }
                            case .peerLeave(let peerID):
                                Task { await peerTrk.removePeer(id: peerID) }
                            default:
                                break
                            }
                        }
                    }
                },
                onForward: { (packet: MeshPacket, excludePeer: String) in
                    let serialized = packet.serialize()
                    mpTransport.forwardPacket(serialized, excludePeer: excludePeer)
                }
            )
        }

        logger.info("AppState initialized — peerID=\(peerID), name=\(self.callsign)")
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        // Load peer fingerprint
        self.peerFingerprint = await PeerIdentity.shared.fingerprint

        // Request mic permission early
        await requestMicPermission()

        // Register for audio session interruption and route change notifications
        AudioSessionManager.registerForNotifications()

        // Wire interruption callbacks to PTTEngine for auto-release on phone calls etc.
        let ptt = self.pttEngine
        AudioSessionManager.onInterruptionBegan = {
            ptt.stopTransmitting()
        }
        AudioSessionManager.onInterruptionEnded = {
            // Session reactivated -- no auto-transmit, just log readiness
            Logger.audio.info("Audio interruption ended — PTT ready")
        }

        pttEngine.multipeerTransport = multipeerTransport
        try? await pttEngine.start()
        await peerTracker.startHealthCheck()

        // Start MultipeerConnectivity transport for local peer discovery.
        // All incoming packets are delivered via meshRouter.onLocalDelivery (wired in init).
        multipeerTransport.start()

        // Create a default channel if none exist (first launch).
        // Channels are persisted, so this only runs once.
        if channelManager.channels.isEmpty {
            let defaultChannel = channelManager.createChannel(name: "General")
            channelManager.joinChannel(id: defaultChannel.id)
        }

        // Crash recovery: rejoin previously active channel if the app was killed
        recoverActiveState()

        // Save active state for crash recovery
        saveActiveState()

        // Live Activity disabled until widget extension signing is resolved
        // if let channel = channelManager.activeChannel {
        //     liveActivityManager.startActivity(channelName: channel.name)
        // }

        // Start mesh beacon broadcasting for presence detection
        let channelIDs = channelManager.channels.map(\.id)
        meshBeacon.startBroadcasting(
            localID: localPeerID,
            localName: callsign,
            channels: channelIDs
        )

        // Request location permission for location sharing features
        locationService.requestPermission()

        // Register background tasks to keep mesh alive
        backgroundService.registerBackgroundTasks()

        // Periodically update mesh stats and prune stale intelligence data
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { break }
                self.meshStats = await self.meshRouter.stats
                await self.meshIntelligence.pruneStaleEntries()
            }
        }

        logger.info("AppState started")
    }

    /// Graceful shutdown.
    func stop() {
        clearActiveState()
        pttEngine.stop()
        liveActivityManager.endActivity()
        Task { await peerTracker.stopHealthCheck() }
        logger.info("AppState stopped")
    }

    // MARK: - State Persistence for Crash Recovery

    /// Save active channel and mesh state so we can recover after a crash or force-quit.
    private func saveActiveState() {
        let channelID = channelManager.activeChannel?.id
        UserDefaults.standard.set(channelID, forKey: Keys.activeChannelID)
        UserDefaults.standard.set(true, forKey: Keys.meshRunning)
        logger.info("Saved active state: channel=\(channelID ?? "none")")
    }

    /// Clear saved state on intentional stop.
    private func clearActiveState() {
        UserDefaults.standard.removeObject(forKey: Keys.activeChannelID)
        UserDefaults.standard.set(false, forKey: Keys.meshRunning)
        logger.info("Cleared active state")
    }

    /// Attempt to rejoin a previously active channel after crash recovery.
    private func recoverActiveState() {
        guard UserDefaults.standard.bool(forKey: Keys.meshRunning) else { return }

        if let savedChannelID = UserDefaults.standard.string(forKey: Keys.activeChannelID) {
            // Check if this channel still exists
            if channelManager.channels.contains(where: { $0.id == savedChannelID }) {
                channelManager.joinChannel(id: savedChannelID)
                logger.info("Crash recovery: rejoined channel \(savedChannelID)")
            } else {
                logger.warning("Crash recovery: saved channel \(savedChannelID) no longer exists")
                clearActiveState()
            }
        }
    }

    // MARK: - Live Activity

    /// Call this whenever PTT state or audio level changes to keep the Dynamic Island in sync.
    func updateLiveActivity() {
        let channel = channelManager.activeChannel
        liveActivityManager.updateActivity(
            state: pttState,
            channelName: channel?.name ?? "ChirpChirp",
            peerCount: channel?.activePeerCount ?? 0,
            inputLevel: Double(inputLevel)
        )
    }
}

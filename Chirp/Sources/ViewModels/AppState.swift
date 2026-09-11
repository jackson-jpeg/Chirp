import AVFAudio
import Foundation
import Observation
import OSLog
import UIKit

@Observable
@MainActor
final class AppState {

    // MARK: - Services

    let audioEngine: AudioEngine
    let floorSession: FloorSession
    let pttEngine: PTTEngine
    let channelManager: ChannelManager
    let peerTracker: PeerTracker
    let multipeerTransport: MultipeerTransport
    let friendsManager: FriendsManager
    let meshRouter: MeshRouter
    let meshIntelligence: MeshIntelligence
    let textMessageService: TextMessageService
    let locationService: LocationService
    let storeAndForwardRelay: StoreAndForwardRelay
    let meshBeacon: MeshBeacon
    let liveTranscription: LiveTranscription
    let quickReplyManager: QuickReplyManager
    let proximityAlert: ProximityAlert
    let offlineMapManager: OfflineMapManager
    let meshShield: MeshShield
    let fileTransferService: FileTransferService
    let pheromoneRouter: PheromoneRouter
    let blockList: BlockList

    // MARK: - Identity

    let localPeerID: String
    let localPeerName: String
    private(set) var peerFingerprint: String = ""

    // MARK: - Persisted State

    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "com.chirpchirp.onboardingComplete") {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    /// The user's on-mesh name. Defaults to a generated callsign, never the
    /// device name — the device name is broadcast to strangers and frequently
    /// contains the owner's real name.
    var callsign: String {
        didSet { UserDefaults.standard.set(callsign, forKey: Keys.callsign) }
    }

    // MARK: - Permissions

    private(set) var micPermissionGranted: Bool = false

    /// Alert shown when a permission is denied. Views observe this to show feedback.
    var permissionDeniedAlert: PermissionDeniedAlert?

    enum PermissionDeniedAlert: Equatable {
        case microphone
        case location
        case camera

        var title: String {
            switch self {
            case .microphone: return "Microphone Access Required"
            case .location: return "Location Access Required"
            case .camera: return "Camera Access Required"
            }
        }

        var message: String {
            switch self {
            case .microphone:
                return "Microphone access is required for push-to-talk. Open Settings to enable."
            case .location:
                return "Location access is required to share your position on the map. Open Settings to enable."
            case .camera:
                return "Camera access is required for photo sharing. Open Settings to enable."
            }
        }
    }

    func requestMicPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            micPermissionGranted = true
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            micPermissionGranted = granted
            if !granted {
                permissionDeniedAlert = .microphone
            }
        case .denied:
            micPermissionGranted = false
            permissionDeniedAlert = .microphone
        @unknown default:
            micPermissionGranted = false
        }
    }

    /// Called when location authorization changes to a denied state.
    func handleLocationPermissionDenied() {
        permissionDeniedAlert = .location
    }

    /// Opens the app's Settings page so the user can re-enable permissions.
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Forwarded State

    var pttState: PTTState { pttEngine.state }
    var inputLevel: Float { audioEngine.inputLevel }
    /// Current Opus encoder bitrate in bits per second.
    var currentBitrate: Int { audioEngine.currentBitrate }
    private(set) var connectedPeerCount: Int = 0
    private(set) var meshStats: MeshStats?

    // MARK: - Private

    private let logger = Logger.ptt
    private var notificationObservers: [Any] = []

    private enum Keys {
        static let peerID = "com.chirpchirp.localPeerID"
        static let onboardingComplete = "com.chirpchirp.onboardingComplete"
        static let activeChannelID = "com.chirpchirp.activeChannelID"
        static let meshRunning = "com.chirpchirp.meshRunning"
        static let callsign = "com.chirpchirp.callsign"
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

        // Resolve or generate the callsign. Generated once and persisted so the
        // name is stable across launches.
        let resolvedCallsign: String
        if let stored = UserDefaults.standard.string(forKey: Keys.callsign), !stored.isEmpty {
            resolvedCallsign = stored
        } else {
            resolvedCallsign = CallsignGenerator.generate()
            UserDefaults.standard.set(resolvedCallsign, forKey: Keys.callsign)
        }
        self.callsign = resolvedCallsign
        self.localPeerName = resolvedCallsign

        // Create subsystems.
        let audioEngine = AudioEngine()
        let peerTracker = PeerTracker()
        let floorSession = FloorSession(
            localPeerID: peerID,
            localPeerName: resolvedCallsign
        )
        let pttEngine = PTTEngine(
            audioEngine: audioEngine,
            floorSession: floorSession,
            localPeerID: peerID
        )
        let channelManager = ChannelManager()

        self.audioEngine = audioEngine
        self.peerTracker = peerTracker
        self.floorSession = floorSession
        self.pttEngine = pttEngine
        self.channelManager = channelManager

        self.friendsManager = FriendsManager()

        // Create mesh router using stable local peer ID as origin
        let originUUID: UUID
        if let parsed = UUID(uuidString: peerID) {
            originUUID = parsed
        } else {
            // Peer ID was corrupted — generate a fresh one and persist it.
            let freshUUID = UUID()
            UserDefaults.standard.set(freshUUID.uuidString, forKey: Keys.peerID)
            originUUID = freshUUID
            Logger.ptt.error("Local peer ID was not a valid UUID — regenerated: \(freshUUID.uuidString)")
        }
        let router = MeshRouter(localPeerID: originUUID)
        self.meshRouter = router
        self.meshIntelligence = MeshIntelligence()

        // Text messaging service
        let textMessageService = TextMessageService()
        self.textMessageService = textMessageService

        // Block list store (wired to router + text service below).
        let blockList = BlockList()
        self.blockList = blockList

        // File transfer service
        let fileTransferService = FileTransferService()
        self.fileTransferService = fileTransferService

        self.locationService = LocationService()
        self.storeAndForwardRelay = StoreAndForwardRelay()
        self.meshBeacon = MeshBeacon()
        self.liveTranscription = LiveTranscription()
        self.quickReplyManager = QuickReplyManager()
        self.proximityAlert = ProximityAlert()
        self.offlineMapManager = OfflineMapManager()
        self.meshShield = MeshShield()

        // Pheromone routing overlay -- bio-inspired ACK backpropagation and relay optimization
        let pheromoneRouter = PheromoneRouter()
        pheromoneRouter.configure(
            meshIntelligence: self.meshIntelligence,
            localPeerID: peerID,
            localPeerName: resolvedCallsign
        )
        self.pheromoneRouter = pheromoneRouter

        // Wire pheromone router into mesh beacon for trail sharing
        self.meshBeacon.pheromoneRouter = pheromoneRouter

        // Create MultipeerConnectivity transport
        let transport = MultipeerTransport(displayName: resolvedCallsign, meshRouter: router, localPeerID: peerID, localPeerName: resolvedCallsign)
        self.multipeerTransport = transport

        transport.onPeersChanged = { [weak self] _ in self?.updateUnifiedPeerList() }

        // Wire peer ghost detection — auto-prune peers with no heartbeat for >45s.
        // Also tell the floor: a ghosted speaker must not hold it forever.
        Task {
            await peerTracker.setGhostCallback { [weak self] peerID in
                Task { @MainActor in
                    guard let self else { return }
                    self.floorSession.peerLost(peerID)
                    self.updateUnifiedPeerList()
                    Logger.ptt.info("Peer ghosted and pruned: \(peerID)")
                }
            }
        }

        // Wire pheromone router send callback
        pheromoneRouter.onSendPacket = { payload, channelID in
            do {
                try transport.sendControlData(payload, channelID: channelID)
            } catch {
                Logger.network.error("Pheromone ACK send failed: \(error.localizedDescription)")
            }
        }

        // Block list: enforced at the router (drop packets by origin ID)
        // and in the text service (drop + hide history by sender ID).
        blockList.onChange = { blockedIDs in
            Task { await router.setBlockedOrigins(blockedIDs) }
        }
        let initialBlockedIDs = blockList.blockedIDs
        Task { await router.setBlockedOrigins(initialBlockedIDs) }
        textMessageService.blockedPeerIDsProvider = { [weak blockList] in
            blockList?.blockedIDs ?? []
        }

        // Wire encryption provider for text messages on locked channels
        textMessageService.channelCryptoProvider = { [weak self] channelID in
            self?.channelManager.getChannelCrypto(for: channelID)
        }

        // Wire key rotation epoch providers
        textMessageService.epochProvider = { [weak self] channelID in
            self?.channelManager.recordMessageAndGetEpoch(for: channelID) ?? 0
        }
        textMessageService.currentEpochProvider = { [weak self] channelID in
            self?.channelManager.currentEpoch(for: channelID) ?? 0
        }

        // Wire key rotation broadcast — send KRO! packets when epoch advances
        channelManager.onKeyRotation = { payload, channelID in
            do {
                try transport.sendControlData(payload, channelID: channelID)
            } catch {
                Logger.network.error("Key rotation broadcast failed: \(error.localizedDescription)")
            }
        }

        // Wire channel crypto into MeshShield so cover traffic is encrypted with channel key
        meshShield.channelCryptoProvider = { [weak self] channelID in
            self?.channelManager.getChannelCrypto(for: channelID)
        }
        meshShield.activeChannelProvider = { [weak self] in
            self?.channelManager.activeChannel?.id
        }
        meshShield.peerCountProvider = { [weak self] in
            self?.channelManager.activeChannel?.peers.count ?? 0
        }

        // Wire encryption provider for file transfers on locked channels
        fileTransferService.channelCryptoProvider = { [weak self] channelID in
            self?.channelManager.getChannelCrypto(for: channelID)
        }

        // Wire text message service sends, with store-and-forward for offline peers
        // Send policy lives in MeshDelivery.makeTextSendHandler so the test
        // suite runs the production policy — see that function for why the
        // live send is gated on the transport, never the channel roster.
        textMessageService.onSendPacket = MeshDelivery.makeTextSendHandler(
            sendControl: { try transport.sendControlData($0, channelID: $1) },
            transportPeers: { [weak self] in self?.multipeerTransport.peers ?? [] },
            channelLookup: { [weak self] channelID in
                self?.channelManager.channel(withID: channelID)
                    ?? self?.channelManager.activeChannel
            },
            localPeerName: { [weak self] in self?.localPeerName },
            enqueue: { [weak self] pending in
                self?.storeAndForwardRelay.store(message: pending)
            }
        )

        // Wire file transfer service sends
        fileTransferService.onSendPacket = { payload, channelID in
            do {
                try transport.sendControlData(payload, channelID: channelID)
            } catch {
                Logger.network.error("File transfer send failed: \(error.localizedDescription)")
            }
        }

        // Wire decoded PCM audio to live transcription
        let transcription = self.liveTranscription
        audioEngine.onDecodedPCM = { buffer in
            transcription.feedAudioBuffer(buffer)
        }

        // Wire floor state changes to start/stop transcription
        floorSession.onStateChange = { newState in
            switch newState {
            case .receiving(let speakerName, _):
                transcription.startTranscribing(speakerName: speakerName)
            default:
                if transcription.isTranscribing {
                    transcription.stopTranscribing()
                }
            }
        }

        // Wire mesh router callbacks.
        // This is the SOLE delivery path for all incoming audio and control packets.
        // The handler body lives in MeshDelivery so the loopback test suite runs
        // the identical dispatch code — see MeshDelivery.makeLocalDeliveryHandler.
        let mpTransport = self.multipeerTransport
        let deliveryHandler = MeshDelivery.makeLocalDeliveryHandler(
            audioEngine: audioEngine,
            floorSession: floorSession,
            channelManager: channelManager,
            peerTracker: peerTracker,
            textMessageService: textMessageService,
            fileTransferService: fileTransferService,
            meshBeacon: meshBeacon,
            pheromoneRouter: pheromoneRouter,
            notifyMessage: { senderName, text, channelName in
                NotificationService.shared.showMessageNotification(
                    from: senderName,
                    text: text,
                    channelName: channelName
                )
            }
        )
        Task {
            await router.setCallbacks(
                onLocalDelivery: deliveryHandler,
                onForward: { (packet: MeshPacket, excludePeer: String) in
                    mpTransport.forwardPacket(packet.serialize(), excludePeer: excludePeer)
                }
            )
        }

        logger.info("AppState initialized — peerID=\(peerID), name=\(resolvedCallsign)")
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        // Initialize encrypted message database before any packets arrive
        textMessageService.setupDatabase()

        // Load peer fingerprint
        self.peerFingerprint = await PeerIdentity.shared.fingerprint

        // Request mic permission early (but not during onboarding — handled there)
        if isOnboardingComplete {
            await requestMicPermission()
        }

        // Register for audio session interruption and route change notifications
        AudioSessionManager.registerForNotifications()

        // Audio session interruption and route-change callbacks are wired
        // inside PTTEngine.setupCallbacks() (called from pttEngine.start()).

        pttEngine.multipeerTransport = multipeerTransport
        pttEngine.peerListProvider = { [weak self] in
            self?.channelManager.activeChannel?.peers ?? []
        }
        do {
            try await pttEngine.start()
        } catch {
            logger.error("PTT engine failed to start: \(error.localizedDescription)")
        }
        await peerTracker.startHealthCheck()

        // Start the transport — all incoming packets delivered via meshRouter.onLocalDelivery.
        multipeerTransport.start()

        // Start cover traffic
        meshShield.start(transport: multipeerTransport)

        // Create a default channel if none exist (first launch).
        // Uses a well-known ID so all devices share the same "General" channel.
        if channelManager.channels.isEmpty {
            let defaultChannel = channelManager.createChannel(
                name: "General",
                id: ChannelManager.defaultGeneralChannelID
            )
            channelManager.joinChannel(id: defaultChannel.id)
        }

        // Crash recovery: rejoin previously active channel if the app was killed
        recoverActiveState()

        // Save active state for crash recovery
        saveActiveState()

        // Start mesh beacon broadcasting for presence detection
        let channelIDs = channelManager.channels.map(\.id)
        meshBeacon.startBroadcasting(
            localID: localPeerID,
            localName: callsign,
            channels: channelIDs
        )

        // Request permissions only after onboarding (onboarding handles mic separately)
        if isOnboardingComplete {
            NotificationService.shared.requestPermission()
            locationService.onPermissionDenied = { [weak self] in
                self?.handleLocationPermissionDenied()
            }
            locationService.requestPermission()
            locationService.startUpdating()
        }

        // Subscribe to mesh topology updates from beacons to feed MeshIntelligence
        let intelligence = self.meshIntelligence
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshTopologyUpdate, object: nil, queue: .main
        ) { notification in
            guard let peerID = notification.userInfo?["peerID"] as? String,
                  let neighbors = notification.userInfo?["neighborIDs"] as? [String] else { return }
            Task {
                await intelligence.updateTopology(peerID: peerID, connectedTo: Set(neighbors))
            }
        })

        // Subscribe to pheromone trail updates from beacons to merge into MeshIntelligence
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshPheromoneUpdate, object: nil, queue: .main
        ) { notification in
            guard let neighborID = notification.userInfo?["neighborID"] as? String,
                  let trails = notification.userInfo?["trails"] as? [String: Double] else { return }
            Task {
                await intelligence.mergePheromones(from: neighborID, trails: trails)
            }
        })

        // Route mesh beacon broadcasts through the mesh transport. The
        // packet is created by the router so it carries a real monotonic
        // sequence number — a beacon with a constant sequence poisons the
        // origin's replay high-water mark on every receiver.
        let mpTransportForBeacon = self.multipeerTransport
        let meshRouterForBeacon = self.meshRouter
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshBeaconBroadcast, object: nil, queue: .main
        ) { notification in
            guard let payload = notification.userInfo?["payload"] as? Data else { return }
            Task {
                let packet = await meshRouterForBeacon.createPacket(
                    type: .control,
                    payload: payload,
                    channelID: ""
                )
                mpTransportForBeacon.forwardPacket(packet.serialize(), excludePeer: "")
            }
        })

        // Periodically update mesh stats and prune stale intelligence data
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { break }
                self.meshStats = await self.meshRouter.stats
                await self.meshIntelligence.updateVisiblePeerCount(self.meshBeacon.directPeers.count)
                await self.meshIntelligence.pruneStaleEntries()
            }
        }

        logger.info("AppState started")
    }

    /// Graceful shutdown.
    func stop() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        clearActiveState()
        pttEngine.stop()
        meshShield.stop()
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

    // MARK: - Peer List

    /// Refresh the peer list from the transport and propagate changes.
    private func updateUnifiedPeerList() {
        var allPeers = multipeerTransport.peers
        for index in allPeers.indices {
            allPeers[index].transportType = .multipeer
        }

        let oldCount = connectedPeerCount
        connectedPeerCount = allPeers.count

        // Play sound/haptic for peer join or leave
        if allPeers.count > oldCount {
            HapticsManager.shared.peerConnected()
            SoundEffects.shared.playPeerJoined()
        } else if allPeers.count < oldCount && oldCount > 0 {
            HapticsManager.shared.peerDisconnected()
            SoundEffects.shared.playPeerLeft()
        }

        // Update active channel peers. Known members are kept and marked
        // disconnected rather than removed: store-and-forward decides who
        // gets a queued copy from the roster, and remove-then-readd erased
        // that memory the moment a peer dropped off the mesh.
        if let activeID = channelManager.activeChannel?.id {
            channelManager.reconcilePeers(channelID: activeID, connected: allPeers)
        }

        // Update friends online status
        let onlinePeerIDs = Set(allPeers.map { $0.id })
        for friend in friendsManager.friends {
            friendsManager.updateOnlineStatus(
                peerID: friend.id,
                isOnline: onlinePeerIDs.contains(friend.id)
            )
        }

        // Check proximity alerts for friends coming into range
        proximityAlert.checkProximity(onlinePeers: allPeers, friends: friendsManager.friends)

        // Check store-and-forward relay for pending messages to newly connected peers
        let mpTransport = multipeerTransport
        for peer in allPeers {
            let pending = storeAndForwardRelay.checkPendingForPeer(peer.id)
            for msg in pending {
                do {
                    try mpTransport.sendControlData(msg.payload, channelID: msg.channelID)
                } catch {
                    Logger.network.error("Store-and-forward replay failed for peer \(peer.id): \(error.localizedDescription)")
                }
            }
        }

        // Log peer changes
        if allPeers.count > oldCount {
            Logger.network.info("Peer connected (total: \(allPeers.count))")
        } else if allPeers.count < oldCount {
            Logger.network.info("Peer disconnected (total: \(allPeers.count))")
        }
    }

    #if DEBUG
    /// Screenshot seeding only (see ScreenshotSeed.swift). The peer-count
    /// badge reads this private(set) property, which is otherwise fed by
    /// transport events that can't fire in a simulator without radios.
    func debugOverrideConnectedPeerCount(_ count: Int) {
        connectedPeerCount = count
    }
    #endif
}

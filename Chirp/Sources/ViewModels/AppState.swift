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
    /// Owns the manual check-in state and gates every location emission.
    let locationSharing: LocationSharing
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
    /// Single-device tour with simulated peers. See DemoMode.swift.
    let demoMode: DemoMode
    /// Paced playback of stored voice clips (Voice Messages).
    let voiceClipPlayer: VoiceClipPlayer

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

    /// Microphone permission as last read from the system.
    ///
    /// Denial is shown where it matters, as an inline notice with an Open
    /// Settings button on the screens that need the microphone. There is
    /// deliberately no alert: the app keeps working without the microphone,
    /// and an alert on every launch or foreground would be a nag.
    enum MicPermission: Equatable {
        case undetermined, granted, denied
    }

    private(set) var micPermission: MicPermission = .undetermined

    var micPermissionGranted: Bool { micPermission == .granted }

    /// Read the current state without asking. Safe on every foreground.
    func refreshMicPermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micPermission = .granted
        case .denied: micPermission = .denied
        case .undetermined: micPermission = .undetermined
        @unknown default: micPermission = .denied
        }
    }

    /// Show the system microphone prompt if it has never been answered.
    /// Callers: the final onboarding "Continue", and the talk button when the
    /// prompt was never shown. Returns whichever way the user answered; the
    /// app carries on either way.
    @discardableResult
    func requestMicPermission() async -> Bool {
        refreshMicPermission()
        if micPermission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            micPermission = granted ? .granted : .denied
        }
        return micPermissionGranted
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
    /// Everyone this device can talk to right now: transport peers, or the
    /// simulated ones while Demo Mode is on.
    private(set) var nearbyPeers: [ChirpPeer] = []
    private(set) var meshStats: MeshStats?

    /// The router's local-delivery handler. Kept so Demo Mode can hand its
    /// simulated peers' packets to exactly the code real packets go through.
    private var localDelivery: (@Sendable (MeshPacket) -> Void)?

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

    /// - Parameters:
    ///   - radio: test seam — stands in for the MCSession the transport sends through.
    ///   - demoDefaults: where the Demo Mode flag is persisted; tests pass a scratch suite.
    init(radio: MeshRadio? = nil, demoDefaults: UserDefaults = .standard) {
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

        let locationService = LocationService()
        self.locationService = locationService
        self.locationSharing = LocationSharing(locationService: locationService)
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
        let transport = MultipeerTransport(
            displayName: resolvedCallsign,
            meshRouter: router,
            localPeerID: peerID,
            localPeerName: resolvedCallsign,
            radio: radio
        )
        self.multipeerTransport = transport

        let demoMode = DemoMode(defaults: demoDefaults)
        self.demoMode = demoMode
        self.voiceClipPlayer = VoiceClipPlayer(audioEngine: audioEngine)

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
        // ...and at the beacon, so a blocked peer's position never becomes a
        // map pin even if their packet somehow reaches local delivery.
        self.meshBeacon.blockedIDsProvider = { [weak blockList] in
            blockList?.blockedIDs ?? []
        }

        // The single gate: the beacon asks the check-in controller for a
        // coordinate and has no other way to obtain one.
        let sharing = self.locationSharing
        self.meshBeacon.locationProvider = { [weak sharing] in
            sharing?.coordinateForBroadcast()
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
        let meshTextSend = MeshDelivery.makeTextSendHandler(
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
        // Simulated channels are answered by Demo Mode, never the mesh. The
        // transport would refuse these packets anyway (see MultipeerTransport
        // .emit); routing them here is what lets the simulated peer reply.
        textMessageService.onSendPacket = { [weak demoMode] payload, channelID in
            if DemoMode.isDemoChannel(channelID) {
                demoMode?.handleOutboundText(payload, channelID: channelID)
            } else {
                meshTextSend(payload, channelID)
            }
        }

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
        floorSession.onStateChange = { [weak demoMode] newState in
            demoMode?.floorStateChanged(newState)
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
        self.localDelivery = deliveryHandler
        Task {
            await router.setCallbacks(
                onLocalDelivery: deliveryHandler,
                onForward: { (packet: MeshPacket, excludePeer: String) in
                    mpTransport.forwardPacket(packet.serialize(), excludePeer: excludePeer)
                }
            )
        }

        demoMode.host = self

        logger.info("AppState initialized — peerID=\(peerID), name=\(resolvedCallsign)")
    }

    /// Hand a packet to the local-delivery handler as if the router had just
    /// accepted it off the air. Demo Mode only.
    func deliverLocally(_ packet: MeshPacket) {
        localDelivery?(packet)
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        // Initialize encrypted message database before any packets arrive
        textMessageService.setupDatabase()

        // Load peer fingerprint
        self.peerFingerprint = await PeerIdentity.shared.fingerprint

        // Read, never request: the microphone prompt belongs to the final
        // onboarding step (or the talk button if it was never answered).
        refreshMicPermission()

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

        // A relaunch in Demo Mode must not open the radio, not even for the
        // moment before the simulated world is rebuilt below.
        if demoMode.isEnabled {
            multipeerTransport.setSandboxed(true)
        }

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

        // Demo Mode persists across launches so a relaunch does not wipe it.
        demoMode.restoreIfEnabled()

        // Start mesh beacon broadcasting for presence detection
        let channelIDs = channelManager.channels.map(\.id)
        meshBeacon.startBroadcasting(
            localID: localPeerID,
            localName: callsign,
            channels: channelIDs
        )

        // Request permissions only after onboarding (onboarding handles mic separately).
        //
        // Location is deliberately NOT requested here. Launch is not consent:
        // the system prompt appears only after the user opens the check-in
        // sheet, reads what sharing means, and taps Continue. Nothing starts
        // the location manager until they then tap Check In.
        if isOnboardingComplete {
            NotificationService.shared.requestPermission()
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

    /// Recompute the peer list, e.g. after Demo Mode switches on or off.
    func refreshPeers() {
        updateUnifiedPeerList()
    }

    /// Refresh the peer list from the transport and propagate changes.
    private func updateUnifiedPeerList() {
        var allPeers = demoMode.isActive ? demoMode.peers : multipeerTransport.peers
        for index in allPeers.indices {
            allPeers[index].transportType = .multipeer
        }
        nearbyPeers = allPeers

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

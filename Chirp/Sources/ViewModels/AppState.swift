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
    let wifiAwareTransport: WiFiAwareTransport?
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
    let liveTranscription: LiveTranscription
    let quickReplyManager: QuickReplyManager
    let proximityAlert: ProximityAlert
    let offlineMapManager: OfflineMapManager
    let meshShield: MeshShield
    let fileTransferService: FileTransferService
    let bleScanner: BLEScanner
    let privacyShield: PrivacyShield
    let soundAlertService: SoundAlertService
    let pheromoneRouter: PheromoneRouter
    let meshCloudService: MeshCloudService
    let cicadaService: CICADAService
    let uwbService: UWBService
    let deadReckoningService: DeadReckoningService
    let positioningEngine: PositioningEngine
    let lighthouseService: LighthouseService
    let meshWitnessService: MeshWitnessService
    let deadDropService: DeadDropService
    let darkroomService: DarkroomService
    let babelService: BabelService
    let swarmService: SwarmService
    let chorusService: ChorusService
    let meshGateway: MeshGateway

    // MARK: - Link Quality

    var wifiAwareLinkMetrics: [String: WALinkMetrics] {
        wifiAwareTransport?.linkMetrics ?? [:]
    }

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
                return "Location access is required for GPS sharing and SOS beacons."
            case .camera:
                return "Camera access is required for photo sharing."
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
    /// Current Opus encoder bitrate in bits per second (adaptive based on WiFi Aware link quality).
    var currentBitrate: Int { audioEngine.currentBitrate }
    private(set) var connectedPeerCount: Int = 0
    private(set) var meshStats: MeshStats?

    /// For demo/screenshot mode only.
    func setDemoPeerCount(_ count: Int) { connectedPeerCount = count }

    // MARK: - Private

    private let logger = Logger.ptt
    private var bitrateAdaptationTask: Task<Void, Never>?
    private var notificationObservers: [Any] = []

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
        self.floorController = floorController
        self.pttEngine = pttEngine
        self.channelManager = channelManager
        self.liveActivityManager = LiveActivityManager()

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
        self.backgroundService = BackgroundMeshService.shared

        // Text messaging service
        let textMessageService = TextMessageService()
        self.textMessageService = textMessageService

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

        // BLE room scanner
        let bleScanner = BLEScanner()
        self.bleScanner = bleScanner

        // Privacy analysis (local only — no mesh wiring needed)
        self.privacyShield = PrivacyShield(bleScanner: bleScanner)

        // Sound alert service for emergency sound detection
        let soundAlertService = SoundAlertService(locationService: self.locationService)
        soundAlertService.configure(senderID: peerID, senderName: self.localPeerName)
        self.soundAlertService = soundAlertService

        // Pheromone routing overlay -- bio-inspired ACK backpropagation and relay optimization
        let pheromoneRouter = PheromoneRouter()
        pheromoneRouter.configure(
            meshIntelligence: self.meshIntelligence,
            localPeerID: peerID,
            localPeerName: self.localPeerName
        )
        self.pheromoneRouter = pheromoneRouter

        // Wire pheromone router into mesh beacon for trail sharing
        self.meshBeacon.pheromoneRouter = pheromoneRouter

        // Mesh Cloud — distributed encrypted backup
        // Fingerprint loaded asynchronously later in start(), use placeholder for now
        let meshCloudService = MeshCloudService(localPeerID: peerID, localFingerprint: "")
        self.meshCloudService = meshCloudService

        // CICADA steganography
        let cicadaService = CICADAService()
        self.cicadaService = cicadaService

        // V3 Positioning
        let uwbService = UWBService(localPeerID: peerID)
        self.uwbService = uwbService

        let deadReckoningService = DeadReckoningService()
        self.deadReckoningService = deadReckoningService

        let positioningEngine = PositioningEngine()
        self.positioningEngine = positioningEngine

        let lighthouseService: LighthouseService
        if let lighthouseDB = try? LighthouseDatabase() {
            lighthouseService = LighthouseService(database: lighthouseDB)
        } else {
            // Database init failed (e.g. disk full) — create with a fresh retry.
            // If still fails, create a no-database instance so the app can still launch.
            Logger.ptt.error("Failed to initialize LighthouseDatabase — retrying once")
            if let retryDB = try? LighthouseDatabase() {
                lighthouseService = LighthouseService(database: retryDB)
            } else {
                Logger.ptt.error("LighthouseDatabase retry failed — positioning features will be unavailable")
                lighthouseService = LighthouseService()
            }
        }
        self.lighthouseService = lighthouseService

        // V3 Crypto
        let meshWitnessService = MeshWitnessService()
        self.meshWitnessService = meshWitnessService
        meshWitnessService.locationService = self.locationService

        let deadDropService = DeadDropService()
        self.deadDropService = deadDropService
        deadDropService.locationService = self.locationService

        let darkroomService = DarkroomService()
        self.darkroomService = darkroomService

        // V3 Compute
        let babelService = BabelService()
        self.babelService = babelService

        let swarmService = SwarmService(localPeerID: peerID)
        self.swarmService = swarmService

        let chorusService = ChorusService(localPeerID: peerID)
        self.chorusService = chorusService

        let meshGateway = MeshGateway.shared
        meshGateway.configure(peerID: peerID, peerName: self.localPeerName)
        self.meshGateway = meshGateway

        // Create MultipeerConnectivity transport (works on any iPhone, zero friction)
        let displayName = UserDefaults.standard.string(forKey: "com.chirpchirp.callsign") ?? UIDevice.current.name
        let transport = MultipeerTransport(displayName: displayName, meshRouter: router, localPeerID: peerID, localPeerName: self.localPeerName)
        self.multipeerTransport = transport

        // Create Wi-Fi Aware transport (long range, paired devices, iPhone 12+)
        let waCandidate = WiFiAwareTransport(meshRouter: router, localPeerID: peerID, localPeerName: self.localPeerName)
        let waTransport: WiFiAwareTransport? = waCandidate.isSupported ? waCandidate : nil
        self.wifiAwareTransport = waTransport

        // Unified peer list: merge peers from both transports, dedup by ID.
        // Both transports call this when their peer lists change.
        transport.onPeersChanged = { [weak self] _ in self?.updateUnifiedPeerList() }
        waTransport?.onPeersChanged = { [weak self] _ in self?.updateUnifiedPeerList() }

        // Wire CICADA key derivation (after all properties initialized)
        cicadaService.channelCryptoProvider = { [weak self] channelID in
            self?.channelManager.getChannelCrypto(for: channelID)
        }

        // Wire pheromone router send callback -- ACKs go out on both transports
        pheromoneRouter.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        // Wire encryption provider for text messages on locked channels
        textMessageService.channelCryptoProvider = { [weak self] channelID in
            self?.channelManager.getChannelCrypto(for: channelID)
        }

        // Wire triple-layer encryption into text messaging
        textMessageService.meshShield = self.meshShield

        // Wire key rotation epoch providers
        textMessageService.epochProvider = { [weak self] channelID in
            self?.channelManager.recordMessageAndGetEpoch(for: channelID) ?? 0
        }
        textMessageService.currentEpochProvider = { [weak self] channelID in
            self?.channelManager.currentEpoch(for: channelID) ?? 0
        }

        // Wire key rotation broadcast — send KRO! packets when epoch advances
        channelManager.onKeyRotation = { payload, channelID in
            try? transport.sendControlData(payload, channelID: channelID)
            try? waTransport?.sendControlData(payload, channelID: channelID)
        }

        // Wire CICADA steganography into text messaging
        textMessageService.cicadaService = cicadaService

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

        // Wire text message service — quality-aware transport (control = send on both for reliability)
        textMessageService.onSendPacket = { [weak self] payload, channelID in
            let channel = self?.channelManager.channel(withID: channelID)
                ?? self?.channelManager.activeChannel
            let peers = channel?.peers ?? []
            let connectedPeers = peers.filter(\.isConnected)
            let metrics = waTransport?.linkMetrics
            let choice = TransportPreference.preferredTransport(
                for: .control,
                wifiAwareMetrics: metrics,
                peers: peers
            )

            if !connectedPeers.isEmpty {
                // Peers are online — send normally via transports
                if TransportPreference.shouldSendOnMC(choice: choice) {
                    try? transport.sendControlData(payload, channelID: channelID)
                }
                if TransportPreference.shouldSendOnWA(choice: choice) {
                    try? waTransport?.sendControlData(payload, channelID: channelID)
                }
            }

            // Store-and-forward: queue for any known peers that are currently offline
            let offlinePeers = peers.filter { !$0.isConnected }
            if let relay = self?.storeAndForwardRelay,
               let senderName = self?.localPeerName {
                for peer in offlinePeers {
                    let pending = StoreAndForwardRelay.PendingMessage(
                        id: UUID(),
                        recipientPeerID: peer.id,
                        payload: payload,
                        channelID: channelID,
                        senderName: senderName,
                        timestamp: Date()
                    )
                    relay.store(message: pending)
                }
            }
        }

        // Wire BLE scanner — same transport pattern as text messages
        bleScanner.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        // Wire file transfer service — quality-aware transport (bulk data = prefer highest throughput)
        fileTransferService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            let metrics = waTransport?.linkMetrics
            let choice = TransportPreference.preferredTransport(
                for: .bulkData,
                wifiAwareMetrics: metrics,
                peers: peers
            )
            if TransportPreference.shouldSendOnMC(choice: choice) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(choice: choice) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        // Wire V3 services -- same dual-transport send pattern
        uwbService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        lighthouseService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        meshWitnessService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        deadDropService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        darkroomService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        babelService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        swarmService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        chorusService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        // Wire UWB measurement callback
        uwbService.onMeasurement = { measurement in
            Task {
                await positioningEngine.updateUWB(measurement: measurement, remotePeerPosition: nil)
            }
        }

        // Wire raw audio buffer to sound alert service for emergency sound detection + BABEL
        audioEngine.onRawAudioBuffer = { [weak soundAlertService, weak babelService] buffer, time in
            soundAlertService?.feedAudio(buffer: buffer, time: time)
            // AVAudioPCMBuffer is not Sendable but is only read (not mutated) by
            // feedLocalAudio, so this cross-isolation transfer is safe.
            nonisolated(unsafe) let unsafeBuffer = buffer
            Task { @MainActor in
                babelService?.feedLocalAudio(buffer: unsafeBuffer)
            }
        }

        // Wire sound alert broadcast — same transport pattern as text messages
        soundAlertService.onAlertBroadcast = { [weak self] payload in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: "")
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: "")
            }
        }

        // Wire mesh cloud service — backup chunks and retrieval requests broadcast on both transports
        meshCloudService.onSendPacket = { [weak self] payload, channelID in
            let peers = self?.channelManager.activeChannel?.peers ?? []
            if TransportPreference.shouldSendOnMC(peers: peers) {
                try? transport.sendControlData(payload, channelID: channelID)
            }
            if TransportPreference.shouldSendOnWA(peers: peers) {
                try? waTransport?.sendControlData(payload, channelID: channelID)
            }
        }

        // Wire decoded PCM audio to live transcription
        let transcription = self.liveTranscription
        audioEngine.onDecodedPCM = { buffer in
            transcription.feedAudioBuffer(buffer)
        }

        // Wire floor state changes to start/stop transcription
        floorController.onStateChange = { newState in
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
        // All delivery is dispatched to @MainActor for safe access to @MainActor-isolated
        // services (ChannelManager, FloorController, TextMessageService).
        // Audio playback remains low-latency because AudioEngine.receiveAudioPacket
        // schedules buffers on the player node internally.
        let audioEng = self.audioEngine
        let floorCtrl = self.floorController
        let mpTransport = self.multipeerTransport
        let waTransportRef = self.wifiAwareTransport
        let chanMgr = self.channelManager
        let peerTrk = self.peerTracker
        let txtService = self.textMessageService
        let fileService = self.fileTransferService
        let bleScan = self.bleScanner
        let sndAlertService = self.soundAlertService
        let pheroRouter = self.pheromoneRouter
        let cloudService = self.meshCloudService
        let uwbSvc = self.uwbService
        let lighthouseSvc = self.lighthouseService
        let witnessService = self.meshWitnessService
        let deadDropSvc = self.deadDropService
        let darkroomSvc = self.darkroomService
        let babelSvc = self.babelService
        let swarmSvc = self.swarmService
        let chorusSvc = self.chorusService
        let gatewaySvc = self.meshGateway
        Task {
            await router.setCallbacks(
                onLocalDelivery: { (packet: MeshPacket) in
                    Task { @MainActor in
                        // Channel filtering: drop audio for wrong channel.
                        // Control packets with empty channelID (broadcasts) are always delivered.
                        let activeID = chanMgr.activeChannel?.id ?? ""
                        if !packet.channelID.isEmpty && packet.channelID != activeID {
                            // Wrong channel -- drop audio, but still deliver broadcast controls
                            if packet.type == .audio { return }
                        }

                        // Silently discard cover traffic
                        // inside the payload. These are only recognisable after local decryption.
                        if MeshShield.isCoverTraffic(packet.payload) {
                            return
                        }

                        switch packet.type {
                        case .audio:
                            if let audioPacket = AudioPacket.deserialize(packet.payload) {
                                audioEng.receiveAudioPacket(audioPacket.opusData, sequenceNumber: audioPacket.sequenceNumber)
                            }
                        case .control:
                            // Extract 4-byte magic prefix for O(1) dispatch
                            let payload = packet.payload
                            let prefixStr: String
                            if payload.count >= 4 {
                                prefixStr = String(data: payload.prefix(4), encoding: .ascii) ?? ""
                            } else {
                                prefixStr = ""
                            }

                            switch prefixStr {
                            case "ACK!":
                                pheroRouter.handleACK(payload, fromPeer: packet.originID.uuidString)

                            case "TXT!":
                                let channelForACK = packet.channelID
                                let beforeCount = txtService.messagesByChannel[channelForACK]?.count ?? 0
                                txtService.handlePacket(payload, channelID: channelForACK)
                                let afterCount = txtService.messagesByChannel[channelForACK]?.count ?? 0

                                if afterCount > beforeCount, !channelForACK.isEmpty {
                                    pheroRouter.acknowledgeDelivery(
                                        packetID: packet.packetID,
                                        senderID: packet.originID.uuidString,
                                        channelID: packet.channelID
                                    )
                                    if let lastMsg = txtService.messagesByChannel[channelForACK]?.last {
                                        let chName = chanMgr.channels.first(where: { $0.id == channelForACK })?.name ?? "Chirp"
                                        NotificationService.shared.showMessageNotification(
                                            from: lastMsg.senderName,
                                            text: lastMsg.text,
                                            channelName: chName
                                        )
                                    }
                                }

                            case "RXN!":
                                txtService.handleReaction(payload, channelID: packet.channelID)

                            case "FIL!", "FLC!", "FNK!":
                                fileService.handlePacket(payload, channelID: packet.channelID)

                            case "SCN!":
                                bleScan.handleMeshScanReport(payload)

                            case "SND!":
                                sndAlertService.handleMeshAlert(payload)

                            case "BCK!":
                                cloudService.handleBackupChunk(payload)

                            case "BRQ!":
                                cloudService.handleRetrievalRequest(payload)

                            case "UWB!":
                                uwbSvc.handleTokenPacket(payload, fromPeer: packet.originID.uuidString)

                            case "LHQ!", "LHR!":
                                lighthouseSvc.handlePacket(payload)

                            case "WRQ!", "WCS!":
                                witnessService.handlePacket(payload, channelID: packet.channelID)

                            case "DRP!", "DPK!":
                                deadDropSvc.handlePacket(payload, channelID: packet.channelID)

                            case "DRK!", "DVK!":
                                darkroomSvc.handlePacket(payload, channelID: packet.channelID)

                            case "BBL!":
                                babelSvc.handlePacket(payload, channelID: packet.channelID)

                            case "SWM!", "SWR!", "SWC!", "SWA!":
                                swarmSvc.handlePacket(payload, fromPeer: packet.originID.uuidString, channelID: packet.channelID)

                            case "CHR!", "CHO!", "CHC!", "CHX!":
                                chorusSvc.handlePacket(payload, fromPeer: packet.originID.uuidString, channelID: packet.channelID)

                            case "SOS!":
                                let sosCountBefore = EmergencyBeacon.shared.receivedAlerts.count
                                EmergencyBeacon.shared.handleReceivedSOSData(payload)
                                if EmergencyBeacon.shared.receivedAlerts.count > sosCountBefore,
                                   let sosMsg = EmergencyBeacon.shared.receivedAlerts.first {
                                    NotificationService.shared.showSOSNotification(from: sosMsg.senderName)
                                }

                            case "KRO!":
                                if let rotation = ChannelManager.parseKeyRotationPayload(payload) {
                                    chanMgr.handleKeyRotation(channelID: rotation.channelID, peerEpoch: rotation.epoch)
                                }

                            default:
                                // Gateway uses 3-byte prefixes (GW!, GR!) and 4-byte (GDR!)
                                if payload.count >= 3 {
                                    let prefix3 = String(data: payload.prefix(3), encoding: .ascii) ?? ""
                                    if prefix3 == "GW!" || prefix3 == "GR!" {
                                        gatewaySvc.handleGatewayPayload(payload)
                                        break
                                    }
                                }
                                if payload.count >= 4 {
                                    let prefix4 = String(data: payload.prefix(4), encoding: .ascii) ?? ""
                                    if prefix4 == "GDR!" {
                                        gatewaySvc.handleGatewayPayload(payload)
                                        break
                                    }
                                }

                                // FloorControlMessage uses JSON without a magic prefix
                                if let message = try? MeshCodable.decoder.decode(FloorControlMessage.self, from: payload) {
                                    floorCtrl.handleMessage(message)

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
                        }
                    }
                },
                onForward: { (packet: MeshPacket, excludePeer: String) in
                    // Forward on BOTH transports — MeshRouter dedup handles overlap
                    let serialized = packet.serialize()
                    mpTransport.forwardPacket(serialized, excludePeer: excludePeer)
                    Task { @MainActor in
                        waTransportRef?.forwardPacket(serialized, excludePeer: excludePeer)
                    }
                }
            )
        }

        logger.info("AppState initialized — peerID=\(peerID), name=\(self.callsign)")
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        // Initialize encrypted message database before any packets arrive
        textMessageService.setupDatabase()

        // Load peer fingerprint
        self.peerFingerprint = await PeerIdentity.shared.fingerprint

        // Request mic permission early
        await requestMicPermission()

        // Register for audio session interruption and route change notifications
        AudioSessionManager.registerForNotifications()

        // Audio session interruption and route-change callbacks are wired
        // inside PTTEngine.setupCallbacks() (called from pttEngine.start()).

        pttEngine.multipeerTransport = multipeerTransport
        pttEngine.wifiAwareTransport = wifiAwareTransport
        pttEngine.peerListProvider = { [weak self] in
            self?.channelManager.activeChannel?.peers ?? []
        }
        pttEngine.wifiAwareMetricsProvider = { [weak self] in
            self?.wifiAwareTransport?.linkMetrics ?? [:]
        }
        try? await pttEngine.start()
        await peerTracker.startHealthCheck()

        // Start both transports — all incoming packets delivered via meshRouter.onLocalDelivery.
        // MeshRouter dedup (by packetID) prevents double-delivery when both transports carry the same packet.
        multipeerTransport.start()
        wifiAwareTransport?.start()

        // Start cover traffic + triple encryption
        meshShield.start(
            transport: multipeerTransport,
            waTransport: wifiAwareTransport
        )

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

        // Request notification permission for background message alerts
        NotificationService.shared.requestPermission()

        // Request location permission and start updates for location sharing
        locationService.onPermissionDenied = { [weak self] in
            self?.handleLocationPermissionDenied()
        }
        locationService.requestPermission()
        locationService.startUpdating()

        // Start LIGHTHOUSE recording
        lighthouseService.startRecording(peerID: localPeerID)

        // Register SWARM background tasks
        swarmService.registerBackgroundTask()

        // Register background tasks to keep mesh alive
        backgroundService.registerBackgroundTasks()

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

        // Route SOS beacon broadcasts through the mesh transports
        let mpTransportForSOS = self.multipeerTransport
        let waTransportForSOS = self.wifiAwareTransport
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .emergencySOSBroadcast, object: nil, queue: .main
        ) { notification in
            guard let data = notification.userInfo?["packet"] as? Data else { return }
            mpTransportForSOS.forwardPacket(data, excludePeer: "")
            Task { @MainActor in
                waTransportForSOS?.forwardPacket(data, excludePeer: "")
            }
        })

        // Emergency mode: auto-join emergency channel and force beacon refresh
        let chanMgrForEmergency = self.channelManager
        let beaconForEmergency = self.meshBeacon
        let peerIDForEmergency = self.localPeerID
        let callsignForEmergency = self.callsign
        let routerForEmergency = self.meshRouter
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .emergencyModeChanged, object: nil, queue: .main
        ) { notification in
            let active = notification.userInfo?["active"] as? Bool ?? false
            MainActor.assumeIsolated {
                guard active else { return }

                // Toggle mesh router emergency relay
                Task { await routerForEmergency.setEmergencyRelay(active) }

                guard active else { return }

                // Create emergency channel if it doesn't exist
                let emergencyID = EmergencyMode.emergencyChannelID
                if !chanMgrForEmergency.channels.contains(where: { $0.id == emergencyID }) {
                    _ = chanMgrForEmergency.createChannel(
                        name: EmergencyMode.emergencyChannelName,
                        id: emergencyID
                    )
                }
                // Switch to emergency channel
                chanMgrForEmergency.joinChannel(id: emergencyID)

                // Force beacon to use emergency interval
                let channelIDs = chanMgrForEmergency.channels.map(\.id)
                beaconForEmergency.updateBroadcastInterval(forPeerCount: 0)
                beaconForEmergency.startBroadcasting(
                    localID: peerIDForEmergency,
                    localName: callsignForEmergency,
                    channels: channelIDs
                )
            }
        })

        // Route mesh beacon broadcasts through the mesh transports
        let mpTransportForBeacon = self.multipeerTransport
        let waTransportForBeacon = self.wifiAwareTransport
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshBeaconBroadcast, object: nil, queue: .main
        ) { notification in
            guard let data = notification.userInfo?["packet"] as? Data else { return }
            mpTransportForBeacon.forwardPacket(data, excludePeer: "")
            Task { @MainActor in
                waTransportForBeacon?.forwardPacket(data, excludePeer: "")
            }
        })

        // Route mesh gateway broadcasts through the mesh transports
        let mpTransportForGW = self.multipeerTransport
        let waTransportForGW = self.wifiAwareTransport
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshGatewayRequest, object: nil, queue: .main
        ) { notification in
            guard let data = notification.userInfo?["packet"] as? Data else { return }
            mpTransportForGW.forwardPacket(data, excludePeer: "")
            Task { @MainActor in
                waTransportForGW?.forwardPacket(data, excludePeer: "")
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshGatewayBeaconBroadcast, object: nil, queue: .main
        ) { notification in
            guard let data = notification.userInfo?["packet"] as? Data else { return }
            mpTransportForGW.forwardPacket(data, excludePeer: "")
            Task { @MainActor in
                waTransportForGW?.forwardPacket(data, excludePeer: "")
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .meshGatewayDeliveryReceipt, object: nil, queue: .main
        ) { notification in
            guard let data = notification.userInfo?["packet"] as? Data else { return }
            mpTransportForGW.forwardPacket(data, excludePeer: "")
            Task { @MainActor in
                waTransportForGW?.forwardPacket(data, excludePeer: "")
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

        // Adaptive Opus bitrate: periodically check WiFi Aware link quality
        // and adjust encoder bitrate to match available bandwidth.
        startBitrateAdaptation()

        logger.info("AppState started")
    }

    /// Graceful shutdown.
    func stop() {
        bitrateAdaptationTask?.cancel()
        bitrateAdaptationTask = nil
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        clearActiveState()
        pttEngine.stop()
        liveActivityManager.endActivity()
        bleScanner.stopScanning()
        soundAlertService.stopListening()
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

    // MARK: - Unified Peer List

    /// Merge peers from both transports, dedup by ID, prefer Wi-Fi Aware metadata.
    private func updateUnifiedPeerList() {
        let mcPeers = multipeerTransport.peers
        let waPeers = wifiAwareTransport?.peers ?? []

        var merged: [String: ChirpPeer] = [:]
        for peer in mcPeers {
            var p = peer
            p.transportType = .multipeer
            merged[peer.id] = p
        }
        for peer in waPeers {
            if var existing = merged[peer.id] {
                existing.transportType = .both
                existing.signalStrength = max(existing.signalStrength, peer.signalStrength)
                merged[peer.id] = existing
            } else {
                var p = peer
                p.transportType = .wifiAware
                merged[peer.id] = p
            }
        }

        let allPeers = Array(merged.values)
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

        // Update active channel peers
        if let activeID = channelManager.activeChannel?.id {
            for existingPeer in channelManager.activeChannel?.peers ?? [] {
                channelManager.removePeerFromChannel(channelID: activeID, peerID: existingPeer.id)
            }
            for peer in allPeers {
                channelManager.addPeerToChannel(channelID: activeID, peer: peer)
            }
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
                try? mpTransport.sendControlData(msg.payload, channelID: msg.channelID)
                try? wifiAwareTransport?.sendControlData(msg.payload, channelID: msg.channelID)
            }
        }

        // Log peer changes
        if allPeers.count > oldCount {
            Logger.network.info("Peer connected (total: \(allPeers.count), MC: \(mcPeers.count), WA: \(waPeers.count))")
        } else if allPeers.count < oldCount {
            Logger.network.info("Peer disconnected (total: \(allPeers.count))")
        }
    }

    // MARK: - Adaptive Bitrate

    /// Periodically check WiFi Aware link quality and adjust the Opus encoder bitrate.
    /// Uses ~30% of the minimum available throughput across all peers as target, clamped
    /// to voice quality tiers. Only adapts when WiFi Aware metrics are available;
    /// MultipeerConnectivity-only sessions keep the default bitrate.
    private func startBitrateAdaptation() {
        bitrateAdaptationTask?.cancel()
        bitrateAdaptationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { break }

                // Only adapt if WiFi Aware transport is active with metrics
                guard let waTransport = self.wifiAwareTransport,
                      !waTransport.linkMetrics.isEmpty else {
                    continue
                }

                // Find minimum throughputCapacity across all WiFi Aware peers
                let capacities = waTransport.linkMetrics.values.compactMap { $0.throughputCapacity }
                guard let minCapacity = capacities.min() else { continue }

                // Use 30% of available bandwidth (leave headroom for control messages)
                let availableBps = Int(minCapacity * 0.30)

                // Map to quality tier
                let tier = OpusCodec.BitrateQuality.from(availableBandwidth: availableBps)

                self.audioEngine.setTargetBitrate(tier.rawValue)

                Logger.audio.debug("Adaptive bitrate: minCapacity=\(Int(minCapacity))bps, available=\(availableBps)bps, tier=\(tier.rawValue)bps")
            }
        }
    }

    // MARK: - Live Activity

    /// Call this whenever PTT state or audio level changes to keep the Dynamic Island in sync.
    func updateLiveActivity() {
        let channel = channelManager.activeChannel
        liveActivityManager.updateActivity(
            state: pttState,
            channelName: channel?.name ?? "ChirpChirps",
            peerCount: channel?.activePeerCount ?? 0,
            inputLevel: Double(inputLevel)
        )
    }
}

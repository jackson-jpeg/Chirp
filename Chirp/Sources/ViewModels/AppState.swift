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

    // MARK: - Identity

    let localPeerID: String
    let localPeerName: String

    // MARK: - Persisted State

    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "com.chirp.onboardingComplete") {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    var callsign: String = UserDefaults.standard.string(forKey: "com.chirp.callsign") ?? UIDevice.current.name {
        didSet { UserDefaults.standard.set(callsign, forKey: "com.chirp.callsign") }
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

    // MARK: - Private

    private let logger = Logger.ptt

    private enum Keys {
        static let peerID = "com.chirp.localPeerID"
        static let onboardingComplete = "com.chirp.onboardingComplete"
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
            connectionManager: connectionManager
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

        let displayName = UserDefaults.standard.string(forKey: "com.chirp.callsign") ?? UIDevice.current.name
        let transport = MultipeerTransport(displayName: displayName)
        self.multipeerTransport = transport

        // Wire multipeer to PTT engine for real peer-to-peer audio
        transport.onPeersChanged = { [weak self] peers in
            guard let self else { return }
            // Update active channel peers
            if let activeID = self.channelManager.activeChannel?.id {
                // Clear old peers and add current ones
                for existingPeer in self.channelManager.activeChannel?.peers ?? [] {
                    self.channelManager.removePeerFromChannel(channelID: activeID, peerID: existingPeer.id)
                }
                for peer in peers {
                    self.channelManager.addPeerToChannel(channelID: activeID, peer: peer)
                }
            }
        }

        logger.info("AppState initialized — peerID=\(peerID), name=\(self.callsign)")
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        // Request mic permission early
        await requestMicPermission()

        pttEngine.multipeerTransport = multipeerTransport
        try? await pttEngine.start()
        await peerTracker.startHealthCheck()

        // Start MultipeerConnectivity transport for local peer discovery
        multipeerTransport.start()

        // Wire multipeer audio/control streams into PTT engine receive loops
        Task {
            for await data in multipeerTransport.audioPackets {
                if let packet = AudioPacket.deserialize(data) {
                    audioEngine.receiveAudioPacket(packet.opusData, sequenceNumber: packet.sequenceNumber)
                }
            }
        }
        Task {
            for await message in multipeerTransport.controlMessages {
                floorController.handleMessage(message)
            }
        }

        // Create a default channel if none exist (first launch).
        // Channels are persisted, so this only runs once.
        if channelManager.channels.isEmpty {
            let defaultChannel = channelManager.createChannel(name: "General")
            channelManager.joinChannel(id: defaultChannel.id)
        }

        // Live Activity disabled until widget extension signing is resolved
        // if let channel = channelManager.activeChannel {
        //     liveActivityManager.startActivity(channelName: channel.name)
        // }

        logger.info("AppState started")
    }

    /// Graceful shutdown.
    func stop() {
        pttEngine.stop()
        liveActivityManager.endActivity()
        Task { await peerTracker.stopHealthCheck() }
        logger.info("AppState stopped")
    }

    // MARK: - Live Activity

    /// Call this whenever PTT state or audio level changes to keep the Dynamic Island in sync.
    func updateLiveActivity() {
        let channel = channelManager.activeChannel
        liveActivityManager.updateActivity(
            state: pttState,
            channelName: channel?.name ?? "Chirp",
            peerCount: channel?.activePeerCount ?? 0,
            inputLevel: Double(inputLevel)
        )
    }
}

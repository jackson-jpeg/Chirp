import ActivityKit
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

    // MARK: - Identity

    let localPeerID: String
    let localPeerName: String

    // MARK: - Persisted State

    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "com.chirp.onboardingComplete") {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
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

        logger.info("AppState initialized — peerID=\(peerID), name=\(self.localPeerName)")
    }

    // MARK: - Lifecycle

    /// Call once from the app's root view `.task` modifier.
    func start() async {
        try? await pttEngine.start()
        await peerTracker.startHealthCheck()

        // Create a default channel if none exist.
        if channelManager.channels.isEmpty {
            let defaultChannel = channelManager.createChannel(name: "General")
            channelManager.joinChannel(id: defaultChannel.id)
        }

        // Start Live Activity for the active channel.
        if let channel = channelManager.activeChannel {
            liveActivityManager.startActivity(channelName: channel.name)
        }

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

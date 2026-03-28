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

    // MARK: - Identity

    let localPeerID: String
    let localPeerName: String

    // MARK: - Persisted State

    var isOnboardingComplete: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.onboardingComplete) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.onboardingComplete) }
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

        logger.info("AppState started")
    }

    /// Graceful shutdown.
    func stop() {
        pttEngine.stop()
        Task { await peerTracker.stopHealthCheck() }
        logger.info("AppState stopped")
    }
}

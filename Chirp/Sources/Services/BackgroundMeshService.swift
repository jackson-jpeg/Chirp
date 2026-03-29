import AVFoundation
import BackgroundTasks
import Foundation
import OSLog
import UIKit

/// Keeps the mesh network running when the app is backgrounded.
/// Uses audio background mode with a silent audio loop to prevent iOS
/// from suspending the process. MultipeerConnectivity stays active as
/// long as the process is alive, so this is critical for emergency use.
@MainActor
final class BackgroundMeshService {
    static let shared = BackgroundMeshService()

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "Background")
    private var silentPlayer: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private(set) var isBackgrounded = false

    static let refreshTaskID = "com.chirpchirp.mesh.refresh"

    private init() {}

    // MARK: - Background / Foreground Transitions

    /// Start background execution. Called when app enters background.
    func enterBackground() {
        guard !isBackgrounded else { return }
        isBackgrounded = true
        logger.info("Entering background — starting mesh keep-alive")

        startSilentAudio()
        beginBackgroundTask()
    }

    /// Stop background execution. Called when app enters foreground.
    func enterForeground() {
        guard isBackgrounded else { return }
        isBackgrounded = false
        logger.info("Entering foreground — stopping mesh keep-alive")

        stopSilentAudio()
        endBackgroundTask()
    }

    // MARK: - Background Task Registration

    /// Register the BGAppRefreshTask for periodic mesh maintenance.
    /// Call this once at app launch.
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: .main
        ) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            self?.handleBackgroundRefresh(bgTask)
        }
        logger.info("Registered background refresh task: \(Self.refreshTaskID)")
        scheduleNextRefresh()
    }

    // MARK: - Silent Audio Keep-Alive

    /// Start a silent audio loop to keep the app running via the audio background mode.
    /// iOS allows apps playing audio to continue executing in the background.
    private func startSilentAudio() {
        // Configure audio session for background playback
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session for background: \(error.localizedDescription)")
            return
        }

        // Generate a tiny silent audio buffer (0.1 seconds of silence at 44100 Hz)
        guard let silentData = generateSilentWAV(durationSeconds: 0.1, sampleRate: 44100) else {
            logger.error("Failed to generate silent audio data")
            return
        }

        do {
            let player = try AVAudioPlayer(data: silentData)
            player.numberOfLoops = -1  // Loop forever
            player.volume = 0.0
            player.play()
            self.silentPlayer = player
            logger.info("Silent audio keep-alive started")
        } catch {
            logger.error("Failed to start silent audio player: \(error.localizedDescription)")
        }
    }

    /// Stop the silent audio loop.
    private func stopSilentAudio() {
        silentPlayer?.stop()
        silentPlayer = nil

        // Deactivate the playback session so it doesn't interfere with PTT audio
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        logger.info("Silent audio keep-alive stopped")
    }

    // MARK: - UIKit Background Task

    /// Begin a UIKit background task as a fallback keep-alive mechanism.
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MeshKeepAlive") { [weak self] in
            // Expiration handler -- clean up gracefully
            self?.logger.warning("Background task expiring")
            self?.endBackgroundTask()
        }
        if backgroundTask != .invalid {
            logger.info("UIKit background task started (id: \(self.backgroundTask.rawValue))")
            // End the UIKit task after 5 seconds — the silent audio loop
            // is the real keep-alive mechanism, not this task.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    /// End the UIKit background task.
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        logger.info("UIKit background task ended")
        backgroundTask = .invalid
    }

    // MARK: - BGAppRefreshTask

    /// Handle a periodic background refresh -- send a mesh beacon.
    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        logger.info("Background refresh task fired")

        // Schedule the next one immediately so we keep the chain going
        scheduleNextRefresh()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // The mesh transport stays alive via silent audio, so this is mainly
        // to trigger a beacon broadcast to maintain presence in the mesh.
        // Actual beacon sending would be done through the mesh beacon service.
        task.setTaskCompleted(success: true)
        logger.info("Background refresh task completed")
    }

    /// Schedule the next BGAppRefreshTask.
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled next background refresh")
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }

    // MARK: - Silent WAV Generation

    /// Generate a minimal WAV file with silence.
    private func generateSilentWAV(durationSeconds: Double, sampleRate: Int) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let dataSize = numSamples * Int(numChannels) * Int(bitsPerSample / 8)

        var data = Data()
        data.reserveCapacity(44 + dataSize)

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32LE(&data, UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32LE(&data, 16)  // chunk size
        appendUInt16LE(&data, 1)   // PCM format
        appendUInt16LE(&data, numChannels)
        appendUInt32LE(&data, UInt32(sampleRate))
        appendUInt32LE(&data, UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8)))  // byte rate
        appendUInt16LE(&data, numChannels * (bitsPerSample / 8))  // block align
        appendUInt16LE(&data, bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendUInt32LE(&data, UInt32(dataSize))

        // Silent samples (all zeros)
        data.append(Data(count: dataSize))

        return data
    }

    private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }

    private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }
}

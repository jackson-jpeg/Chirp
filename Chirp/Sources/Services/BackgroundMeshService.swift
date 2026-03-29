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
    private var toneEngine: AVAudioEngine?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var engineRestartTask: Task<Void, Never>?

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

    // MARK: - Inaudible Tone Keep-Alive

    /// Start an inaudible 20Hz tone at -60dB to keep the app running via audio background mode.
    /// A real (but inaudible) tone is more robust than pure silence -- iOS is less likely
    /// to detect "no audio" and suspend the process.
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

        startToneEngine()
        monitorEngineHealth()
    }

    /// Stop the inaudible tone and tear down the engine.
    private func stopSilentAudio() {
        engineRestartTask?.cancel()
        engineRestartTask = nil

        if let engine = toneEngine {
            engine.stop()
            toneEngine = nil
        }

        // Deactivate the playback session so it doesn't interfere with PTT audio
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        logger.info("Inaudible tone keep-alive stopped")
    }

    /// Create and start an AVAudioEngine with a source node generating 20Hz at -60dB.
    private func startToneEngine() {
        let engine = AVAudioEngine()
        let sampleRate: Double = 44100.0
        let frequency: Double = 20.0        // 20Hz -- below human hearing threshold for most people
        let amplitude: Float = 0.001        // approximately -60dB

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        var phase: Double = 0.0
        let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate

        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * amplitude
                phase += phaseIncrement
                if phase >= 2.0 * Double.pi { phase -= 2.0 * Double.pi }
                for buffer in bufferList {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.toneEngine = engine
            logger.info("Inaudible 20Hz tone keep-alive started (amplitude=\(amplitude))")
        } catch {
            logger.error("Failed to start tone engine: \(error.localizedDescription)")
        }
    }

    /// Monitor the tone engine and auto-restart if iOS stops it unexpectedly.
    private func monitorEngineHealth() {
        engineRestartTask?.cancel()
        engineRestartTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isBackgrounded else { break }
                if let engine = self.toneEngine, !engine.isRunning {
                    self.logger.warning("Tone engine stopped unexpectedly — restarting")
                    engine.stop()
                    self.toneEngine = nil

                    // Re-activate audio session before restarting
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.startToneEngine()
                }
            }
        }
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

}

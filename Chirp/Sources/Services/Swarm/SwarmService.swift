import BackgroundTasks
import CoreML
import Foundation
import Observation
import OSLog
import UIKit

/// Distributed compute service that parallelizes CoreML inference across mesh peers.
///
/// Work distribution follows a weighted round-robin strategy based on each node's
/// ``SwarmNodeCapability``. Thermal and battery guards prevent devices from
/// accepting work that would degrade user experience.
///
/// Two execution modes:
/// - **Background**: Registered as a `BGProcessingTask`, requires external power.
/// - **Foreground**: Direct CoreML inference while the app is active.
@Observable
@MainActor
final class SwarmService {

    // MARK: - Public State

    private(set) var activeJobs: [UUID: SwarmJob] = [:]
    private(set) var completedUnits: [UUID: [UInt32: SwarmWorkResult]] = [:]
    private(set) var knownNodes: [String: SwarmNodeCapability] = [:]
    private(set) var localWorkQueue: [SwarmWorkUnit] = []

    var donateBackgroundCompute: Bool = false {
        didSet { UserDefaults.standard.set(donateBackgroundCompute, forKey: Keys.donateBackground) }
    }

    var donateForegroundCompute: Bool = false {
        didSet { UserDefaults.standard.set(donateForegroundCompute, forKey: Keys.donateForeground) }
    }

    // MARK: - Callbacks

    /// Send a packet to a specific peer (by ID) or broadcast (empty string).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "Swarm")
    private let localPeerID: String

    /// Tracks which unit index to assign next per-job for round-robin distribution.
    private var assignmentCursors: [UUID: Int] = [:]

    private static let backgroundTaskID = "com.chirpchirp.swarm.compute"
    private static let minimumBattery: Float = 0.20
    /// `ProcessInfo.ThermalState.serious.rawValue`
    private static let maxThermalState = 2

    private enum Keys {
        static let donateBackground = "com.chirpchirp.swarm.donateBackground"
        static let donateForeground = "com.chirpchirp.swarm.donateForeground"
    }

    // MARK: - Init

    init(localPeerID: String) {
        self.localPeerID = localPeerID

        // Restore persisted preferences
        self.donateBackgroundCompute = UserDefaults.standard.bool(forKey: Keys.donateBackground)
        self.donateForegroundCompute = UserDefaults.standard.bool(forKey: Keys.donateForeground)
    }

    // MARK: - Job Creation

    /// Create a new swarm job, advertise it, and begin distributing work units.
    ///
    /// - Parameters:
    ///   - modelID: CoreML model identifier that workers must have available.
    ///   - description: Human-readable description of the job.
    ///   - inputs: Array of input data blobs, one per work unit.
    ///   - priority: Background (power-required) or foreground (real-time).
    ///   - channelID: Mesh channel to broadcast on.
    /// - Returns: The created ``SwarmJob``.
    @discardableResult
    func createJob(
        modelID: String,
        description: String,
        inputs: [Data],
        priority: SwarmJob.SwarmPriority,
        channelID: String
    ) -> SwarmJob {
        let job = SwarmJob(
            id: UUID(),
            originatorID: localPeerID,
            modelID: modelID,
            description: description,
            totalUnits: UInt32(inputs.count),
            priority: priority,
            createdAt: Date(),
            deadline: priority == .foreground ? Date().addingTimeInterval(60) : nil
        )

        activeJobs[job.id] = job
        completedUnits[job.id] = [:]
        assignmentCursors[job.id] = 0

        // Advertise to mesh
        let advert = SwarmJobAdvertise(job: job)
        if let payload = try? advert.wirePayload() {
            onSendPacket?(payload, "")
        }

        logger.info("Created swarm job \(job.id): \(description), \(inputs.count) units, model=\(modelID)")

        // Distribute work units to known capable nodes
        distributeWorkUnits(job: job, inputs: inputs, channelID: channelID)

        return job
    }

    // MARK: - Packet Handling

    /// Route an incoming swarm packet to the appropriate handler based on magic prefix.
    func handlePacket(_ data: Data, fromPeer: String, channelID: String) {
        guard data.count >= 4 else { return }
        let prefix = Array(data.prefix(4))

        if prefix == SwarmJobAdvertise.magicPrefix {
            handleJobAdvertise(data, fromPeer: fromPeer, channelID: channelID)
        } else if prefix == SwarmNodeCapability.magicPrefix {
            handleNodeCapability(data, fromPeer: fromPeer)
        } else if prefix == SwarmWorkUnit.magicPrefix {
            handleWorkUnit(data, fromPeer: fromPeer, channelID: channelID)
        } else if prefix == SwarmWorkResult.magicPrefix {
            handleWorkResult(data, fromPeer: fromPeer)
        }
    }

    // MARK: - Background Task Registration

    /// Register the BGProcessingTask for background swarm compute.
    ///
    /// Call this once during app launch (e.g. in `application(_:didFinishLaunchingWithOptions:)`).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskID,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGProcessingTask else { return }
            Task { @MainActor [weak self] in
                self?.handleBackgroundTask(bgTask)
            }
        }

        logger.info("Registered background task: \(Self.backgroundTaskID)")
    }

    /// Schedule the next background processing task.
    func scheduleBackgroundTask() {
        guard donateBackgroundCompute else { return }

        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background swarm compute task")
        } catch {
            logger.error("Failed to schedule background task: \(error.localizedDescription)")
        }
    }

    // MARK: - Device Health

    /// Check whether this device is healthy enough to accept swarm work.
    ///
    /// Rejects if:
    /// - Battery below 20% (unless charging)
    /// - Thermal state is `.serious` or worse
    func checkDeviceHealth() -> Bool {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = device.batteryLevel
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        let thermalState = ProcessInfo.processInfo.thermalState.rawValue

        // Battery guard: reject if below threshold unless plugged in
        if batteryLevel >= 0, batteryLevel < Self.minimumBattery, !isCharging {
            logger.info("Rejecting swarm work: battery \(batteryLevel * 100)%% (not charging)")
            return false
        }

        // Thermal guard: reject if serious or critical
        if thermalState >= Self.maxThermalState {
            logger.info("Rejecting swarm work: thermal state \(thermalState)")
            return false
        }

        return true
    }

    // MARK: - Private: Packet Handlers

    private func handleJobAdvertise(_ data: Data, fromPeer: String, channelID: String) {
        guard let advert = SwarmJobAdvertise.from(payload: data) else { return }
        let job = advert.job

        // Don't process our own advertisements
        guard job.originatorID != localPeerID else { return }

        logger.info("Received job advert from \(fromPeer): \(job.description) (model=\(job.modelID))")

        // Check if we can contribute
        let canBackground = donateBackgroundCompute && job.priority == .background
        let canForeground = donateForegroundCompute && job.priority == .foreground

        guard canBackground || canForeground else {
            logger.info("Not accepting job \(job.id): donation not enabled for \(job.priority.rawValue)")
            return
        }

        guard checkDeviceHealth() else { return }

        // Respond with our capabilities
        let capability = buildLocalCapability(
            acceptsBackground: donateBackgroundCompute,
            acceptsForeground: donateForegroundCompute
        )

        if let payload = try? capability.wirePayload() {
            onSendPacket?(payload, fromPeer)
        }
    }

    private func handleNodeCapability(_ data: Data, fromPeer: String) {
        guard let capability = SwarmNodeCapability.from(payload: data) else { return }

        knownNodes[capability.peerID] = capability
        logger.info("Updated capability for \(capability.peerID): \(capability.availableModels.count) models, \(capability.availableMemoryMB)MB RAM")
    }

    private func handleWorkUnit(_ data: Data, fromPeer: String, channelID: String) {
        guard let unit = SwarmWorkUnit.from(payload: data) else { return }

        // Only process units assigned to us
        guard unit.assignedPeerID == localPeerID else { return }

        guard checkDeviceHealth() else {
            logger.warning("Rejecting work unit \(unit.id): device unhealthy")
            return
        }

        localWorkQueue.append(unit)
        logger.info("Queued work unit \(unit.unitIndex) for job \(unit.jobID)")

        // Execute immediately if foreground mode
        if let job = activeJobs[unit.jobID], job.priority == .foreground {
            Task { await executeWorkUnit(unit, channelID: channelID) }
        } else {
            // Background units are picked up by BGProcessingTask
            scheduleBackgroundTask()
        }
    }

    private func handleWorkResult(_ data: Data, fromPeer: String) {
        guard let result = SwarmWorkResult.from(payload: data) else { return }

        // Store the result
        if completedUnits[result.jobID] == nil {
            completedUnits[result.jobID] = [:]
        }
        completedUnits[result.jobID]?[result.unitIndex] = result

        // Check job completion
        if let job = activeJobs[result.jobID] {
            let completed = completedUnits[result.jobID]?.count ?? 0
            logger.info("Job \(job.id) progress: \(completed)/\(job.totalUnits) units")

            if completed >= job.totalUnits {
                logger.info("Job \(job.id) complete: \(job.description)")
                activeJobs.removeValue(forKey: job.id)
                assignmentCursors.removeValue(forKey: job.id)
            }
        }
    }

    // MARK: - Private: Work Distribution

    /// Distribute work units across known capable nodes using weighted round-robin.
    private func distributeWorkUnits(job: SwarmJob, inputs: [Data], channelID: String) {
        // Filter nodes that can handle this job
        let capableNodes = knownNodes.values.filter { node in
            node.availableModels.contains(job.modelID) &&
            (job.priority == .background ? node.acceptsBackground : node.acceptsForeground) &&
            isNodeHealthy(node)
        }

        guard !capableNodes.isEmpty else {
            logger.warning("No capable nodes for job \(job.id) — queuing locally")
            // Fall back to local execution
            for (index, input) in inputs.enumerated() {
                let unit = SwarmWorkUnit(
                    id: UUID(),
                    jobID: job.id,
                    unitIndex: UInt32(index),
                    assignedPeerID: localPeerID,
                    modelID: job.modelID,
                    inputData: input,
                    timestamp: Date()
                )
                localWorkQueue.append(unit)
            }
            return
        }

        // Weight nodes by available memory (rough proxy for compute capability)
        let totalMemory = capableNodes.reduce(0) { $0 + $1.availableMemoryMB }
        guard totalMemory > 0 else { return }

        var cursor = assignmentCursors[job.id] ?? 0

        for (index, input) in inputs.enumerated() {
            let nodeIndex = cursor % capableNodes.count
            let node = capableNodes[nodeIndex]
            cursor += 1

            let unit = SwarmWorkUnit(
                id: UUID(),
                jobID: job.id,
                unitIndex: UInt32(index),
                assignedPeerID: node.peerID,
                modelID: job.modelID,
                inputData: input,
                timestamp: Date()
            )

            if let payload = try? unit.wirePayload() {
                onSendPacket?(payload, node.peerID)
            }
        }

        assignmentCursors[job.id] = cursor
        logger.info("Distributed \(inputs.count) units across \(capableNodes.count) nodes")
    }

    /// Check whether a remote node meets health thresholds.
    private func isNodeHealthy(_ node: SwarmNodeCapability) -> Bool {
        // Battery guard
        if node.batteryLevel >= 0, node.batteryLevel < Self.minimumBattery, !node.isCharging {
            return false
        }
        // Thermal guard
        if node.thermalState >= Self.maxThermalState {
            return false
        }
        return true
    }

    // MARK: - Private: Execution

    /// Execute a work unit locally using CoreML.
    private func executeWorkUnit(_ unit: SwarmWorkUnit, channelID: String) async {
        let startTime = DispatchTime.now()

        logger.info("Executing work unit \(unit.unitIndex) for job \(unit.jobID)")

        // Attempt to load and run CoreML model
        guard let modelURL = findModelURL(for: unit.modelID) else {
            logger.error("Model not found: \(unit.modelID)")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: config)

            // Create input from raw data
            let inputFeature = try MLDictionaryFeatureProvider(
                dictionary: ["input": MLMultiArray(dataPointer: UnsafeMutableRawPointer(mutating: (unit.inputData as NSData).bytes),
                                                   shape: [NSNumber(value: unit.inputData.count)],
                                                   dataType: .float32,
                                                   strides: [1])]
            )

            let prediction = try await model.prediction(from: inputFeature)

            // Serialize output
            var resultData = Data()
            for featureName in prediction.featureNames {
                if let multiArray = prediction.featureValue(for: featureName)?.multiArrayValue {
                    let ptr = multiArray.dataPointer
                    let byteCount = multiArray.count * MemoryLayout<Float>.size
                    resultData.append(Data(bytes: ptr, count: byteCount))
                }
            }

            let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            let elapsedMs = elapsed / 1_000_000

            let result = SwarmWorkResult(
                jobID: unit.jobID,
                unitIndex: unit.unitIndex,
                workerPeerID: localPeerID,
                resultData: resultData,
                computeTimeMs: elapsedMs,
                timestamp: Date()
            )

            // Store locally
            if completedUnits[unit.jobID] == nil {
                completedUnits[unit.jobID] = [:]
            }
            completedUnits[unit.jobID]?[unit.unitIndex] = result

            // Send result back to originator
            if let payload = try? result.wirePayload() {
                onSendPacket?(payload, "")
            }

            // Remove from local queue
            localWorkQueue.removeAll { $0.id == unit.id }

            logger.info("Completed unit \(unit.unitIndex) for job \(unit.jobID) in \(elapsedMs)ms")

        } catch {
            logger.error("CoreML execution failed for unit \(unit.unitIndex): \(error.localizedDescription)")
            localWorkQueue.removeAll { $0.id == unit.id }
        }
    }

    /// Find compiled CoreML model URL by model identifier.
    private func findModelURL(for modelID: String) -> URL? {
        // Check app bundle first
        if let bundleURL = Bundle.main.url(forResource: modelID, withExtension: "mlmodelc") {
            return bundleURL
        }

        // Check Documents directory for downloaded models
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelURL = docsDir.appendingPathComponent("\(modelID).mlmodelc")
        if FileManager.default.fileExists(atPath: modelURL.path) {
            return modelURL
        }

        return nil
    }

    // MARK: - Private: Background Task

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        guard donateBackgroundCompute else {
            task.setTaskCompleted(success: true)
            return
        }

        guard checkDeviceHealth() else {
            task.setTaskCompleted(success: true)
            scheduleBackgroundTask()
            return
        }

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.logger.info("Background task expired, rescheduling")
                self?.scheduleBackgroundTask()
            }
        }

        // Process queued work units
        Task {
            var processedCount = 0
            while !localWorkQueue.isEmpty, checkDeviceHealth() {
                let unit = localWorkQueue[0]
                await executeWorkUnit(unit, channelID: "")
                processedCount += 1

                // Yield to prevent blocking too long
                try? await Task.sleep(for: .milliseconds(100))
            }

            logger.info("Background task processed \(processedCount) units")
            task.setTaskCompleted(success: true)
            scheduleBackgroundTask()
        }
    }

    // MARK: - Private: Capability Building

    private func buildLocalCapability(acceptsBackground: Bool, acceptsForeground: Bool) -> SwarmNodeCapability {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        // Enumerate locally available models
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var models: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: nil
        ) {
            models = contents
                .filter { $0.pathExtension == "mlmodelc" }
                .map { $0.deletingPathExtension().lastPathComponent }
        }

        // Estimate available memory
        let availableMemory = Int(os_proc_available_memory() / (1024 * 1024))

        return SwarmNodeCapability(
            peerID: localPeerID,
            availableModels: models,
            batteryLevel: device.batteryLevel,
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            availableMemoryMB: availableMemory,
            acceptsBackground: acceptsBackground,
            acceptsForeground: acceptsForeground
        )
    }
}

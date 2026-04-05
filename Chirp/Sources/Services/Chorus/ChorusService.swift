import CoreML
import Foundation
import Observation
import OSLog
import UIKit

/// Distributed pipeline-parallel inference service across mesh peers.
///
/// CHORUS partitions a large CoreML model's layers across multiple devices,
/// flowing intermediate activations (tensors) through the pipeline in sequence.
/// This enables running models that exceed a single device's memory.
///
/// Pipeline negotiation:
/// 1. Broadcast `CHO!` offer request to the mesh
/// 2. Collect ``ChorusPipelineOffer`` responses from peers
/// 3. Partition model layers weighted by each peer's ``ChorusPipelineOffer/computeCapability``
/// 4. Send ``ChorusPipelineConfig`` (`CHC!`) to each participating peer
/// 5. Submit inputs as ``ChorusActivation`` (`CHR!`) binary packets
/// 6. Collect ``ChorusResult`` (`CHX!`) from the final stage
@Observable
@MainActor
final class ChorusService {

    // MARK: - Public State

    private(set) var activePipelines: [UUID: ChorusPipelineConfig] = [:]
    private(set) var peerOffers: [String: ChorusPipelineOffer] = [:]
    private(set) var completedResults: [UUID: [UInt32: ChorusResult]] = [:]

    /// Model currently loaded for this device's pipeline stage, if any.
    private(set) var localStageModel: String?

    // MARK: - Callbacks

    /// Send a packet to a specific peer (by ID) or broadcast (empty string).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "Chorus")
    private let localPeerID: String

    /// Loaded CoreML model for local stage execution.
    private var loadedModel: MLModel?
    /// The pipeline config for a pipeline where this device is a stage participant.
    private var localPipelineConfig: ChorusPipelineConfig?
    /// Local stage index within the active pipeline.
    private var localStageIndex: Int?

    /// Pending activations waiting for pipeline configuration.
    private var pendingActivations: [UUID: [UInt32: ChorusActivation]] = [:]

    /// Timeout for collecting peer offers during pipeline negotiation.
    private static let offerCollectionTimeout: TimeInterval = 5.0
    /// Minimum battery level to participate in pipeline inference.
    private static let minimumBattery: Float = 0.20
    /// Maximum thermal state (ProcessInfo.ThermalState.serious.rawValue).
    private static let maxThermalState = 2

    // MARK: - Init

    init(localPeerID: String) {
        self.localPeerID = localPeerID
    }

    // MARK: - Pipeline Request

    /// Broadcast a request for peers to join a distributed pipeline for the given model.
    ///
    /// After broadcasting, waits ``offerCollectionTimeout`` seconds for responses
    /// before returning. Use ``configurePipeline(modelID:offers:)`` to finalize.
    func requestPipeline(modelID: String, channelID: String) {
        // Build and broadcast our own offer
        let localOffer = buildLocalOffer(modelID: modelID)
        peerOffers[localPeerID] = localOffer

        // Broadcast offer request — peers respond with CHO! packets
        if let payload = try? localOffer.wirePayload() {
            onSendPacket?(payload, "")
        }

        logger.info("Broadcast pipeline request for model \(modelID)")
    }

    // MARK: - Pipeline Configuration

    /// Partition model layers across collected peer offers and distribute config.
    ///
    /// Layers are assigned proportionally to each peer's ``ChorusPipelineOffer/computeCapability``.
    /// Returns the finalized ``ChorusPipelineConfig``.
    @discardableResult
    func configurePipeline(
        modelID: String,
        offers: [ChorusPipelineOffer]
    ) -> ChorusPipelineConfig {
        let totalLayers = estimateModelLayers(modelID: modelID)
        let totalCompute = offers.reduce(0) { $0 + max($1.computeCapability, 1) }

        var stages: [ChorusPipelineConfig.PipelineStage] = []
        var currentLayer = 0

        for (index, offer) in offers.enumerated() {
            let isLast = index == offers.count - 1
            let proportion = Double(max(offer.computeCapability, 1)) / Double(max(totalCompute, 1))
            let layerCount: Int

            if isLast {
                // Last peer gets all remaining layers to avoid rounding gaps
                layerCount = totalLayers - currentLayer
            } else {
                layerCount = max(1, Int(Double(totalLayers) * proportion))
            }

            let endLayer = min(currentLayer + layerCount - 1, totalLayers - 1)

            stages.append(ChorusPipelineConfig.PipelineStage(
                peerID: offer.peerID,
                startLayer: currentLayer,
                endLayer: endLayer
            ))

            currentLayer = endLayer + 1

            if currentLayer >= totalLayers { break }
        }

        let config = ChorusPipelineConfig(
            id: UUID(),
            modelID: modelID,
            stages: stages,
            totalLayers: totalLayers
        )

        activePipelines[config.id] = config
        completedResults[config.id] = [:]

        // Send config to each participating peer
        if let payload = try? config.wirePayload() {
            for stage in stages {
                onSendPacket?(payload, stage.peerID)
            }
        }

        logger.info("Configured pipeline \(config.id): \(stages.count) stages, \(totalLayers) layers")

        return config
    }

    // MARK: - Input Submission

    /// Submit input data to the first stage of a pipeline for inference.
    func submitInput(pipelineID: UUID, inputIndex: UInt32, data: Data, channelID: String) {
        guard let config = activePipelines[pipelineID],
              let firstStage = config.stages.first else {
            logger.warning("No pipeline config for \(pipelineID)")
            return
        }

        let activation = ChorusActivation(
            pipelineID: pipelineID,
            stageIndex: 0,
            inputIndex: inputIndex,
            tensorData: data,
            shape: [data.count / MemoryLayout<Float>.size],
            dataType: .float32
        )

        let payload = activation.wirePayload()

        if firstStage.peerID == localPeerID {
            // First stage is local — execute directly
            Task { await executeLocalStage(activation, config: config) }
        } else {
            onSendPacket?(payload, firstStage.peerID)
        }

        logger.info("Submitted input \(inputIndex) to pipeline \(pipelineID)")
    }

    // MARK: - Packet Handling

    /// Route an incoming chorus packet to the appropriate handler based on magic prefix.
    func handlePacket(_ data: Data, fromPeer: String, channelID: String) {
        guard data.count >= 4 else { return }
        let prefix = Array(data.prefix(4))

        if prefix == ChorusPipelineOffer.magicPrefix {
            handleOffer(data, fromPeer: fromPeer)
        } else if prefix == ChorusPipelineConfig.magicPrefix {
            handleConfig(data, fromPeer: fromPeer)
        } else if prefix == ChorusActivation.magicPrefix {
            handleActivation(data, fromPeer: fromPeer, channelID: channelID)
        } else if prefix == ChorusResult.magicPrefix {
            handleResult(data, fromPeer: fromPeer)
        }
    }

    // MARK: - BABEL Integration

    /// Find a peer that has the specified model available for pipeline inference.
    ///
    /// Returns the peer ID or `nil` if no peer offers that model.
    func findPeerWithModel(_ modelID: String) -> String? {
        peerOffers.first { $0.value.modelID == modelID }?.key
    }

    // MARK: - Private: Packet Handlers

    private func handleOffer(_ data: Data, fromPeer: String) {
        guard let offer = ChorusPipelineOffer.from(payload: data) else { return }

        // Don't store offers from unhealthy nodes
        guard isOfferHealthy(offer) else {
            logger.info("Rejected offer from \(fromPeer): unhealthy")
            return
        }

        peerOffers[offer.peerID] = offer
        logger.info("Received pipeline offer from \(offer.peerID): \(offer.computeCapability) TFLOPS, \(offer.availableMemoryMB)MB")
    }

    private func handleConfig(_ data: Data, fromPeer: String) {
        guard let config = ChorusPipelineConfig.from(payload: data) else { return }

        // Check if we're a participant in this pipeline
        guard let stageIdx = config.stages.firstIndex(where: { $0.peerID == localPeerID }) else {
            logger.info("Pipeline \(config.id) does not include us, ignoring")
            return
        }

        activePipelines[config.id] = config
        localPipelineConfig = config
        localStageIndex = stageIdx

        logger.info("Joined pipeline \(config.id) as stage \(stageIdx): layers \(config.stages[stageIdx].startLayer)-\(config.stages[stageIdx].endLayer)")

        // Pre-load the model for our stage
        Task { await loadModelForStage(config.modelID) }

        // Process any pending activations for this pipeline
        if let pending = pendingActivations[config.id] {
            pendingActivations.removeValue(forKey: config.id)
            for (_, activation) in pending.sorted(by: { $0.key < $1.key }) {
                Task { await executeLocalStage(activation, config: config) }
            }
        }
    }

    private func handleActivation(_ data: Data, fromPeer: String, channelID: String) {
        guard let activation = ChorusActivation.from(payload: data) else { return }

        guard let config = activePipelines[activation.pipelineID] else {
            // Config hasn't arrived yet — queue the activation
            if pendingActivations[activation.pipelineID] == nil {
                pendingActivations[activation.pipelineID] = [:]
            }
            pendingActivations[activation.pipelineID]?[activation.inputIndex] = activation
            logger.info("Queued activation for pipeline \(activation.pipelineID) (config pending)")
            return
        }

        Task { await executeLocalStage(activation, config: config) }
    }

    private func handleResult(_ data: Data, fromPeer: String) {
        guard let result = ChorusResult.from(payload: data) else { return }

        if completedResults[result.pipelineID] == nil {
            completedResults[result.pipelineID] = [:]
        }
        completedResults[result.pipelineID]?[result.inputIndex] = result

        logger.info("Received result for pipeline \(result.pipelineID), input \(result.inputIndex)")
    }

    // MARK: - Private: Stage Execution

    /// Execute this device's pipeline stage on an incoming activation.
    private func executeLocalStage(_ activation: ChorusActivation, config: ChorusPipelineConfig) async {
        guard let stageIdx = config.stages.firstIndex(where: { $0.peerID == localPeerID }) else {
            return
        }

        let stage = config.stages[stageIdx]

        logger.info("Executing stage \(stageIdx) (layers \(stage.startLayer)-\(stage.endLayer)) for input \(activation.inputIndex)")

        // Ensure model is loaded
        if loadedModel == nil {
            await loadModelForStage(config.modelID)
        }

        guard let model = loadedModel else {
            logger.error("Failed to load model \(config.modelID) for stage execution")
            return
        }

        do {
            // Create input feature from tensor data
            let elementCount = activation.tensorData.count / (activation.dataType == .float16 ? 2 : 4)
            let shapeNS = activation.shape.isEmpty
                ? [NSNumber(value: elementCount)]
                : activation.shape.map { NSNumber(value: $0) }

            let multiArray = try MLMultiArray(
                dataPointer: UnsafeMutableRawPointer(mutating: (activation.tensorData as NSData).bytes),
                shape: shapeNS,
                dataType: activation.dataType == .float16 ? .float16 : .float32,
                strides: computeStrides(shape: shapeNS)
            )

            let input = try MLDictionaryFeatureProvider(dictionary: ["input": multiArray])
            // MLModel is not Sendable but prediction is read-only — safe to cross isolation.
            nonisolated(unsafe) let unsafeModel = model
            let prediction = try await unsafeModel.prediction(from: input)

            // Serialize output tensor
            var outputData = Data()
            var outputShape: [Int] = []
            for featureName in prediction.featureNames {
                if let array = prediction.featureValue(for: featureName)?.multiArrayValue {
                    let byteCount = array.count * (activation.dataType == .float16 ? 2 : 4)
                    outputData.append(Data(bytes: array.dataPointer, count: byteCount))
                    outputShape = (0..<array.shape.count).map { array.shape[$0].intValue }
                }
            }

            let isLastStage = stageIdx == config.stages.count - 1

            if isLastStage {
                // Final stage — emit result
                let result = ChorusResult(
                    pipelineID: config.id,
                    inputIndex: activation.inputIndex,
                    resultData: outputData,
                    timestamp: Date()
                )

                if completedResults[config.id] == nil {
                    completedResults[config.id] = [:]
                }
                completedResults[config.id]?[activation.inputIndex] = result

                // Send result back to pipeline originator
                if let payload = try? result.wirePayload() {
                    onSendPacket?(payload, "")
                }

                logger.info("Pipeline \(config.id) input \(activation.inputIndex) complete")
            } else {
                // Forward activation to next stage
                let nextStage = config.stages[stageIdx + 1]
                let nextActivation = ChorusActivation(
                    pipelineID: config.id,
                    stageIndex: UInt8(clamping: stageIdx + 1),
                    inputIndex: activation.inputIndex,
                    tensorData: outputData,
                    shape: outputShape,
                    dataType: activation.dataType
                )

                let payload = nextActivation.wirePayload()
                onSendPacket?(payload, nextStage.peerID)

                logger.info("Forwarded activation to stage \(stageIdx + 1) (\(nextStage.peerID))")
            }

        } catch {
            logger.error("Stage \(stageIdx) execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Model Loading

    /// Load a CoreML model for local pipeline stage execution.
    private func loadModelForStage(_ modelID: String) async {
        guard localStageModel != modelID else { return }

        // Check app bundle
        var modelURL: URL?
        if let bundleURL = Bundle.main.url(forResource: modelID, withExtension: "mlmodelc") {
            modelURL = bundleURL
        } else {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let docsURL = docsDir.appendingPathComponent("\(modelID).mlmodelc")
            if FileManager.default.fileExists(atPath: docsURL.path) {
                modelURL = docsURL
            }
        }

        guard let url = modelURL else {
            logger.error("Model \(modelID) not found in bundle or documents")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            loadedModel = try MLModel(contentsOf: url, configuration: config)
            localStageModel = modelID
            logger.info("Loaded model \(modelID) for pipeline stage")
        } catch {
            logger.error("Failed to load model \(modelID): \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Helpers

    /// Build a local pipeline offer based on current device state.
    private func buildLocalOffer(modelID: String) -> ChorusPipelineOffer {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        let availableMemory = Int(os_proc_available_memory() / (1024 * 1024))

        // Rough compute estimate: memory-based heuristic (1 TFLOPS per 2GB)
        let computeEstimate = max(1, availableMemory / 2048)

        return ChorusPipelineOffer(
            peerID: localPeerID,
            modelID: modelID,
            availableMemoryMB: availableMemory,
            computeCapability: computeEstimate,
            batteryLevel: device.batteryLevel,
            isCharging: device.batteryState == .charging || device.batteryState == .full
        )
    }

    /// Check whether a peer's offer meets minimum health requirements.
    private func isOfferHealthy(_ offer: ChorusPipelineOffer) -> Bool {
        if offer.batteryLevel >= 0, offer.batteryLevel < Self.minimumBattery, !offer.isCharging {
            return false
        }
        return true
    }

    /// Estimate layer count for a model (used for pipeline partitioning).
    ///
    /// In production this would inspect the model's metadata or architecture.
    /// For now, uses conservative defaults based on common model families.
    private func estimateModelLayers(modelID: String) -> Int {
        // Check for model metadata in documents directory
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let metaURL = docsDir.appendingPathComponent("\(modelID).layers.json")

        if let data = try? Data(contentsOf: metaURL),
           let count = try? JSONDecoder().decode(Int.self, from: data) {
            return count
        }

        // Fallback heuristics based on model name patterns
        let lowered = modelID.lowercased()
        if lowered.contains("7b") { return 32 }
        if lowered.contains("13b") { return 40 }
        if lowered.contains("70b") { return 80 }
        if lowered.contains("large") { return 24 }
        if lowered.contains("small") { return 12 }

        return 16 // Conservative default
    }

    /// Compute C-contiguous strides for an N-dimensional shape.
    private func computeStrides(shape: [NSNumber]) -> [NSNumber] {
        guard !shape.isEmpty else { return [] }
        var strides = [NSNumber](repeating: NSNumber(value: 1), count: shape.count)
        for i in stride(from: shape.count - 2, through: 0, by: -1) {
            strides[i] = NSNumber(value: strides[i + 1].intValue * shape[i + 1].intValue)
        }
        return strides
    }
}

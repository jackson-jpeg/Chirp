import XCTest
@testable import Chirp

final class ChorusTests: XCTestCase {

    // MARK: - ChorusActivation binary wire round-trip

    func testChorusActivationWireRoundTrip() {
        let pipelineID = UUID()
        let tensorData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

        let activation = ChorusActivation(
            pipelineID: pipelineID,
            stageIndex: 3,
            inputIndex: 42,
            tensorData: tensorData,
            shape: [1, 768, 128],
            dataType: .float32
        )

        let payload = activation.wirePayload()
        let decoded = ChorusActivation.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.pipelineID, pipelineID)
        XCTAssertEqual(decoded?.stageIndex, 3)
        XCTAssertEqual(decoded?.inputIndex, 42)
        XCTAssertEqual(decoded?.tensorData, tensorData)
        XCTAssertEqual(decoded?.shape, [1, 768, 128])
        XCTAssertEqual(decoded?.dataType, .float32)
    }

    func testChorusActivationFloat16DataType() {
        let activation = ChorusActivation(
            pipelineID: UUID(),
            stageIndex: 0,
            inputIndex: 0,
            tensorData: Data(repeating: 0xAA, count: 16),
            shape: [4, 4],
            dataType: .float16
        )

        let payload = activation.wirePayload()
        let decoded = ChorusActivation.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.dataType, .float16)
        XCTAssertEqual(decoded?.shape, [4, 4])
    }

    func testChorusActivationEmptyTensorData() {
        let activation = ChorusActivation(
            pipelineID: UUID(),
            stageIndex: 1,
            inputIndex: 100,
            tensorData: Data(),
            shape: [],
            dataType: .float32
        )

        let payload = activation.wirePayload()
        let decoded = ChorusActivation.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.tensorData, Data())
        XCTAssertEqual(decoded?.shape, [])
    }

    func testChorusActivationMagicPrefix() {
        let activation = ChorusActivation(
            pipelineID: UUID(),
            stageIndex: 0,
            inputIndex: 0,
            tensorData: Data(),
            shape: [],
            dataType: .float32
        )

        let payload = activation.wirePayload()

        // CHR! = 0x43, 0x48, 0x52, 0x21
        XCTAssertEqual(payload[0], 0x43)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x52)
        XCTAssertEqual(payload[3], 0x21)
    }

    func testChorusActivationFromTooShortReturnsNil() {
        let data = Data(repeating: 0x00, count: 10)
        XCTAssertNil(ChorusActivation.from(payload: data))
    }

    func testChorusActivationFromWrongMagicReturnsNil() {
        var data = Data(repeating: 0x00, count: 30)
        data[0] = 0xFF // wrong magic
        XCTAssertNil(ChorusActivation.from(payload: data))
    }

    // MARK: - ChorusPipelineOffer Codable round-trip

    func testChorusPipelineOfferWireRoundTrip() throws {
        let offer = ChorusPipelineOffer(
            peerID: "peer-A",
            modelID: "llama-7b",
            availableMemoryMB: 4096,
            computeCapability: 12,
            batteryLevel: 0.92,
            isCharging: true
        )

        let payload = try offer.wirePayload()
        let decoded = ChorusPipelineOffer.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.peerID, "peer-A")
        XCTAssertEqual(decoded?.modelID, "llama-7b")
        XCTAssertEqual(decoded?.availableMemoryMB, 4096)
        XCTAssertEqual(decoded?.computeCapability, 12)
        XCTAssertEqual(decoded?.batteryLevel ?? 0, 0.92, accuracy: 0.01)
        XCTAssertEqual(decoded?.isCharging, true)
    }

    func testChorusPipelineOfferMagicPrefix() throws {
        let offer = ChorusPipelineOffer(
            peerID: "peer-A",
            modelID: "model",
            availableMemoryMB: 1024,
            computeCapability: 5,
            batteryLevel: 0.5,
            isCharging: false
        )

        let payload = try offer.wirePayload()

        // CHO! = 0x43, 0x48, 0x4F, 0x21
        XCTAssertEqual(payload[0], 0x43)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x4F)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - ChorusPipelineConfig Codable round-trip

    func testChorusPipelineConfigWireRoundTrip() throws {
        let config = ChorusPipelineConfig(
            id: UUID(),
            modelID: "llama-7b",
            stages: [
                ChorusPipelineConfig.PipelineStage(peerID: "peer-A", startLayer: 0, endLayer: 15),
                ChorusPipelineConfig.PipelineStage(peerID: "peer-B", startLayer: 16, endLayer: 31),
            ],
            totalLayers: 32
        )

        let payload = try config.wirePayload()
        let decoded = ChorusPipelineConfig.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, config.id)
        XCTAssertEqual(decoded?.modelID, "llama-7b")
        XCTAssertEqual(decoded?.totalLayers, 32)
        XCTAssertEqual(decoded?.stages.count, 2)
        XCTAssertEqual(decoded?.stages[0].peerID, "peer-A")
        XCTAssertEqual(decoded?.stages[0].startLayer, 0)
        XCTAssertEqual(decoded?.stages[0].endLayer, 15)
        XCTAssertEqual(decoded?.stages[1].peerID, "peer-B")
        XCTAssertEqual(decoded?.stages[1].startLayer, 16)
        XCTAssertEqual(decoded?.stages[1].endLayer, 31)
    }

    func testChorusPipelineConfigMagicPrefix() throws {
        let config = ChorusPipelineConfig(
            id: UUID(),
            modelID: "model",
            stages: [],
            totalLayers: 0
        )

        let payload = try config.wirePayload()

        // CHC! = 0x43, 0x48, 0x43, 0x21
        XCTAssertEqual(payload[0], 0x43)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x43)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - ChorusResult wire round-trip

    func testChorusResultWireRoundTrip() throws {
        let result = ChorusResult(
            pipelineID: UUID(),
            inputIndex: 99,
            resultData: Data("inference output".utf8),
            timestamp: Date()
        )

        let payload = try result.wirePayload()
        let decoded = ChorusResult.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.pipelineID, result.pipelineID)
        XCTAssertEqual(decoded?.inputIndex, 99)
        XCTAssertEqual(decoded?.resultData, Data("inference output".utf8))
    }

    func testChorusResultMagicPrefix() throws {
        let result = ChorusResult(
            pipelineID: UUID(),
            inputIndex: 0,
            resultData: Data(),
            timestamp: Date()
        )

        let payload = try result.wirePayload()

        // CHX! = 0x43, 0x48, 0x58, 0x21
        XCTAssertEqual(payload[0], 0x43)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x58)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - Invalid payloads

    func testChorusPipelineOfferFromGarbageReturnsNil() {
        XCTAssertNil(ChorusPipelineOffer.from(payload: Data([0xFF, 0xFE])))
    }

    func testChorusPipelineConfigFromGarbageReturnsNil() {
        XCTAssertNil(ChorusPipelineConfig.from(payload: Data([0xFF, 0xFE])))
    }

    func testChorusResultFromGarbageReturnsNil() {
        XCTAssertNil(ChorusResult.from(payload: Data([0xFF, 0xFE])))
    }
}

import XCTest
@testable import Chirp

final class SwarmTests: XCTestCase {

    // MARK: - SwarmWorkUnit wire round-trip

    func testSwarmWorkUnitWireRoundTrip() throws {
        let unit = SwarmWorkUnit(
            id: UUID(),
            jobID: UUID(),
            unitIndex: 42,
            assignedPeerID: "peer-A",
            modelID: "distilbert-base",
            inputData: Data("input tensor data".utf8),
            timestamp: Date()
        )

        let payload = try unit.wirePayload()
        let decoded = SwarmWorkUnit.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, unit.id)
        XCTAssertEqual(decoded?.jobID, unit.jobID)
        XCTAssertEqual(decoded?.unitIndex, 42)
        XCTAssertEqual(decoded?.assignedPeerID, "peer-A")
        XCTAssertEqual(decoded?.modelID, "distilbert-base")
        XCTAssertEqual(decoded?.inputData, Data("input tensor data".utf8))
    }

    func testSwarmWorkUnitMagicPrefixAndSubType() throws {
        let unit = SwarmWorkUnit(
            id: UUID(),
            jobID: UUID(),
            unitIndex: 0,
            assignedPeerID: "peer-A",
            modelID: "model-1",
            inputData: Data(),
            timestamp: Date()
        )

        let payload = try unit.wirePayload()

        // SWM! = 0x53, 0x57, 0x4D, 0x21
        XCTAssertEqual(payload[0], 0x53)
        XCTAssertEqual(payload[1], 0x57)
        XCTAssertEqual(payload[2], 0x4D)
        XCTAssertEqual(payload[3], 0x21)
        // Sub-type byte: 0x01 = work unit
        XCTAssertEqual(payload[4], 0x01)
    }

    // MARK: - SwarmWorkResult wire round-trip

    func testSwarmWorkResultWireRoundTrip() throws {
        let result = SwarmWorkResult(
            jobID: UUID(),
            unitIndex: 7,
            workerPeerID: "peer-B",
            resultData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            computeTimeMs: 1234,
            timestamp: Date()
        )

        let payload = try result.wirePayload()
        let decoded = SwarmWorkResult.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.jobID, result.jobID)
        XCTAssertEqual(decoded?.unitIndex, 7)
        XCTAssertEqual(decoded?.workerPeerID, "peer-B")
        XCTAssertEqual(decoded?.resultData, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(decoded?.computeTimeMs, 1234)
    }

    func testSwarmWorkResultMagicPrefixAndSubType() throws {
        let result = SwarmWorkResult(
            jobID: UUID(),
            unitIndex: 0,
            workerPeerID: "peer-B",
            resultData: Data(),
            computeTimeMs: 0,
            timestamp: Date()
        )

        let payload = try result.wirePayload()

        // SWR! = 0x53, 0x57, 0x52, 0x21
        XCTAssertEqual(payload[0], 0x53)
        XCTAssertEqual(payload[1], 0x57)
        XCTAssertEqual(payload[2], 0x52)
        XCTAssertEqual(payload[3], 0x21)
        // Sub-type byte: 0x02 = work result
        XCTAssertEqual(payload[4], 0x02)
    }

    // MARK: - SwarmNodeCapability wire round-trip

    func testSwarmNodeCapabilityWireRoundTrip() throws {
        let capability = SwarmNodeCapability(
            peerID: "peer-C",
            availableModels: ["distilbert-base", "mobilenet-v2"],
            batteryLevel: 0.85,
            isCharging: true,
            thermalState: 1,
            availableMemoryMB: 2048,
            acceptsBackground: true,
            acceptsForeground: false
        )

        let payload = try capability.wirePayload()
        let decoded = SwarmNodeCapability.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.peerID, "peer-C")
        XCTAssertEqual(decoded?.availableModels, ["distilbert-base", "mobilenet-v2"])
        XCTAssertEqual(decoded?.batteryLevel ?? 0, 0.85, accuracy: 0.01)
        XCTAssertEqual(decoded?.isCharging, true)
        XCTAssertEqual(decoded?.thermalState, 1)
        XCTAssertEqual(decoded?.availableMemoryMB, 2048)
        XCTAssertEqual(decoded?.acceptsBackground, true)
        XCTAssertEqual(decoded?.acceptsForeground, false)
    }

    func testSwarmNodeCapabilityMagicPrefix() throws {
        let capability = SwarmNodeCapability(
            peerID: "peer-C",
            availableModels: [],
            batteryLevel: 0.5,
            isCharging: false,
            thermalState: 0,
            availableMemoryMB: 1024,
            acceptsBackground: false,
            acceptsForeground: false
        )

        let payload = try capability.wirePayload()

        // SWC! = 0x53, 0x57, 0x43, 0x21
        XCTAssertEqual(payload[0], 0x53)
        XCTAssertEqual(payload[1], 0x57)
        XCTAssertEqual(payload[2], 0x43)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - SwarmJobAdvertise wire round-trip

    func testSwarmJobAdvertiseWireRoundTrip() throws {
        let job = SwarmJob(
            id: UUID(),
            originatorID: "peer-D",
            modelID: "whisper-tiny",
            description: "Transcribe audio segment",
            totalUnits: 10,
            priority: .foreground,
            createdAt: Date(),
            deadline: Date().addingTimeInterval(300)
        )

        let advertise = SwarmJobAdvertise(job: job)

        let payload = try advertise.wirePayload()
        let decoded = SwarmJobAdvertise.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.job.id, job.id)
        XCTAssertEqual(decoded?.job.originatorID, "peer-D")
        XCTAssertEqual(decoded?.job.modelID, "whisper-tiny")
        XCTAssertEqual(decoded?.job.description, "Transcribe audio segment")
        XCTAssertEqual(decoded?.job.totalUnits, 10)
        XCTAssertEqual(decoded?.job.priority, .foreground)
    }

    func testSwarmJobAdvertiseMagicPrefix() throws {
        let job = SwarmJob(
            id: UUID(),
            originatorID: "peer-D",
            modelID: "model-1",
            description: "Test",
            totalUnits: 1,
            priority: .background,
            createdAt: Date(),
            deadline: nil
        )

        let payload = try SwarmJobAdvertise(job: job).wirePayload()

        // SWA! = 0x53, 0x57, 0x41, 0x21
        XCTAssertEqual(payload[0], 0x53)
        XCTAssertEqual(payload[1], 0x57)
        XCTAssertEqual(payload[2], 0x41)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - Invalid payloads

    func testSwarmWorkUnitFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(SwarmWorkUnit.from(payload: garbage))
    }

    func testSwarmWorkResultFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(SwarmWorkResult.from(payload: garbage))
    }

    func testSwarmNodeCapabilityFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(SwarmNodeCapability.from(payload: garbage))
    }

    func testSwarmJobAdvertiseFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(SwarmJobAdvertise.from(payload: garbage))
    }

    func testSwarmWorkUnitSubTypeMismatchReturnsNil() throws {
        // Build a payload with SWM! prefix but wrong sub-type
        let unit = SwarmWorkUnit(
            id: UUID(),
            jobID: UUID(),
            unitIndex: 0,
            assignedPeerID: "peer-A",
            modelID: "model-1",
            inputData: Data(),
            timestamp: Date()
        )

        var payload = try unit.wirePayload()
        // Change sub-type byte from 0x01 to 0x02
        payload[4] = 0x02

        XCTAssertNil(SwarmWorkUnit.from(payload: payload))
    }
}

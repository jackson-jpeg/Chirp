import XCTest
@testable import Chirp

/// Fuzz-style tests to verify all control packet handlers survive malformed input
/// without crashing. Each test sends truncated, empty, and garbage payloads through
/// the handler's deserialization path.
@MainActor final class DeserializationFuzzTests: XCTestCase {

    // MARK: - Malformed Payload Generators

    private let payloads: [Data] = [
        Data(),                                     // empty
        Data([0x00]),                               // single byte
        Data([0xFF, 0xFF, 0xFF, 0xFF]),             // 4 bytes garbage
        Data(repeating: 0x00, count: 5),            // 5 null bytes
        Data(repeating: 0xAA, count: 23),           // just over FileChunk min
        Data(repeating: 0xFF, count: 100),          // medium garbage
        Data(repeating: 0x00, count: 1000),         // large null payload
    ]

    /// Build payloads with a valid magic prefix but garbage body
    private func prefixedPayloads(_ magic: [UInt8]) -> [Data] {
        let prefix = Data(magic)
        return [
            prefix,                                              // prefix only, no body
            prefix + Data([0x00]),                                // prefix + 1 byte
            prefix + Data(repeating: 0xFF, count: 4),            // prefix + 4 garbage
            prefix + Data(repeating: 0x00, count: 16),           // prefix + 16 null
            prefix + Data(repeating: 0xAB, count: 100),          // prefix + 100 garbage
        ]
    }

    // MARK: - Text Message (TXT!)

    func testTextMessageSurvivesMalformed() {
        let service = TextMessageService()
        for payload in payloads + prefixedPayloads([0x54, 0x58, 0x54, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - File Transfer (FIL! / FLC! / FNK!)

    func testFileChunkSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x46, 0x49, 0x4C, 0x21]) {
            let result = FileChunk.from(payload: payload)
            // Should return nil, never crash
            _ = result
        }
    }

    func testFileChunkRequestSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x46, 0x4E, 0x4B, 0x21]) {
            let result = try? JSONDecoder().decode(FileChunkRequest.self, from: payload)
            _ = result
        }
    }

    // MARK: - BLE Scan Report (SCN!)

    func testBLEScanReportSurvivesMalformed() {
        let scanner = BLEScanner()
        for payload in payloads + prefixedPayloads([0x53, 0x43, 0x4E, 0x21]) {
            scanner.handleMeshScanReport(payload)
        }
    }

    // MARK: - Sound Alert (SND!)

    func testSoundAlertSurvivesMalformed() {
        let service = SoundAlertService(locationService: LocationService())
        for payload in payloads + prefixedPayloads([0x53, 0x4E, 0x44, 0x21]) {
            service.handleMeshAlert(payload)
        }
    }

    // MARK: - Emergency SOS (SOS!)

    func testSOSBeaconSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x53, 0x4F, 0x53, 0x21]) {
            EmergencyBeacon.shared.handleReceivedSOSData(payload)
        }
    }

    // MARK: - Chorus (CHR!)

    func testChorusActivationSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x43, 0x48, 0x52, 0x21]) {
            let result = ChorusActivation.from(payload: payload)
            _ = result
        }
    }

    // MARK: - Floor Control (JSON, no prefix)

    func testFloorControlSurvivesMalformed() {
        for payload in payloads {
            let result = try? MeshCodable.decoder.decode(FloorControlMessage.self, from: payload)
            _ = result
        }
    }

    // MARK: - Mesh Cloud (BCK! / BRQ!)

    func testMeshCloudSurvivesMalformed() {
        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fingerprint")
        for payload in payloads + prefixedPayloads([0x42, 0x43, 0x4B, 0x21]) {
            service.handleBackupChunk(payload)
        }
        for payload in payloads + prefixedPayloads([0x42, 0x52, 0x51, 0x21]) {
            service.handleRetrievalRequest(payload)
        }
    }

    // MARK: - Lighthouse (LHQ! / LHR!)

    func testLighthouseSurvivesMalformed() {
        let service = LighthouseService()
        for payload in payloads + prefixedPayloads([0x4C, 0x48, 0x51, 0x21]) {
            service.handlePacket(payload)
        }
        for payload in payloads + prefixedPayloads([0x4C, 0x48, 0x52, 0x21]) {
            service.handlePacket(payload)
        }
    }

    // MARK: - Witness (WRQ! / WCS!)

    func testWitnessSurvivesMalformed() {
        let service = MeshWitnessService()
        for payload in payloads + prefixedPayloads([0x57, 0x52, 0x51, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
        for payload in payloads + prefixedPayloads([0x57, 0x43, 0x53, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - Dead Drop (DRP! / DPK!)

    func testDeadDropSurvivesMalformed() {
        let service = DeadDropService()
        for payload in payloads + prefixedPayloads([0x44, 0x52, 0x50, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - Darkroom (DRK! / DVK!)

    func testDarkroomSurvivesMalformed() {
        let service = DarkroomService()
        for payload in payloads + prefixedPayloads([0x44, 0x52, 0x4B, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - Babel (BBL!)

    func testBabelSurvivesMalformed() {
        let service = BabelService()
        for payload in payloads + prefixedPayloads([0x42, 0x42, 0x4C, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - Swarm (SWM!)

    func testSwarmSurvivesMalformed() {
        let service = SwarmService(localPeerID: "test-peer")
        for payload in payloads + prefixedPayloads([0x53, 0x57, 0x4D, 0x21]) {
            service.handlePacket(payload, fromPeer: "test-peer", channelID: "test")
        }
    }
}

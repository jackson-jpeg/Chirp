import XCTest
@testable import Chirp

final class LighthouseTests: XCTestCase {

    // MARK: - Helpers

    private func makeSampleFingerprint() -> WiFiFingerprint {
        WiFiFingerprint(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracyMeters: 5.0,
            floorLevel: 2,
            observations: [
                RadioObservation(
                    identifier: "AA:BB:CC:DD:EE:FF",
                    type: .wifi,
                    rssi: -65,
                    ssid: "TestNetwork",
                    channel: 6
                ),
                RadioObservation(
                    identifier: "11:22:33:44:55:66",
                    type: .bleBeacon,
                    rssi: -72,
                    ssid: nil,
                    channel: nil
                ),
            ],
            contributorPeerID: "peer-A"
        )
    }

    // MARK: - LighthousePacket.Query wire round-trip

    func testLighthouseQueryWireRoundTrip() {
        let query = LighthousePacket.Query(
            requestID: UUID(),
            geohashPrefix: "u4pru",
            requestorPeerID: "peer-A",
            timestamp: Date()
        )

        let payload = query.wirePayload()
        let decoded = LighthousePacket.Query.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.requestID, query.requestID)
        XCTAssertEqual(decoded?.geohashPrefix, "u4pru")
        XCTAssertEqual(decoded?.requestorPeerID, "peer-A")
    }

    func testLighthouseQueryMagicPrefix() {
        let query = LighthousePacket.Query(
            requestID: UUID(),
            geohashPrefix: "u4pr",
            requestorPeerID: "peer-A",
            timestamp: Date()
        )

        let payload = query.wirePayload()

        // LHQ! = 0x4C, 0x48, 0x51, 0x21
        XCTAssertEqual(payload[0], 0x4C)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x51)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - LighthousePacket.Record wire round-trip

    func testLighthouseRecordWireRoundTrip() {
        let fingerprint = makeSampleFingerprint()

        let record = LighthousePacket.Record(
            requestID: UUID(),
            regionHash: "u4pruyd",
            fingerprints: [fingerprint],
            breadcrumbCount: 42,
            version: 3,
            lastUpdated: Date()
        )

        let payload = record.wirePayload()
        let decoded = LighthousePacket.Record.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.requestID, record.requestID)
        XCTAssertEqual(decoded?.regionHash, "u4pruyd")
        XCTAssertEqual(decoded?.fingerprints.count, 1)
        XCTAssertEqual(decoded?.breadcrumbCount, 42)
        XCTAssertEqual(decoded?.version, 3)
    }

    func testLighthouseRecordMagicPrefix() {
        let record = LighthousePacket.Record(
            requestID: UUID(),
            regionHash: "u4pr",
            fingerprints: [],
            breadcrumbCount: 0,
            version: 1,
            lastUpdated: Date()
        )

        let payload = record.wirePayload()

        // LHR! = 0x4C, 0x48, 0x52, 0x21
        XCTAssertEqual(payload[0], 0x4C)
        XCTAssertEqual(payload[1], 0x48)
        XCTAssertEqual(payload[2], 0x52)
        XCTAssertEqual(payload[3], 0x21)
    }

    func testLighthouseRecordWithMultipleFingerprints() {
        let fp1 = makeSampleFingerprint()
        let fp2 = WiFiFingerprint(
            latitude: 37.7750,
            longitude: -122.4195,
            accuracyMeters: 8.0,
            floorLevel: nil,
            observations: [],
            contributorPeerID: "peer-B"
        )

        let record = LighthousePacket.Record(
            requestID: UUID(),
            regionHash: "u4pruyd",
            fingerprints: [fp1, fp2],
            breadcrumbCount: 10,
            version: 2,
            lastUpdated: Date()
        )

        let payload = record.wirePayload()
        let decoded = LighthousePacket.Record.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.fingerprints.count, 2)
    }

    // MARK: - RadioObservation Codable round-trip

    func testRadioObservationCodableRoundTripWifi() throws {
        let observation = RadioObservation(
            identifier: "AA:BB:CC:DD:EE:FF",
            type: .wifi,
            rssi: -55,
            ssid: "MyNetwork",
            channel: 11
        )

        let data = try MeshCodable.encoder.encode(observation)
        let decoded = try MeshCodable.decoder.decode(RadioObservation.self, from: data)

        XCTAssertEqual(decoded.identifier, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(decoded.type, .wifi)
        XCTAssertEqual(decoded.rssi, -55)
        XCTAssertEqual(decoded.ssid, "MyNetwork")
        XCTAssertEqual(decoded.channel, 11)
    }

    func testRadioObservationCodableRoundTripBLE() throws {
        let observation = RadioObservation(
            identifier: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0",
            type: .bleBeacon,
            rssi: -80,
            ssid: nil,
            channel: nil
        )

        let data = try MeshCodable.encoder.encode(observation)
        let decoded = try MeshCodable.decoder.decode(RadioObservation.self, from: data)

        XCTAssertEqual(decoded.identifier, "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
        XCTAssertEqual(decoded.type, .bleBeacon)
        XCTAssertEqual(decoded.rssi, -80)
        XCTAssertNil(decoded.ssid)
        XCTAssertNil(decoded.channel)
    }

    // MARK: - WiFiFingerprint Codable round-trip

    func testWiFiFingerprintCodableRoundTrip() throws {
        let fingerprint = makeSampleFingerprint()

        let data = try MeshCodable.encoder.encode(fingerprint)
        let decoded = try MeshCodable.decoder.decode(WiFiFingerprint.self, from: data)

        XCTAssertEqual(decoded.id, fingerprint.id)
        XCTAssertEqual(decoded.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(decoded.accuracyMeters, 5.0, accuracy: 0.01)
        XCTAssertEqual(decoded.floorLevel, 2)
        XCTAssertEqual(decoded.observations.count, 2)
        XCTAssertEqual(decoded.contributorPeerID, "peer-A")
    }

    // MARK: - Invalid payloads

    func testLighthouseQueryFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(LighthousePacket.Query.from(payload: garbage))
    }

    func testLighthouseRecordFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(LighthousePacket.Record.from(payload: garbage))
    }

    func testLighthouseQueryFromTooShortReturnsNil() {
        let data = Data([0x4C, 0x48, 0x51, 0x21]) // Just prefix
        XCTAssertNil(LighthousePacket.Query.from(payload: data))
    }

    func testLighthouseRecordFromTooShortReturnsNil() {
        let data = Data([0x4C, 0x48, 0x52, 0x21]) // Just prefix
        XCTAssertNil(LighthousePacket.Record.from(payload: data))
    }
}

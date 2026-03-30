import XCTest
@testable import Chirp

final class WitnessTests: XCTestCase {

    // MARK: - WitnessRequest wire round-trip

    func testWitnessRequestWireRoundTrip() {
        let request = WitnessRequest(
            id: UUID(),
            mediaHash: Data(repeating: 0xAB, count: 32),
            mediaType: .photo,
            originPeerID: "peer-A",
            originPublicKey: Data(repeating: 0x01, count: 32),
            originSignature: Data(repeating: 0x02, count: 64),
            originTimestamp: Date(),
            originLocation: LocationStamp(
                latitude: 37.7749,
                longitude: -122.4194,
                horizontalAccuracy: 5.0,
                altitude: 10.0,
                timestamp: Date()
            )
        )

        let payload = request.wirePayload()
        XCTAssertNotNil(payload)

        let decoded = WitnessRequest.from(payload: payload!)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, request.id)
        XCTAssertEqual(decoded?.mediaHash, request.mediaHash)
        XCTAssertEqual(decoded?.mediaType, .photo)
        XCTAssertEqual(decoded?.originPeerID, "peer-A")
        XCTAssertEqual(decoded?.originPublicKey, request.originPublicKey)
        XCTAssertEqual(decoded?.originSignature, request.originSignature)
        XCTAssertNotNil(decoded?.originLocation)
        XCTAssertEqual(decoded?.originLocation?.latitude ?? 0, 37.7749, accuracy: 0.0001)
    }

    func testWitnessRequestWithNilLocation() {
        let request = WitnessRequest(
            id: UUID(),
            mediaHash: Data(repeating: 0xCD, count: 32),
            mediaType: .audio,
            originPeerID: "peer-B",
            originPublicKey: Data(repeating: 0x03, count: 32),
            originSignature: Data(repeating: 0x04, count: 64),
            originTimestamp: Date(),
            originLocation: nil
        )

        let payload = request.wirePayload()!
        let decoded = WitnessRequest.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.originLocation)
        XCTAssertEqual(decoded?.mediaType, .audio)
    }

    // MARK: - WitnessCountersign wire round-trip

    func testWitnessCountersignWireRoundTrip() {
        let countersign = WitnessCountersign(
            id: UUID(),
            witnessSessionID: UUID(),
            mediaHash: Data(repeating: 0xEF, count: 32),
            counterSignerPeerID: "peer-C",
            counterSignerPublicKey: Data(repeating: 0x05, count: 32),
            signature: Data(repeating: 0x06, count: 64),
            timestamp: Date(),
            location: LocationStamp(
                latitude: 51.5074,
                longitude: -0.1278,
                horizontalAccuracy: 8.0,
                altitude: nil,
                timestamp: Date()
            )
        )

        let payload = countersign.wirePayload()
        XCTAssertNotNil(payload)

        let decoded = WitnessCountersign.from(payload: payload!)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, countersign.id)
        XCTAssertEqual(decoded?.witnessSessionID, countersign.witnessSessionID)
        XCTAssertEqual(decoded?.mediaHash, countersign.mediaHash)
        XCTAssertEqual(decoded?.counterSignerPeerID, "peer-C")
        XCTAssertEqual(decoded?.counterSignerPublicKey, countersign.counterSignerPublicKey)
        XCTAssertEqual(decoded?.signature, countersign.signature)
    }

    // MARK: - Magic prefix bytes

    func testWitnessRequestMagicPrefix() {
        let request = WitnessRequest(
            id: UUID(),
            mediaHash: Data(repeating: 0x00, count: 32),
            mediaType: .video,
            originPeerID: "peer-X",
            originPublicKey: Data(repeating: 0x00, count: 32),
            originSignature: Data(repeating: 0x00, count: 64),
            originTimestamp: Date(),
            originLocation: nil
        )

        let payload = request.wirePayload()!

        // WRQ! = 0x57, 0x52, 0x51, 0x21
        XCTAssertEqual(payload[0], 0x57)
        XCTAssertEqual(payload[1], 0x52)
        XCTAssertEqual(payload[2], 0x51)
        XCTAssertEqual(payload[3], 0x21)
    }

    func testWitnessCountersignMagicPrefix() {
        let countersign = WitnessCountersign(
            id: UUID(),
            witnessSessionID: UUID(),
            mediaHash: Data(repeating: 0x00, count: 32),
            counterSignerPeerID: "peer-Y",
            counterSignerPublicKey: Data(repeating: 0x00, count: 32),
            signature: Data(repeating: 0x00, count: 64),
            timestamp: Date(),
            location: nil
        )

        let payload = countersign.wirePayload()!

        // WCS! = 0x57, 0x43, 0x53, 0x21
        XCTAssertEqual(payload[0], 0x57)
        XCTAssertEqual(payload[1], 0x43)
        XCTAssertEqual(payload[2], 0x53)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - LocationStamp Codable round-trip

    func testLocationStampCodableRoundTrip() throws {
        let stamp = LocationStamp(
            latitude: 48.8566,
            longitude: 2.3522,
            horizontalAccuracy: 3.0,
            altitude: 35.5,
            timestamp: Date()
        )

        let data = try MeshCodable.encoder.encode(stamp)
        let decoded = try MeshCodable.decoder.decode(LocationStamp.self, from: data)

        XCTAssertEqual(decoded.latitude, stamp.latitude, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, stamp.longitude, accuracy: 0.0001)
        XCTAssertEqual(decoded.horizontalAccuracy, stamp.horizontalAccuracy, accuracy: 0.01)
        XCTAssertEqual(decoded.altitude, stamp.altitude)
    }

    func testLocationStampCodableWithNilAltitude() throws {
        let stamp = LocationStamp(
            latitude: 35.6762,
            longitude: 139.6503,
            horizontalAccuracy: 10.0,
            altitude: nil,
            timestamp: Date()
        )

        let data = try MeshCodable.encoder.encode(stamp)
        let decoded = try MeshCodable.decoder.decode(LocationStamp.self, from: data)

        XCTAssertNil(decoded.altitude)
    }

    // MARK: - Invalid payloads

    func testWitnessRequestFromGarbageReturnsNil() {
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB])
        XCTAssertNil(WitnessRequest.from(payload: garbage))
    }

    func testWitnessCountersignFromGarbageReturnsNil() {
        let garbage = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB])
        XCTAssertNil(WitnessCountersign.from(payload: garbage))
    }
}

import XCTest
import simd
@testable import Chirp

final class UWBTests: XCTestCase {

    // MARK: - UWBTokenExchange wire round-trip

    func testUWBTokenExchangeWireRoundTrip() {
        let exchange = UWBTokenExchange(
            peerID: "peer-A",
            discoveryToken: Data(repeating: 0xAB, count: 32),
            timestamp: Date()
        )

        let payload = exchange.wirePayload()
        let decoded = UWBTokenExchange.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.peerID, "peer-A")
        XCTAssertEqual(decoded?.discoveryToken, Data(repeating: 0xAB, count: 32))
    }

    // MARK: - Magic prefix

    func testUWBTokenExchangeMagicPrefix() {
        let exchange = UWBTokenExchange(
            peerID: "peer-A",
            discoveryToken: Data(),
            timestamp: Date()
        )

        let payload = exchange.wirePayload()

        // UWB! = 0x55, 0x57, 0x42, 0x21
        XCTAssertEqual(payload[0], 0x55)
        XCTAssertEqual(payload[1], 0x57)
        XCTAssertEqual(payload[2], 0x42)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - UWBMeasurement direction reconstruction

    func testUWBMeasurementDirectionReconstruction() {
        let direction = SIMD3<Float>(0.5, 0.7, -0.3)
        let measurement = UWBMeasurement(
            localPeerID: "peer-A",
            remotePeerID: "peer-B",
            distanceMeters: 2.5,
            direction: direction
        )

        let reconstructed = measurement.direction

        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.x ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(reconstructed?.y ?? 0, 0.7, accuracy: 0.001)
        XCTAssertEqual(reconstructed?.z ?? 0, -0.3, accuracy: 0.001)
    }

    func testUWBMeasurementDirectionNilWhenNoComponents() {
        let measurement = UWBMeasurement(
            localPeerID: "peer-A",
            remotePeerID: "peer-B",
            distanceMeters: 3.0,
            direction: nil
        )

        XCTAssertNil(measurement.direction)
        XCTAssertNil(measurement.directionX)
        XCTAssertNil(measurement.directionY)
        XCTAssertNil(measurement.directionZ)
    }

    func testUWBMeasurementDistanceStored() {
        let measurement = UWBMeasurement(
            localPeerID: "peer-A",
            remotePeerID: "peer-B",
            distanceMeters: 5.75,
            direction: SIMD3<Float>(1, 0, 0)
        )

        XCTAssertEqual(measurement.distanceMeters, 5.75, accuracy: 0.001)
        XCTAssertEqual(measurement.localPeerID, "peer-A")
        XCTAssertEqual(measurement.remotePeerID, "peer-B")
    }

    // MARK: - UWBMeasurement Codable round-trip

    func testUWBMeasurementCodableRoundTrip() throws {
        let measurement = UWBMeasurement(
            localPeerID: "peer-A",
            remotePeerID: "peer-B",
            distanceMeters: 1.23,
            direction: SIMD3<Float>(0.1, 0.2, 0.3)
        )

        let data = try MeshCodable.encoder.encode(measurement)
        let decoded = try MeshCodable.decoder.decode(UWBMeasurement.self, from: data)

        XCTAssertEqual(decoded.localPeerID, "peer-A")
        XCTAssertEqual(decoded.remotePeerID, "peer-B")
        XCTAssertEqual(decoded.distanceMeters, 1.23, accuracy: 0.01)
        XCTAssertEqual(decoded.directionX ?? 0, 0.1, accuracy: 0.001)
        XCTAssertEqual(decoded.directionY ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(decoded.directionZ ?? 0, 0.3, accuracy: 0.001)
    }

    // MARK: - Invalid payloads

    func testUWBTokenExchangeFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(UWBTokenExchange.from(payload: garbage))
    }

    func testUWBTokenExchangeFromTooShortReturnsNil() {
        let data = Data([0x55, 0x57, 0x42, 0x21]) // Just prefix, no JSON
        XCTAssertNil(UWBTokenExchange.from(payload: data))
    }
}

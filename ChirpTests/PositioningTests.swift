import XCTest
@testable import Chirp

final class PositioningTests: XCTestCase {

    // MARK: - PositionEstimate encoded/decode round-trip

    func testEncodedRoundTrip() {
        let estimate = PositionEstimate(
            latitude: 37.774929,
            longitude: -122.419418,
            altitudeMeters: 15.0,
            horizontalAccuracyMeters: 10.0,
            source: .gps,
            confidence: 0.9,
            timestamp: Date()
        )

        let encoded = estimate.encoded
        let decoded = PositionEstimate.decode(encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.latitude ?? 0, 37.774929, accuracy: 0.000001)
        XCTAssertEqual(decoded?.longitude ?? 0, -122.419418, accuracy: 0.000001)
        XCTAssertEqual(decoded?.horizontalAccuracyMeters ?? 0, 10.0, accuracy: 0.1)
        XCTAssertEqual(decoded?.source, .gps)
    }

    func testEncodedRoundTripDeadReckoning() {
        let estimate = PositionEstimate(
            latitude: 51.507351,
            longitude: -0.127758,
            altitudeMeters: nil,
            horizontalAccuracyMeters: 25.0,
            source: .deadReckoning,
            confidence: 0.04,
            timestamp: Date()
        )

        let decoded = PositionEstimate.decode(estimate.encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.source, .deadReckoning)
    }

    // MARK: - All PositionSource cases encode/decode

    func testAllPositionSourceCasesRoundTrip() {
        let sources: [PositionEstimate.PositionSource] = [
            .gps, .uwbAnchored, .meshCorrected, .lighthouseWifi,
            .deadReckoning, .uwbRelative, .unknown
        ]

        for source in sources {
            let estimate = PositionEstimate(
                latitude: 0.0,
                longitude: 0.0,
                altitudeMeters: nil,
                horizontalAccuracyMeters: 5.0,
                source: source,
                confidence: 0.5,
                timestamp: Date()
            )

            let decoded = PositionEstimate.decode(estimate.encoded)
            XCTAssertNotNil(decoded, "Source \(source) should decode")
            XCTAssertEqual(decoded?.source, source, "Source \(source) should round-trip")
        }
    }

    // MARK: - Coordinate and accuracy preservation

    func testCoordinatePreservation() {
        let estimate = PositionEstimate(
            latitude: -33.868820,
            longitude: 151.209296,
            altitudeMeters: nil,
            horizontalAccuracyMeters: 3.5,
            source: .uwbAnchored,
            confidence: 0.8,
            timestamp: Date()
        )

        let decoded = PositionEstimate.decode(estimate.encoded)!

        XCTAssertEqual(decoded.latitude, -33.868820, accuracy: 0.000001)
        XCTAssertEqual(decoded.longitude, 151.209296, accuracy: 0.000001)
        XCTAssertEqual(decoded.horizontalAccuracyMeters, 3.5, accuracy: 0.1)
    }

    func testDecodeInvalidStringReturnsNil() {
        XCTAssertNil(PositionEstimate.decode("garbage"))
        XCTAssertNil(PositionEstimate.decode(""))
        XCTAssertNil(PositionEstimate.decode("POS:abc,def,ghi,jkl"))
        XCTAssertNil(PositionEstimate.decode("POS:1.0,2.0,3.0"))
    }

    // MARK: - Dead reckoning algorithm concepts

    func testStepDistanceCalculation() {
        // distance = steps * stepLength
        let steps = 100
        let stepLength = 0.75 // meters (default)
        let distance = Double(steps) * stepLength

        XCTAssertEqual(distance, 75.0)
    }

    func testHeadingToDeltaConversionNorth() {
        // heading 0 (north): +latitude, 0 longitude
        let headingDegrees = 0.0
        let distance = 100.0 // meters
        let metersPerDegreeLat = 111_320.0

        let headingRad = headingDegrees * .pi / 180.0
        let deltaLat = cos(headingRad) * distance / metersPerDegreeLat
        let deltaLon = sin(headingRad) * distance / (metersPerDegreeLat * cos(0.0))

        XCTAssertGreaterThan(deltaLat, 0, "North heading should produce positive latitude delta")
        XCTAssertEqual(deltaLon, 0, accuracy: 1e-10, "North heading should produce zero longitude delta")
    }

    func testHeadingToDeltaConversionEast() {
        // heading 90 (east): 0 latitude, +longitude
        let headingDegrees = 90.0
        let distance = 100.0
        let metersPerDegreeLat = 111_320.0
        let latitude = 0.0

        let headingRad = headingDegrees * .pi / 180.0
        let deltaLat = cos(headingRad) * distance / metersPerDegreeLat
        let deltaLon = sin(headingRad) * distance / (metersPerDegreeLat * cos(latitude * .pi / 180.0))

        XCTAssertEqual(deltaLat, 0, accuracy: 1e-10, "East heading should produce zero latitude delta")
        XCTAssertGreaterThan(deltaLon, 0, "East heading should produce positive longitude delta")
    }

    func testDriftAccumulation() {
        // Drift = 3% per meter traveled
        let driftRate = 0.03
        let distanceTraveled = 200.0 // meters
        let baseAccuracy = 5.0
        let drift = distanceTraveled * driftRate

        XCTAssertEqual(drift, 6.0, accuracy: 0.001)

        let totalAccuracy = baseAccuracy + drift
        XCTAssertEqual(totalAccuracy, 11.0, accuracy: 0.001)
    }

    func testDriftAccumulationLinear() {
        let driftRate = 0.03
        let distances = [10.0, 50.0, 100.0, 500.0]

        for distance in distances {
            let drift = distance * driftRate
            XCTAssertEqual(drift, distance * 0.03, accuracy: 0.001)
        }
    }
}

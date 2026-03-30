import XCTest
@testable import Chirp

final class GeohashTests: XCTestCase {

    // MARK: - Known coordinate -> expected geohash

    func testKnownCoordinateEncode() {
        // Published test vector: lat=57.64911, lon=10.40744, precision=11 -> "u4pruydqqvj"
        let hash = Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11)
        XCTAssertEqual(hash, "u4pruydqqvj")
    }

    func testKnownCoordinateEncodePrecision7() {
        let hash = Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 7)
        // Should be the first 7 chars of the full precision-11 hash
        XCTAssertEqual(hash, "u4pruyd")
    }

    // MARK: - Decode round-trip

    func testDecodeRoundTrip() {
        let lat = 37.7749
        let lon = -122.4194
        let precision = 9

        let hash = Geohash.encode(latitude: lat, longitude: lon, precision: precision)
        let decoded = Geohash.decode(hash)

        XCTAssertNotNil(decoded)
        // Precision 9 yields ~4.8m x 4.8m cells, so within 0.0001 degrees is reasonable
        XCTAssertEqual(decoded!.latitude, lat, accuracy: 0.001)
        XCTAssertEqual(decoded!.longitude, lon, accuracy: 0.001)
    }

    func testDecodeRoundTripPrecision5() {
        let lat = -33.8688
        let lon = 151.2093

        let hash = Geohash.encode(latitude: lat, longitude: lon, precision: 5)
        let decoded = Geohash.decode(hash)

        XCTAssertNotNil(decoded)
        // Precision 5 yields ~4.9km x 4.9km cells
        XCTAssertEqual(decoded!.latitude, lat, accuracy: 0.1)
        XCTAssertEqual(decoded!.longitude, lon, accuracy: 0.1)
    }

    // MARK: - Neighbors

    func testNeighborsReturnEightResults() {
        let hash = Geohash.encode(latitude: 40.7128, longitude: -74.0060, precision: 7)
        let neighbors = Geohash.neighbors(of: hash)

        XCTAssertEqual(neighbors.count, 8)
    }

    func testNeighborsAllValidGeohashStrings() {
        let hash = Geohash.encode(latitude: 51.5074, longitude: -0.1278, precision: 6)
        let neighbors = Geohash.neighbors(of: hash)

        for neighbor in neighbors {
            XCTAssertEqual(neighbor.count, hash.count, "Neighbor should have same length as input")
            // Verify decodable
            XCTAssertNotNil(Geohash.decode(neighbor), "Neighbor '\(neighbor)' should decode")
        }
    }

    func testNeighborsAllDistinctAndDifferentFromCenter() {
        let hash = Geohash.encode(latitude: 48.8566, longitude: 2.3522, precision: 6)
        let neighbors = Geohash.neighbors(of: hash)

        let unique = Set(neighbors)
        XCTAssertEqual(unique.count, 8, "All 8 neighbors should be distinct")
        XCTAssertFalse(unique.contains(hash), "Neighbors should not include the center cell")
    }

    // MARK: - Precision differences

    func testPrecision1VsPrecision7ProducesDifferentLengths() {
        let lat = 35.6762
        let lon = 139.6503

        let hash1 = Geohash.encode(latitude: lat, longitude: lon, precision: 1)
        let hash7 = Geohash.encode(latitude: lat, longitude: lon, precision: 7)

        XCTAssertEqual(hash1.count, 1)
        XCTAssertEqual(hash7.count, 7)
        XCTAssertNotEqual(hash1, hash7)
    }

    func testHigherPrecisionIsPrefix() {
        let lat = 40.7128
        let lon = -74.0060

        let hash5 = Geohash.encode(latitude: lat, longitude: lon, precision: 5)
        let hash9 = Geohash.encode(latitude: lat, longitude: lon, precision: 9)

        XCTAssertTrue(hash9.hasPrefix(hash5), "Higher precision geohash should start with lower precision prefix")
    }

    // MARK: - Edge cases

    func testNorthPole() {
        let hash = Geohash.encode(latitude: 90.0, longitude: 0.0, precision: 7)
        XCTAssertEqual(hash.count, 7)

        let decoded = Geohash.decode(hash)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.latitude, 90.0, accuracy: 0.01)
    }

    func testSouthPole() {
        let hash = Geohash.encode(latitude: -90.0, longitude: 0.0, precision: 7)
        XCTAssertEqual(hash.count, 7)

        let decoded = Geohash.decode(hash)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.latitude, -90.0, accuracy: 0.01)
    }

    func testInternationalDateLineEast() {
        let hash = Geohash.encode(latitude: 0.0, longitude: 180.0, precision: 7)
        XCTAssertEqual(hash.count, 7)

        let decoded = Geohash.decode(hash)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.longitude, 180.0, accuracy: 0.01)
    }

    func testInternationalDateLineWest() {
        let hash = Geohash.encode(latitude: 0.0, longitude: -180.0, precision: 7)
        XCTAssertEqual(hash.count, 7)

        let decoded = Geohash.decode(hash)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded!.longitude, -180.0, accuracy: 0.01)
    }

    func testDecodeEmptyStringReturnsNil() {
        XCTAssertNil(Geohash.decode(""))
    }

    func testDecodeInvalidCharactersReturnsNil() {
        // 'a', 'i', 'l', 'o' are not in the geohash base32 alphabet
        XCTAssertNil(Geohash.decode("ailo"))
    }

    func testNeighborsOfEmptyStringReturnsEmpty() {
        let neighbors = Geohash.neighbors(of: "")
        XCTAssertTrue(neighbors.isEmpty)
    }
}

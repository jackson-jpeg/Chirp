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

    // MARK: - Neighbor lookup table integrity (regression)

    /// The neighbor lookup tables must each be a permutation of the 32-character
    /// base32 alphabet. Two of them were 36 characters long, which made
    /// `adjacentCardinal` index past the end of the 32-element `base32` array and
    /// trap with "Index out of range" for any hash ending in q, r, w or x — and
    /// return wrong neighbors (from the duplicated entries) for several others.
    ///
    /// The tables are private, so these tests assert the property through the
    /// public API instead: sweep enough of the globe to hit all 32 possible
    /// terminal characters, at both an even- and an odd-length precision, and
    /// check the results against an independent geometric oracle.

    /// Every terminal character must be exercised, otherwise a sweep can pass by
    /// simply never reaching the broken rows — which is how the original bug
    /// survived. Guards the two tests below.
    func testSweepCoversAllThirtyTwoTerminalCharacters() {
        for precision in [6, 7] {
            var seen = Set<Character>()
            for hash in Self.sweepHashes(precision: precision) {
                if let last = hash.last { seen.insert(last) }
            }
            XCTAssertEqual(
                seen.count, 32,
                "precision \(precision): sweep reached only \(seen.count)/32 terminal characters"
            )
        }
    }

    /// No coordinate may crash or produce a malformed neighbor.
    func testNeighborsAreWellFormedAcrossTheGlobe() {
        for precision in [6, 7] {
            for hash in Self.sweepHashes(precision: precision) {
                let neighbors = Geohash.neighbors(of: hash)
                XCTAssertEqual(neighbors.count, 8, "\(hash): expected 8 neighbors")
                XCTAssertEqual(Set(neighbors).count, 8, "\(hash): neighbors not distinct")
                XCTAssertFalse(Set(neighbors).contains(hash), "\(hash): neighbors include the center")
                for n in neighbors {
                    XCTAssertEqual(n.count, hash.count, "\(hash) -> \(n): wrong length")
                    XCTAssertNotNil(Geohash.decode(n), "\(hash) -> \(n): does not decode")
                }
            }
        }
    }

    /// The neighbors must be the *correct* cells, not merely well-formed ones.
    /// Oracle: encode the eight coordinates one cell away from this cell's center.
    /// This catches the silent half of the bug — the duplicated table entries
    /// returned plausible-looking but wrong neighbors without crashing.
    func testNeighborsMatchGeometricOracle() {
        for precision in [6, 7] {
            let (latSize, lonSize) = Self.cellSize(precision: precision)
            for hash in Self.sweepHashes(precision: precision) {
                guard let center = Geohash.decode(hash) else {
                    XCTFail("\(hash): center does not decode")
                    continue
                }
                var expected = Set<String>()
                for dLat in [-1.0, 0.0, 1.0] {
                    for dLon in [-1.0, 0.0, 1.0] {
                        if dLat == 0 && dLon == 0 { continue }
                        expected.insert(Geohash.encode(
                            latitude: center.latitude + dLat * latSize,
                            longitude: center.longitude + dLon * lonSize,
                            precision: precision
                        ))
                    }
                }
                XCTAssertEqual(
                    Set(Geohash.neighbors(of: hash)), expected,
                    "\(hash): neighbors do not match the eight adjacent cells"
                )
            }
        }
    }

    // MARK: - Sweep helpers

    /// Hashes covering a wide grid, away from the poles and the antimeridian so
    /// that the geometric oracle does not have to model wrapping.
    private static func sweepHashes(precision: Int) -> [String] {
        var hashes: [String] = []
        for lat in stride(from: -57.0, through: 57.0, by: 3.0) {
            for lon in stride(from: -171.0, through: 171.0, by: 3.0) {
                hashes.append(encode(latitude: lat, longitude: lon, precision: precision))
            }
        }
        return hashes
    }

    private static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        Geohash.encode(latitude: latitude, longitude: longitude, precision: precision)
    }

    /// Degrees of latitude/longitude spanned by one cell at the given precision.
    /// A geohash spends 5 bits per character, alternating longitude first.
    private static func cellSize(precision: Int) -> (lat: Double, lon: Double) {
        let bits = 5 * precision
        let lonBits = (bits + 1) / 2
        let latBits = bits / 2
        return (180.0 / pow(2.0, Double(latBits)), 360.0 / pow(2.0, Double(lonBits)))
    }
}

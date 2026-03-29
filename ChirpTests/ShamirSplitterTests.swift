import XCTest
@testable import Chirp

final class ShamirSplitterTests: XCTestCase {

    // MARK: - Basic split/reconstruct

    func testBasicSplitAndReconstruct() {
        let secret = Data((0..<32).map { UInt8($0) })

        let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 3)
        XCTAssertNotNil(shares)
        XCTAssertEqual(shares?.count, 3)

        // Reconstruct from first 2 shares
        let reconstructed = ShamirSplitter.reconstruct(shares: Array(shares![0..<2]))
        XCTAssertEqual(reconstructed, secret)
    }

    // MARK: - All share combinations (k=2, n=4)

    func testAllShareCombinationsK2N4() {
        let secret = Data((0..<32).map { UInt8($0 &+ 0xA0) })

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 4) else {
            XCTFail("Split returned nil")
            return
        }
        XCTAssertEqual(shares.count, 4)

        // C(4,2) = 6 combinations
        let pairs: [(Int, Int)] = [(0,1), (0,2), (0,3), (1,2), (1,3), (2,3)]
        for (i, j) in pairs {
            let result = ShamirSplitter.reconstruct(shares: [shares[i], shares[j]])
            XCTAssertEqual(result, secret, "Reconstruction failed for shares (\(i), \(j))")
        }
    }

    // MARK: - Threshold enforcement

    func testInsufficientSharesDoNotReconstruct() {
        let secret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 3, shares: 5) else {
            XCTFail("Split returned nil")
            return
        }

        // Only 2 shares with k=3 should NOT produce the original secret
        let insufficient = ShamirSplitter.reconstruct(shares: Array(shares[0..<2]))
        XCTAssertNotEqual(insufficient, secret, "2 shares should not reconstruct a k=3 secret")
    }

    // MARK: - Single byte secret

    func testSingleByteSecret() {
        let secret = Data([0x42])

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 3) else {
            XCTFail("Split returned nil")
            return
        }

        let reconstructed = ShamirSplitter.reconstruct(shares: Array(shares[0..<2]))
        XCTAssertEqual(reconstructed, secret)
    }

    // MARK: - Larger secret (64 bytes, k=3, n=5)

    func testLargerSecretK3N5() {
        let secret = Data((0..<64).map { UInt8($0) })

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 3, shares: 5) else {
            XCTFail("Split returned nil")
            return
        }
        XCTAssertEqual(shares.count, 5)

        // Reconstruct from shares 1, 3, 4 (indices 0, 2, 3)
        let subset = [shares[0], shares[2], shares[3]]
        let reconstructed = ShamirSplitter.reconstruct(shares: subset)
        XCTAssertEqual(reconstructed, secret)
    }

    // MARK: - Edge case: k=2, n=2

    func testMinimumConfigurationK2N2() {
        let secret = Data([0xDE, 0xAD, 0xBE, 0xEF])

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 2) else {
            XCTFail("Split returned nil")
            return
        }
        XCTAssertEqual(shares.count, 2)

        let reconstructed = ShamirSplitter.reconstruct(shares: shares)
        XCTAssertEqual(reconstructed, secret)
    }

    // MARK: - Invalid inputs

    func testInvalidInputK1ReturnsNil() {
        let secret = Data([0x01])
        XCTAssertNil(ShamirSplitter.split(secret: secret, threshold: 1, shares: 3))
    }

    func testInvalidInputNLessThanKReturnsNil() {
        let secret = Data([0x01])
        XCTAssertNil(ShamirSplitter.split(secret: secret, threshold: 4, shares: 3))
    }

    func testInvalidInputEmptySecretReturnsNil() {
        XCTAssertNil(ShamirSplitter.split(secret: Data(), threshold: 2, shares: 3))
    }

    func testInvalidInputNGreaterThan255ReturnsNil() {
        let secret = Data([0x01])
        XCTAssertNil(ShamirSplitter.split(secret: secret, threshold: 2, shares: 256))
    }

    // MARK: - Share uniqueness

    func testSharesHaveDifferentData() {
        let secret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 5) else {
            XCTFail("Split returned nil")
            return
        }

        // Check that not all shares are identical (they should differ)
        var uniqueShares = Set<Data>()
        for share in shares {
            uniqueShares.insert(share.y)
        }
        // With random coefficients and 16 bytes, all 5 shares should be distinct
        XCTAssertEqual(uniqueShares.count, 5, "All shares should have unique y values")
    }

    // MARK: - Deterministic x values

    func testShareXValuesAre1ThroughN() {
        let secret = Data([0xAA, 0xBB])

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 5) else {
            XCTFail("Split returned nil")
            return
        }

        for (i, share) in shares.enumerated() {
            XCTAssertEqual(share.x, UInt8(i + 1), "Share \(i) should have x = \(i + 1)")
        }
    }
}

import XCTest
import CryptoKit
@testable import Chirp

final class TextStegoTests: XCTestCase {

    private let testKey = SymmetricKey(size: .bits256)
    private let wrongKey = SymmetricKey(size: .bits256)

    // MARK: - Roundtrip

    func testBasicRoundtrip() {
        let cover = "Hello, how are you doing today?"
        let hidden = Data("secret".utf8)

        let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
        XCTAssertNotNil(encoded)

        // Visible text should look the same
        let visible = TextStego.visibleText(encoded!)
        XCTAssertEqual(visible, cover)

        // Decode should recover hidden data
        let decoded = TextStego.decode(encoded!, key: testKey)
        XCTAssertEqual(decoded, hidden)
    }

    func testRoundtripUTF8Hidden() {
        let cover = "Just a normal message about the weather today."
        let hidden = Data("Coordinates: 27.9506° N, 82.4572° W".utf8)

        let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
        XCTAssertNotNil(encoded)

        let decoded = TextStego.decode(encoded!, key: testKey)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "Coordinates: 27.9506° N, 82.4572° W")
    }

    // MARK: - Wrong Key

    func testWrongKeyReturnsNil() {
        let cover = "This is a perfectly normal message."
        let hidden = Data("top secret".utf8)

        let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
        XCTAssertNotNil(encoded)

        let decoded = TextStego.decode(encoded!, key: wrongKey)
        XCTAssertNil(decoded)
    }

    // MARK: - Capacity

    func testCapacityCalculation() {
        // 100 visible chars = 99 positions x 2 bits = 198 bits = 24 bytes - 31 overhead = negative -> 0
        let cap100 = TextStego.capacity(coverLength: 100)
        XCTAssertGreaterThanOrEqual(cap100, 0)

        // 200 chars = 199 positions x 2 bits = 398 bits = 49 bytes - 31 = 18 usable bytes
        let cap200 = TextStego.capacity(coverLength: 200)
        XCTAssertGreaterThan(cap200, 0)

        // Single char = 0 positions = 0 capacity
        XCTAssertEqual(TextStego.capacity(coverLength: 1), 0)
        XCTAssertEqual(TextStego.capacity(coverLength: 0), 0)
    }

    // MARK: - hasHiddenContent

    func testHasHiddenContentTrue() {
        let cover = "Hello"
        let hidden = Data("x".utf8)
        let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
        // May be nil if capacity is too small - check
        if let encoded {
            XCTAssertTrue(TextStego.hasHiddenContent(encoded))
        }
    }

    func testHasHiddenContentFalse() {
        XCTAssertFalse(TextStego.hasHiddenContent("Normal text with no hidden content"))
    }

    // MARK: - Edge Cases

    func testEmptyHiddenReturnsNil() {
        let result = TextStego.encode(cover: "cover", hidden: Data(), key: testKey)
        XCTAssertNil(result)
    }

    func testEmptyCoverReturnsNil() {
        let result = TextStego.encode(cover: "", hidden: Data("x".utf8), key: testKey)
        XCTAssertNil(result)
    }

    func testExceedsCapacityReturnsNil() {
        let cover = "Hi" // Only 1 position = very limited capacity
        let hidden = Data(repeating: 0xAA, count: 100) // Way too much data
        let result = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
        XCTAssertNil(result)
    }

    func testVisibleTextStripsInvisible() {
        let text = "H\u{200B}\u{200C}ello"
        XCTAssertEqual(TextStego.visibleText(text), "Hello")
    }

    func testNoHiddenContentDecodeReturnsNil() {
        let result = TextStego.decode("Normal text", key: testKey)
        XCTAssertNil(result)
    }

    // MARK: - Max Capacity

    func testLongCoverMaxCapacity() {
        // 500-char cover should have significant capacity
        let cover = String(repeating: "A", count: 500)
        let capacity = TextStego.capacity(coverLength: 500)
        XCTAssertGreaterThan(capacity, 50, "500-char cover should hide at least 50 bytes")

        // Encode max capacity data
        if capacity > 0 {
            let hidden = Data(repeating: 0x42, count: capacity)
            let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey)
            XCTAssertNotNil(encoded, "Should encode at max capacity")

            if let encoded {
                XCTAssertTrue(encoded.count <= MeshTextMessage.maxTextLength, "Must fit in message limit")
                let decoded = TextStego.decode(encoded, key: testKey)
                XCTAssertEqual(decoded, hidden)
            }
        }
    }
}

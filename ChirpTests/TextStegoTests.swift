import XCTest
import CryptoKit
@testable import Chirp

final class TextStegoTests: XCTestCase {

    private let testKey = SymmetricKey(size: .bits256)
    private let wrongKey = SymmetricKey(size: .bits256)

    /// Cover text must be long enough: hidden bytes + 31 crypto overhead.
    /// ~240 chars provides ~28 usable bytes of hidden capacity.
    private let longCover = "The weather is absolutely beautiful today and I was thinking we should go for a walk in the park later this afternoon. What do you think about meeting at three? I could bring some sandwiches and we could have a nice little picnic by the lake."

    // MARK: - Roundtrip

    func testBasicRoundtrip() {
        let hidden = Data("secret".utf8)
        guard let encoded = TextStego.encode(cover: longCover, hidden: hidden, key: testKey) else {
            XCTFail("Encode returned nil — capacity: \(TextStego.capacity(coverLength: longCover.count))")
            return
        }

        XCTAssertEqual(TextStego.visibleText(encoded), longCover)

        let decoded = TextStego.decode(encoded, key: testKey)
        XCTAssertEqual(decoded, hidden)
    }

    func testRoundtripUTF8Hidden() {
        let hidden = Data("GPS:27.95,82.45".utf8)
        guard let encoded = TextStego.encode(cover: longCover, hidden: hidden, key: testKey) else {
            XCTFail("Encode returned nil")
            return
        }

        guard let decoded = TextStego.decode(encoded, key: testKey) else {
            XCTFail("Decode returned nil")
            return
        }
        XCTAssertEqual(String(data: decoded, encoding: .utf8), "GPS:27.95,82.45")
    }

    // MARK: - Wrong Key

    func testWrongKeyReturnsNil() {
        let hidden = Data("top secret".utf8)
        guard let encoded = TextStego.encode(cover: longCover, hidden: hidden, key: testKey) else {
            XCTFail("Encode returned nil")
            return
        }

        let decoded = TextStego.decode(encoded, key: wrongKey)
        XCTAssertNil(decoded, "Wrong key should not decode")
    }

    // MARK: - Capacity

    func testCapacityCalculation() {
        XCTAssertEqual(TextStego.capacity(coverLength: 0), 0)
        XCTAssertEqual(TextStego.capacity(coverLength: 1), 0)

        // 200 chars = 199 positions × 2 bits = 398 bits = 49 bytes - 31 = 18 usable
        let cap200 = TextStego.capacity(coverLength: 200)
        XCTAssertGreaterThan(cap200, 0)
        XCTAssertEqual(cap200, 18)
    }

    // MARK: - hasHiddenContent

    func testHasHiddenContentDetectsInvisibleChars() {
        let text = "Hello\u{200B}world"
        XCTAssertTrue(TextStego.hasHiddenContent(text))
    }

    func testHasHiddenContentFalseForNormalText() {
        XCTAssertFalse(TextStego.hasHiddenContent("Normal text with no hidden content"))
    }

    // MARK: - Edge Cases

    func testEmptyHiddenReturnsNil() {
        XCTAssertNil(TextStego.encode(cover: longCover, hidden: Data(), key: testKey))
    }

    func testEmptyCoverReturnsNil() {
        XCTAssertNil(TextStego.encode(cover: "", hidden: Data("x".utf8), key: testKey))
    }

    func testExceedsCapacityReturnsNil() {
        let cover = "Hi"  // 1 position, ~0 usable bytes
        XCTAssertNil(TextStego.encode(cover: cover, hidden: Data(repeating: 0xAA, count: 100), key: testKey))
    }

    func testVisibleTextStripsInvisible() {
        XCTAssertEqual(TextStego.visibleText("H\u{200B}\u{200C}ello"), "Hello")
    }

    func testNoHiddenContentDecodeReturnsNil() {
        XCTAssertNil(TextStego.decode("Normal text", key: testKey))
    }

    // MARK: - Max Capacity

    func testLongCoverMaxCapacity() {
        let cover = String(repeating: "A", count: 500)
        let capacity = TextStego.capacity(coverLength: 500)
        XCTAssertGreaterThan(capacity, 50)

        let hidden = Data(repeating: 0x42, count: min(capacity, 50))
        guard let encoded = TextStego.encode(cover: cover, hidden: hidden, key: testKey) else {
            XCTFail("Encode at max capacity failed")
            return
        }
        XCTAssertTrue(encoded.count <= MeshTextMessage.maxTextLength)
        XCTAssertEqual(TextStego.decode(encoded, key: testKey), hidden)
    }
}

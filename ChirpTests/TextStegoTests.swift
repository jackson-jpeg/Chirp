import XCTest
import CryptoKit
@testable import Chirp

final class TextStegoTests: XCTestCase {

    private let testKey = SymmetricKey(size: .bits256)
    private let wrongKey = SymmetricKey(size: .bits256)

    /// Cover text must be long enough: hidden bytes + 31 crypto overhead.
    /// ~240 chars provides ~28 usable bytes of hidden capacity.
    private let longCover = "The weather is absolutely beautiful today and I was thinking we should go for a walk in the park later this afternoon. What do you think about meeting at three? I could bring some sandwiches and we could have a nice little picnic by the lake."

    // MARK: - Zero-Width Roundtrip

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

    // MARK: - Homoglyph Mode

    /// Cover needs ~264+ eligible chars (a,c,e,o,p,x,y,s,i,j) to encode even 1 byte.
    /// Crypto overhead is 31 bytes. Each eligible lowercase char = 1 bit.
    /// This cover is intentionally heavy on eligible letters.
    private let homoglyphCover = String(repeating: "accessible space joy experience ", count: 25)

    func testHomoglyphRoundtrip() {
        let cap = TextStego.capacity(cover: homoglyphCover, mode: .homoglyph)
        guard cap > 0 else {
            // Verify capacity calc is reasonable, skip round-trip if cover is too small
            XCTFail("Homoglyph capacity is 0 for \(homoglyphCover.count)-char cover")
            return
        }
        let hidden = Data("x".utf8)
        guard let encoded = TextStego.encode(cover: homoglyphCover, hidden: hidden, key: testKey, mode: .homoglyph) else {
            XCTFail("Homoglyph encode returned nil — exact capacity: \(cap) bytes")
            return
        }

        // Visible text should match original (homoglyphs look the same, normalized back)
        XCTAssertEqual(TextStego.visibleText(encoded), homoglyphCover)

        // Decode should auto-detect mode and recover data
        let decoded = TextStego.decode(encoded, key: testKey)
        XCTAssertEqual(decoded, hidden)
    }

    func testHomoglyphWrongKeyReturnsNil() {
        let hidden = Data("x".utf8)
        guard let encoded = TextStego.encode(cover: homoglyphCover, hidden: hidden, key: testKey, mode: .homoglyph) else {
            // If capacity too small, skip test
            return
        }
        XCTAssertNil(TextStego.decode(encoded, key: wrongKey))
    }

    func testHomoglyphCapacity() {
        // Count eligible characters in the cover
        let eligibleCount = homoglyphCover.reduce(0) { $0 + (Constants.CICADA.homoglyphMap[$1] != nil ? 1 : 0) }
        let exactCap = TextStego.capacity(cover: homoglyphCover, mode: .homoglyph)

        // Exact capacity should be (eligibleBits / 8) - cryptoOverhead
        let expected = max(0, eligibleCount / 8 - Constants.CICADA.cryptoOverhead)
        XCTAssertEqual(exactCap, expected)
    }

    func testHomoglyphExceedsCapacityReturnsNil() {
        let cover = "ABCDEF"  // no lowercase eligible chars
        XCTAssertNil(TextStego.encode(cover: cover, hidden: Data("x".utf8), key: testKey, mode: .homoglyph))
    }

    // MARK: - Whitespace Mode

    /// Need 264+ spaces for 1 hidden byte (31 overhead + 1 data = 32 bytes = 256 bits).
    /// Each space = 1 bit. This cover has ~300 spaces.
    private let whitespaceCover = String(repeating: "a b c d e f g h i j k l m n o p q r s t u v w x y z ", count: 12)

    func testWhitespaceRoundtrip() {
        let cap = TextStego.capacity(cover: whitespaceCover, mode: .whitespace)
        guard cap > 0 else {
            XCTFail("Whitespace capacity is 0 for cover with \(whitespaceCover.filter { $0 == " " }.count) spaces")
            return
        }
        let hidden = Data("x".utf8)
        guard let encoded = TextStego.encode(cover: whitespaceCover, hidden: hidden, key: testKey, mode: .whitespace) else {
            XCTFail("Whitespace encode returned nil — exact capacity: \(cap) bytes")
            return
        }

        // Visible text should match original (thin space looks like regular space)
        XCTAssertEqual(TextStego.visibleText(encoded), whitespaceCover)

        // Decode should auto-detect mode and recover data
        let decoded = TextStego.decode(encoded, key: testKey)
        XCTAssertEqual(decoded, hidden)
    }

    func testWhitespaceWrongKeyReturnsNil() {
        let hidden = Data("x".utf8)
        guard let encoded = TextStego.encode(cover: whitespaceCover, hidden: hidden, key: testKey, mode: .whitespace) else {
            return  // If capacity too small, skip test
        }
        XCTAssertNil(TextStego.decode(encoded, key: wrongKey))
    }

    func testWhitespaceCapacity() {
        let spaceCount = whitespaceCover.reduce(0) { $0 + ($1 == " " ? 1 : 0) }
        let exactCap = TextStego.capacity(cover: whitespaceCover, mode: .whitespace)
        let expected = max(0, spaceCount / 8 - Constants.CICADA.cryptoOverhead)
        XCTAssertEqual(exactCap, expected)
    }

    func testWhitespaceExceedsCapacityReturnsNil() {
        let cover = "NoSpaces"
        XCTAssertNil(TextStego.encode(cover: cover, hidden: Data("x".utf8), key: testKey, mode: .whitespace))
    }

    // MARK: - Auto-Detection

    func testAutoDetectZeroWidth() {
        let text = "Hello\u{200B}world"
        XCTAssertEqual(TextStego.detectMode(text), .zeroWidth)
    }

    func testAutoDetectHomoglyph() {
        // Insert a Cyrillic 'а' (U+0430) where Latin 'a' would be
        let text = "hell\u{043E}"  // Cyrillic 'о'
        XCTAssertEqual(TextStego.detectMode(text), .homoglyph)
    }

    func testAutoDetectWhitespace() {
        let text = "hello\u{2009}world"  // thin space
        XCTAssertEqual(TextStego.detectMode(text), .whitespace)
    }

    func testAutoDetectNone() {
        XCTAssertNil(TextStego.detectMode("just normal text"))
    }

    func testHasHiddenContentDetectsHomoglyph() {
        let text = "hell\u{043E}"  // Cyrillic 'о'
        XCTAssertTrue(TextStego.hasHiddenContent(text))
    }

    func testHasHiddenContentDetectsWhitespace() {
        let text = "hello\u{2009}world"
        XCTAssertTrue(TextStego.hasHiddenContent(text))
    }

    // MARK: - visibleText Normalization

    func testVisibleTextNormalizesHomoglyphs() {
        // Cyrillic а, с, е → Latin a, c, e
        let text = "\u{0430}\u{0441}\u{0435}"
        XCTAssertEqual(TextStego.visibleText(text), "ace")
    }

    func testVisibleTextNormalizesThinSpaces() {
        let text = "hello\u{2009}world"
        XCTAssertEqual(TextStego.visibleText(text), "hello world")
    }

    func testVisibleTextHandlesMixedContent() {
        // Zero-width + Cyrillic homoglyph + thin space
        let text = "h\u{200B}\u{0435}llo\u{2009}world"
        XCTAssertEqual(TextStego.visibleText(text), "hello world")
    }
}

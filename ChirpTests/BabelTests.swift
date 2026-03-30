import XCTest
@testable import Chirp

final class BabelTests: XCTestCase {

    // MARK: - Wire round-trip

    func testBabelMessageWireRoundTrip() throws {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            channelID: "ch-1",
            sourceLanguage: "en-US",
            targetLanguage: "es",
            originalText: "Hello, how are you?",
            translatedText: "Hola, como estas?",
            isFinal: true,
            timestamp: Date()
        )

        let payload = try message.wirePayload()
        let decoded = BabelMessage.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, message.id)
        XCTAssertEqual(decoded?.senderID, "peer-A")
        XCTAssertEqual(decoded?.senderName, "Alice")
        XCTAssertEqual(decoded?.channelID, "ch-1")
        XCTAssertEqual(decoded?.sourceLanguage, "en-US")
        XCTAssertEqual(decoded?.targetLanguage, "es")
        XCTAssertEqual(decoded?.originalText, "Hello, how are you?")
        XCTAssertEqual(decoded?.translatedText, "Hola, como estas?")
        XCTAssertEqual(decoded?.isFinal, true)
    }

    // MARK: - All fields preserved

    func testAllFieldsPreservedPartialResult() throws {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-2",
            sourceLanguage: "ja",
            targetLanguage: "en-US",
            originalText: "Konnichiwa",
            translatedText: "Hello",
            isFinal: false,
            timestamp: Date()
        )

        let payload = try message.wirePayload()
        let decoded = BabelMessage.from(payload: payload)!

        XCTAssertEqual(decoded.sourceLanguage, "ja")
        XCTAssertEqual(decoded.targetLanguage, "en-US")
        XCTAssertEqual(decoded.originalText, "Konnichiwa")
        XCTAssertEqual(decoded.translatedText, "Hello")
        XCTAssertFalse(decoded.isFinal)
    }

    func testUnicodeTextPreserved() throws {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-C",
            senderName: "Charlie",
            channelID: "ch-3",
            sourceLanguage: "zh-CN",
            targetLanguage: "en-US",
            originalText: "\u{4F60}\u{597D}\u{4E16}\u{754C}",
            translatedText: "Hello World",
            isFinal: true,
            timestamp: Date()
        )

        let payload = try message.wirePayload()
        let decoded = BabelMessage.from(payload: payload)!

        XCTAssertEqual(decoded.originalText, "\u{4F60}\u{597D}\u{4E16}\u{754C}")
    }

    // MARK: - Magic prefix

    func testMagicPrefixCorrect() throws {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            channelID: "ch-1",
            sourceLanguage: "en",
            targetLanguage: "fr",
            originalText: "Test",
            translatedText: "Test",
            isFinal: true,
            timestamp: Date()
        )

        let payload = try message.wirePayload()

        // BBL! = 0x42, 0x42, 0x4C, 0x21
        XCTAssertEqual(payload[0], 0x42)
        XCTAssertEqual(payload[1], 0x42)
        XCTAssertEqual(payload[2], 0x4C)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - Invalid payloads

    func testFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(BabelMessage.from(payload: garbage))
    }

    func testFromWrongPrefixReturnsNil() {
        var data = Data([0x42, 0x42, 0x4C, 0x22]) // BBL" instead of BBL!
        data.append(Data("{}".utf8))
        XCTAssertNil(BabelMessage.from(payload: data))
    }

    func testFromTooShortReturnsNil() {
        let data = Data([0x42, 0x42, 0x4C, 0x21]) // Just the prefix, no JSON
        XCTAssertNil(BabelMessage.from(payload: data))
    }
}

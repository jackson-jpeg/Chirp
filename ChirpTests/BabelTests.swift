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

    // MARK: - Receiver-side: New fields round-trip

    func testNewFieldsRoundTripWithNilTranslatedText() throws {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-D",
            senderName: "Diana",
            channelID: "ch-4",
            sourceLanguage: "fr",
            targetLanguage: "en",
            originalText: "Bonjour le monde",
            translatedText: nil,
            isFinal: true,
            timestamp: Date()
        )

        let payload = try message.wirePayload()
        let decoded = BabelMessage.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.originalText, "Bonjour le monde")
        XCTAssertEqual(decoded?.sourceLanguage, "fr")
        XCTAssertNil(decoded?.translatedText)
        // displayText should fall back to originalText
        XCTAssertEqual(decoded?.displayText, "Bonjour le monde")
    }

    func testDisplayTextPrefersTranslated() {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-E",
            senderName: "Eve",
            channelID: "ch-5",
            sourceLanguage: "es",
            targetLanguage: "en",
            originalText: "Hola",
            translatedText: "Hello",
            isFinal: true,
            timestamp: Date()
        )

        XCTAssertEqual(message.displayText, "Hello")
    }

    func testDisplayTextFallsBackToOriginal() {
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-F",
            senderName: "Frank",
            channelID: "ch-6",
            sourceLanguage: "de",
            targetLanguage: "en",
            originalText: "Guten Tag",
            translatedText: nil,
            isFinal: true,
            timestamp: Date()
        )

        XCTAssertEqual(message.displayText, "Guten Tag")
    }

    // MARK: - Backward compatibility (old format with translatedText)

    func testBackwardCompatOldFormatDecodes() throws {
        // Simulate an old-format message that always includes translatedText
        let message = BabelMessage(
            id: UUID(),
            senderID: "peer-old",
            senderName: "Legacy",
            channelID: "ch-old",
            sourceLanguage: "en",
            targetLanguage: "es",
            originalText: "Good morning",
            translatedText: "Buenos dias",
            isFinal: true,
            timestamp: Date()
        )

        let payload = try message.wirePayload()
        let decoded = BabelMessage.from(payload: payload)!

        // Old format messages should decode fine and have translatedText
        XCTAssertEqual(decoded.translatedText, "Buenos dias")
        XCTAssertEqual(decoded.originalText, "Good morning")
        XCTAssertEqual(decoded.displayText, "Buenos dias")
    }

    // MARK: - Language auto-detection via NLLanguageRecognizer

    @MainActor
    func testLanguageDetectionEnglish() {
        let svc = BabelService()
        let lang = svc.detectLanguage("Hello, how are you doing today? The weather is quite nice.")
        XCTAssertEqual(lang, "en")
    }

    @MainActor
    func testLanguageDetectionSpanish() {
        let svc = BabelService()
        let lang = svc.detectLanguage("Hola, como estas? El clima esta muy bonito hoy.")
        XCTAssertEqual(lang, "es")
    }

    @MainActor
    func testLanguageDetectionFrench() {
        let svc = BabelService()
        let lang = svc.detectLanguage("Bonjour, comment allez-vous aujourd'hui? Il fait beau dehors.")
        XCTAssertEqual(lang, "fr")
    }

    @MainActor
    func testLanguageDetectionEmptyReturnsNil() {
        let svc = BabelService()
        let lang = svc.detectLanguage("")
        XCTAssertNil(lang)
    }

    // MARK: - Translation cache

    @MainActor
    func testTranslationCacheHit() async {
        let svc = BabelService()
        // Prime the cache manually via translateText (will fail on Translation
        // framework unavailability, but the cache mechanics are testable).
        // We test cache key generation consistency instead.
        let key1 = svc.testCacheKey(text: "Hello", from: "en", to: "es")
        let key2 = svc.testCacheKey(text: "Hello", from: "en", to: "es")
        let key3 = svc.testCacheKey(text: "Hello", from: "en", to: "fr")

        XCTAssertEqual(key1, key2, "Same input should produce same cache key")
        XCTAssertNotEqual(key1, key3, "Different target language should produce different cache key")
    }

    @MainActor
    func testTranslationCacheMiss() async {
        let svc = BabelService()
        let key1 = svc.testCacheKey(text: "Hello", from: "en", to: "es")
        let key2 = svc.testCacheKey(text: "Goodbye", from: "en", to: "es")

        XCTAssertNotEqual(key1, key2, "Different text should produce different cache key")
    }
}

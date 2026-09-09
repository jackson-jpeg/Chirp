import XCTest
@testable import Chirp

/// Fuzz-style tests to verify all control packet handlers survive malformed input
/// without crashing. Each test sends truncated, empty, and garbage payloads through
/// the handler's deserialization path.
@MainActor final class DeserializationFuzzTests: XCTestCase {

    // MARK: - Malformed Payload Generators

    private let payloads: [Data] = [
        Data(),                                     // empty
        Data([0x00]),                               // single byte
        Data([0xFF, 0xFF, 0xFF, 0xFF]),             // 4 bytes garbage
        Data(repeating: 0x00, count: 5),            // 5 null bytes
        Data(repeating: 0xAA, count: 23),           // just over FileChunk min
        Data(repeating: 0xFF, count: 100),          // medium garbage
        Data(repeating: 0x00, count: 1000),         // large null payload
    ]

    /// Build payloads with a valid magic prefix but garbage body
    private func prefixedPayloads(_ magic: [UInt8]) -> [Data] {
        let prefix = Data(magic)
        let bodies: [Data] = [
            prefix,                                              // prefix only, no body
            prefix + Data([0x00]),                                // prefix + 1 byte
            prefix + Data(repeating: 0xFF, count: 4),            // prefix + 4 garbage
            prefix + Data(repeating: 0x00, count: 16),           // prefix + 16 null
            prefix + Data(repeating: 0xAB, count: 100),          // prefix + 100 garbage
        ]
        // Every body again as a SLICE of a larger buffer, at offsets that are
        // and are not multiples of four.
        //
        // Everything above is freshly constructed and therefore zero-based, so
        // for the life of this suite it only ever exercised `startIndex == 0`.
        // That is the one case where absolute indexing is accidentally correct
        // and where `load(as:)` is accidentally aligned — which is why a fuzz
        // suite this thorough sat green over a family of crashes for months.
        return bodies + bodies.flatMap { body in
            [1, 2, 3, 4].map { offset -> Data in
                var backing = Data(repeating: 0xEE, count: offset)
                backing.append(body)
                return backing[backing.startIndex.advanced(by: offset)...]
            }
        }
    }

    // MARK: - Text Message (TXT!)

    func testTextMessageSurvivesMalformed() {
        let service = TextMessageService()
        for payload in payloads + prefixedPayloads([0x54, 0x58, 0x54, 0x21]) {
            service.handlePacket(payload, channelID: "test")
        }
    }

    // MARK: - File Transfer (FIL! / FLC! / FNK!)

    func testFileChunkSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x46, 0x49, 0x4C, 0x21]) {
            let result = FileChunk.from(payload: payload)
            // Should return nil, never crash
            _ = result
        }
    }

    func testFileChunkRequestSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x46, 0x4E, 0x4B, 0x21]) {
            let result = try? JSONDecoder().decode(FileChunkRequest.self, from: payload)
            _ = result
        }
    }

    // MARK: - Floor Control (JSON, no prefix)

    func testFloorControlSurvivesMalformed() {
        for payload in payloads {
            let result = try? MeshCodable.decoder.decode(FloorControlMessage.self, from: payload)
            _ = result
        }
    }

    // MARK: - Key Rotation (KRO!)

    /// KRO! had no fuzz coverage. It is the packet that moves the channel to a
    /// new encryption epoch, so a peer can send it unprompted at any time —
    /// which makes it the shortest path from a hostile device to this parser.
    func testKeyRotationSurvivesMalformed() {
        for payload in payloads + prefixedPayloads([0x4B, 0x52, 0x4F, 0x21]) {
            _ = ChannelManager.parseKeyRotationPayload(payload)
        }
    }

    /// The specific shapes the length guard has to get right: exactly at the
    /// 9-byte minimum, one short of it, and a channel ID that is not valid UTF-8.
    func testKeyRotationBoundaryLengths() {
        let magic = Data([0x4B, 0x52, 0x4F, 0x21])
        let epoch = Data([0x00, 0x00, 0x00, 0x01])

        XCTAssertNil(ChannelManager.parseKeyRotationPayload(magic + epoch))        // 8 bytes
        XCTAssertNotNil(ChannelManager.parseKeyRotationPayload(magic + epoch + Data([0x41])))
        XCTAssertNil(ChannelManager.parseKeyRotationPayload(magic + epoch + Data([0xFF, 0xFE])))
        XCTAssertNil(ChannelManager.parseKeyRotationPayload(Data([0x4B, 0x52, 0x4F, 0x22]) + epoch + Data([0x41])))
    }
}

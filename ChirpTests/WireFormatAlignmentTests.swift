import XCTest
@testable import Chirp

/// Regression tests for the misaligned-load and absolute-index family.
///
/// These do not fail with an assertion when the fix is absent — they **trap**,
/// killing the test runner with "Fatal error: load from misaligned raw pointer"
/// or an index-out-of-range abort. A run that dies with zero tests executed is
/// the failure signal here, not a red X.
@MainActor final class WireFormatAlignmentTests: XCTestCase {

    // MARK: - The remotely triggerable one

    /// `decodeFrames` walks `offset` forward by a frame length read out of the
    /// file — and for a received voice message, a peer wrote that file. A frame
    /// length that is not a multiple of four leaves the next length prefix at a
    /// non-4-aligned offset. Nothing here is a slice and nothing is a caller
    /// mistake: the buffer is a zero-based `Data(contentsOf:)` and the offending
    /// number arrives from the network.
    func testFrameLengthNotAMultipleOfFourDoesNotCrashPlayback() throws {
        var payload = Data()
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x02])   // frameCount = 2
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x05])   // frame 1 length = 5
        payload.append(Data(repeating: 0xAA, count: 5))        // -> next read at offset 13
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x01])   // frame 2 length, read AT 13
        payload.append(Data([0xBB]))

        let frames = try loadFrames(from: payload, named: "unaligned-frame-length.opus")
        XCTAssertEqual(frames?.count, 2)
        XCTAssertEqual(frames?[0], Data(repeating: 0xAA, count: 5))
        XCTAssertEqual(frames?[1], Data([0xBB]))
    }

    /// Every odd frame length from 1 to 16, so the walk lands on every possible
    /// residue rather than only the one that happened to reproduce.
    func testEveryFrameLengthResidueDecodesCorrectly() throws {
        for firstLength in 1...16 {
            var payload = Data()
            payload.append(contentsOf: [0x00, 0x00, 0x00, 0x02])
            payload.append(contentsOf: UInt32(firstLength).bigEndianBytes)
            payload.append(Data(repeating: 0xAA, count: firstLength))
            payload.append(contentsOf: [0x00, 0x00, 0x00, 0x03])
            payload.append(Data(repeating: 0xBB, count: 3))

            let frames = try loadFrames(from: payload, named: "residue-\(firstLength).opus")
            XCTAssertEqual(frames?.count, 2, "first frame length \(firstLength)")
            XCTAssertEqual(frames?[0].count, firstLength)
            XCTAssertEqual(frames?[1], Data(repeating: 0xBB, count: 3))
        }
    }

    /// A frame length larger than the remaining buffer must be rejected, not
    /// read past the end. Also covers the reservation: `frameCount` is
    /// attacker-supplied, and reserving it verbatim is a 4 GiB allocation
    /// request from a 12-byte file.
    func testOversizedFrameCountAndLengthAreRejected() throws {
        var lyingCount = Data()
        lyingCount.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])   // frameCount = 4294967295
        lyingCount.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        lyingCount.append(Data([0xAA]))
        XCTAssertNil(try loadFrames(from: lyingCount, named: "lying-count.opus"))

        var lyingLength = Data()
        lyingLength.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        lyingLength.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])  // frame longer than the file
        lyingLength.append(Data([0xAA]))
        XCTAssertNil(try loadFrames(from: lyingLength, named: "lying-length.opus"))
    }

    // MARK: - Slices at every offset

    /// `ChannelCrypto.decrypt` reads a 4-byte epoch prefix off received
    /// ciphertext. Confirmed to trap on a slice at offset 1 before the fix.
    func testDecryptAcceptsCiphertextAsASliceAtAnyOffset() {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        for offset in 0...15 {
            for length in [5, 9, 13, 14, 15, 33, 64] {
                var backing = Data(repeating: 0xEE, count: offset)
                backing.append(Data(repeating: 0xAB, count: length))
                // Garbage never decrypts; the point is that it must FAIL rather
                // than trap. A thrown error is the correct outcome.
                XCTAssertThrowsError(try crypto.decrypt(backing[backing.startIndex.advanced(by: offset)...]))
            }
        }
    }

    /// A real round-trip through a slice: encrypt, re-present the ciphertext as
    /// a slice at every offset, and require the plaintext back. Proves the epoch
    /// prefix is read from the right bytes, not merely read without trapping.
    func testEncryptedRoundTripSurvivesBeingRepresentedAsASlice() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plaintext = Data("the quick brown fox".utf8)
        let ciphertext = try crypto.encrypt(plaintext, epoch: 3)

        for offset in 0...15 {
            var backing = Data(repeating: 0xEE, count: offset)
            backing.append(ciphertext)
            let slice = backing[backing.startIndex.advanced(by: offset)...]
            XCTAssertEqual(try crypto.decrypt(slice, currentEpoch: 3), plaintext, "offset \(offset)")
        }
    }

    /// KRO! key rotation. Before the fix this indexed `payload[0]`, `payload[4..<8]`
    /// and `payload[8...]` absolutely, so a slice read the wrong bytes or went
    /// out of bounds and aborted the process.
    func testKeyRotationParsesIdenticallyFromASliceAtAnyOffset() {
        var canonical = Data([0x4B, 0x52, 0x4F, 0x21])
        canonical.append(contentsOf: [0x00, 0x00, 0x00, 0x2A])   // epoch 42
        canonical.append(Data("general".utf8))

        let expected = ChannelManager.parseKeyRotationPayload(canonical)
        XCTAssertEqual(expected?.epoch, 42)
        XCTAssertEqual(expected?.channelID, "general")

        for offset in 0...15 {
            var backing = Data(repeating: 0xEE, count: offset)
            backing.append(canonical)
            let parsed = ChannelManager.parseKeyRotationPayload(
                backing[backing.startIndex.advanced(by: offset)...]
            )
            XCTAssertEqual(parsed?.epoch, 42, "offset \(offset)")
            XCTAssertEqual(parsed?.channelID, "general", "offset \(offset)")
        }
    }

    /// `MeshPacket.deserialize` indexed from 0. Both transports happen to hand
    /// it a fresh `Data`, so this was latent — but that safety lived in two
    /// unrelated call sites and nothing recorded that it was load-bearing.
    func testMeshPacketDeserializesIdenticallyFromASliceAtAnyOffset() throws {
        let packet = MeshPacket(
            type: .control,
            ttl: 4,
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: 7,
            timestamp: 1_234_567_890,
            channelID: "general",
            payload: Data("hello".utf8)
        )
        let wire = packet.serialize()

        for offset in 0...15 {
            var backing = Data(repeating: 0xEE, count: offset)
            backing.append(wire)
            let decoded = MeshPacket.deserialize(backing[backing.startIndex.advanced(by: offset)...])
            XCTAssertEqual(decoded?.packetID, packet.packetID, "offset \(offset)")
            XCTAssertEqual(decoded?.channelID, "general", "offset \(offset)")
            XCTAssertEqual(decoded?.payload, Data("hello".utf8), "offset \(offset)")
            XCTAssertEqual(decoded?.sequenceNumber, 7, "offset \(offset)")
        }
    }

    /// The voice-delivery payload parser, same treatment.
    func testVoiceDeliveryPayloadParsesFromASliceAtAnyOffset() throws {
        let message = VoiceMessageQueue.PendingMessage(
            id: UUID(), senderID: "peer", recipientID: "me", recipientName: "Me",
            timestamp: Date(), durationMs: 250, fileName: "x.opus"
        )
        let metadata = try JSONEncoder().encode(message)

        var canonical = Data([0x56, 0x4D, 0x51, 0x21])           // "VMQ!"
        canonical.append(contentsOf: UInt32(metadata.count).bigEndianBytes)
        canonical.append(metadata)
        canonical.append(Data(repeating: 0xAA, count: 7))        // audio

        for offset in 0...15 {
            var backing = Data(repeating: 0xEE, count: offset)
            backing.append(canonical)
            let parsed = VoiceMessageQueue.shared.parseDeliveryPayload(
                backing[backing.startIndex.advanced(by: offset)...]
            )
            XCTAssertEqual(parsed?.message.id, message.id, "offset \(offset)")
            XCTAssertEqual(parsed?.audioData, Data(repeating: 0xAA, count: 7), "offset \(offset)")
        }
    }

    // MARK: - Helpers

    private func loadFrames(from payload: Data, named name: String) throws -> [Data]? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("VoiceMessages", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try payload.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let message = VoiceMessageQueue.PendingMessage(
            id: UUID(), senderID: "peer", recipientID: "me", recipientName: "Me",
            timestamp: Date(), durationMs: 100, fileName: name
        )
        return VoiceMessageQueue.shared.loadOpusFrames(for: message)
    }
}

/// Unit tests for the shared reader itself, so its own bounds arithmetic is
/// covered rather than only exercised through callers.
final class DataWireFormatTests: XCTestCase {

    func testReadsBigEndianAtAnOffsetRelativeToStartIndex() {
        let backing = Data([0xEE, 0xEE, 0xEE, 0x12, 0x34, 0x56, 0x78])
        let slice = backing[backing.startIndex.advanced(by: 3)...]
        XCTAssertEqual(slice.readBigEndian(UInt32.self, at: 0), 0x1234_5678)
        XCTAssertEqual(slice.readBigEndian(UInt16.self, at: 0), 0x1234)
        XCTAssertEqual(slice.readBigEndian(UInt16.self, at: 2), 0x5678)
    }

    func testReturnsNilRatherThanTrappingWhenShort() {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertNil(data.readBigEndian(UInt32.self, at: 0))
        XCTAssertNil(data.readBigEndian(UInt16.self, at: 2))
        XCTAssertNil(data.readBigEndian(UInt16.self, at: -1))
        XCTAssertNil(Data().readBigEndian(UInt32.self, at: 0))
        XCTAssertEqual(data.readBigEndian(UInt16.self, at: 1), 0x0203)
    }

    func testByteSliceAndBytesFromAreAllOffsetRelative() {
        let backing = Data([0xEE, 0xEE, 0x0A, 0x0B, 0x0C, 0x0D])
        let slice = backing[backing.startIndex.advanced(by: 2)...]
        XCTAssertEqual(slice.byte(at: 0), 0x0A)
        XCTAssertEqual(slice.byte(at: 3), 0x0D)
        XCTAssertNil(slice.byte(at: 4))
        XCTAssertNil(slice.byte(at: -1))
        XCTAssertEqual(slice.slice(at: 1, length: 2).map { Data($0) }, Data([0x0B, 0x0C]))
        XCTAssertNil(slice.slice(at: 3, length: 2))
        XCTAssertNil(slice.slice(at: 0, length: 5))
        XCTAssertEqual(slice.bytes(from: 2).map { Data($0) }, Data([0x0C, 0x0D]))
        XCTAssertEqual(slice.bytes(from: 4).map { Data($0) }, Data())
        XCTAssertNil(slice.bytes(from: 5))
    }

    /// A length equal to `count` is legal; the guard must not be off by one.
    func testFullWidthReadIsAccepted() {
        XCTAssertEqual(Data([0x00, 0x00, 0x00, 0x09]).readBigEndian(UInt32.self, at: 0), 9)
        XCTAssertEqual(Data([0xFF, 0xFF, 0xFF, 0xFF]).readBigEndian(UInt32.self, at: 0), UInt32.max)
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [UInt8(truncatingIfNeeded: self >> 24), UInt8(truncatingIfNeeded: self >> 16),
         UInt8(truncatingIfNeeded: self >> 8),  UInt8(truncatingIfNeeded: self)]
    }
}

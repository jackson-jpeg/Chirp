import XCTest
@testable import Chirp

final class MeshPacketTests: XCTestCase {

    // MARK: - Helpers

    private func makePacket(
        type: MeshPacket.PacketType = .audio,
        ttl: UInt8 = MeshPacket.defaultTTL,
        originID: UUID = UUID(),
        packetID: UUID = UUID(),
        sequenceNumber: UInt32 = 1,
        timestamp: UInt64 = 1_700_000_000,
        channelID: String = "test-channel",
        payload: Data = Data([0xDE, 0xAD])
    ) -> MeshPacket {
        MeshPacket(
            type: type,
            ttl: ttl,
            originID: originID,
            packetID: packetID,
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            channelID: channelID,
            payload: payload
        )
    }

    // MARK: - Round-trip

    func testSerializeDeserializeRoundTripAudio() {
        let origin = UUID()
        let pktID = UUID()
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let packet = makePacket(
            type: .audio,
            ttl: 4,
            originID: origin,
            packetID: pktID,
            sequenceNumber: 42,
            timestamp: 1_700_000_000,
            channelID: "room-1",
            payload: payload
        )

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.type, .audio)
        XCTAssertEqual(deserialized?.ttl, 4)
        XCTAssertEqual(deserialized?.originID, origin)
        XCTAssertEqual(deserialized?.packetID, pktID)
        XCTAssertEqual(deserialized?.sequenceNumber, 42)
        XCTAssertEqual(deserialized?.timestamp, 1_700_000_000)
        XCTAssertEqual(deserialized?.channelID, "room-1")
        XCTAssertEqual(deserialized?.payload, payload)
    }

    func testSerializeDeserializeRoundTripControl() {
        let payload = Data("{\"type\":\"ping\"}".utf8)
        let packet = makePacket(type: .control, channelID: "ctl", payload: payload)

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.type, .control)
        XCTAssertEqual(deserialized?.channelID, "ctl")
        XCTAssertEqual(deserialized?.payload, payload)
    }

    func testRoundTripWithEmptyPayload() {
        let packet = makePacket(payload: Data())

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.payload, Data())
    }

    // MARK: - TTL / Forwarding

    func testForwardedDecrementsTTL() {
        let packet = makePacket(ttl: 4)

        let forwarded = packet.forwarded()

        XCTAssertNotNil(forwarded)
        XCTAssertEqual(forwarded?.ttl, 3)
    }

    func testForwardedPreservesAllFieldsExceptTTL() {
        let packet = makePacket(ttl: 5, sequenceNumber: 99, channelID: "ch")

        let forwarded = packet.forwarded()!

        XCTAssertEqual(forwarded.type, packet.type)
        XCTAssertEqual(forwarded.originID, packet.originID)
        XCTAssertEqual(forwarded.packetID, packet.packetID)
        XCTAssertEqual(forwarded.sequenceNumber, 99)
        XCTAssertEqual(forwarded.timestamp, packet.timestamp)
        XCTAssertEqual(forwarded.channelID, "ch")
        XCTAssertEqual(forwarded.payload, packet.payload)
    }

    func testForwardedReturnsNilAtTTLOne() {
        let packet = makePacket(ttl: 1)

        XCTAssertNil(packet.forwarded())
    }

    func testForwardedReturnsNilAtTTLZero() {
        let packet = makePacket(ttl: 0)

        XCTAssertNil(packet.forwarded())
    }

    func testForwardedChainExhaustsTTL() {
        var current: MeshPacket? = makePacket(ttl: 3)
        var hops = 0

        while let next = current?.forwarded() {
            current = next
            hops += 1
        }

        XCTAssertEqual(hops, 2)
        XCTAssertEqual(current?.ttl, 1)
    }

    // MARK: - Channel ID encoding/decoding

    func testEmptyChannelID() {
        let packet = makePacket(channelID: "")

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.channelID, "")
    }

    func testShortChannelID() {
        let packet = makePacket(channelID: "a")

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.channelID, "a")
    }

    func testUnicodeChannelID() {
        let packet = makePacket(channelID: "cafe\u{0301}-\u{1F680}")

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.channelID, "cafe\u{0301}-\u{1F680}")
    }

    func testLongChannelID() {
        let longChannel = String(repeating: "x", count: 1000)
        let packet = makePacket(channelID: longChannel)

        let deserialized = MeshPacket.deserialize(packet.serialize())

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.channelID, longChannel)
    }

    // MARK: - Adaptive TTL

    func testAdaptiveTTLCritical() {
        XCTAssertEqual(MeshPacket.adaptiveTTL(for: .control, priority: .critical), 8)
    }

    func testAdaptiveTTLHigh() {
        XCTAssertEqual(MeshPacket.adaptiveTTL(for: .control, priority: .high), 6)
    }

    func testAdaptiveTTLNormal() {
        XCTAssertEqual(MeshPacket.adaptiveTTL(for: .control, priority: .normal), 4)
    }

    func testAdaptiveTTLLow() {
        XCTAssertEqual(MeshPacket.adaptiveTTL(for: .audio, priority: .low), 2)
    }

    // MARK: - Infer Priority

    func testInferPriorityAudioIsLow() {
        let priority = MeshPacket.inferPriority(type: .audio, payload: Data([0xFF, 0xFE]))
        XCTAssertEqual(priority, .low)
    }

    func testInferPrioritySOSIsCritical() {
        let sosPayload = Data("{\"type\":\"SOS\",\"lat\":0}".utf8)
        let priority = MeshPacket.inferPriority(type: .control, payload: sosPayload)
        XCTAssertEqual(priority, .critical)
    }

    func testInferPrioritySOSCaseInsensitive() {
        let sosPayload = Data("{\"sos\":true}".utf8)
        let priority = MeshPacket.inferPriority(type: .control, payload: sosPayload)
        XCTAssertEqual(priority, .critical)
    }

    func testInferPriorityBeaconIsNormal() {
        // BCN! magic: 0x42, 0x43, 0x4E, 0x21
        let beaconPayload = Data([0x42, 0x43, 0x4E, 0x21, 0x01, 0x02])
        let priority = MeshPacket.inferPriority(type: .control, payload: beaconPayload)
        XCTAssertEqual(priority, .normal)
    }

    func testInferPriorityTextIsHigh() {
        let textPayload = Data("{\"type\":\"text\",\"body\":\"hello\"}".utf8)
        let priority = MeshPacket.inferPriority(type: .control, payload: textPayload)
        XCTAssertEqual(priority, .high)
    }

    func testInferPriorityShortControlIsHigh() {
        // Less than 4 bytes -- not enough for beacon or SOS detection
        let priority = MeshPacket.inferPriority(type: .control, payload: Data([0x01]))
        XCTAssertEqual(priority, .high)
    }

    // MARK: - Wire format (exact byte layout)

    func testWireFormatHeaderLayout() {
        let origin = UUID(uuid: (
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
        ))
        let pktID = UUID(uuid: (
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
            0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        ))
        let packet = MeshPacket(
            type: .audio,
            ttl: 3,
            originID: origin,
            packetID: pktID,
            sequenceNumber: 0x01020304,
            timestamp: 0x0102030405060708,
            channelID: "AB",
            payload: Data([0xFF])
        )

        let data = packet.serialize()

        // Type byte
        XCTAssertEqual(data[0], 0x01, "type should be audio (0x01)")
        // TTL byte
        XCTAssertEqual(data[1], 0x03, "ttl should be 3")
        // Origin ID (bytes 2..17)
        for i in 0..<16 {
            XCTAssertEqual(data[2 + i], UInt8(i), "originID byte \(i)")
        }
        // Packet ID (bytes 18..33)
        for i in 0..<16 {
            XCTAssertEqual(data[18 + i], UInt8(0x10 + i), "packetID byte \(i)")
        }
        // Sequence number big-endian (bytes 34..37)
        XCTAssertEqual(data[34], 0x01)
        XCTAssertEqual(data[35], 0x02)
        XCTAssertEqual(data[36], 0x03)
        XCTAssertEqual(data[37], 0x04)
        // Timestamp big-endian (bytes 38..45)
        XCTAssertEqual(data[38], 0x01)
        XCTAssertEqual(data[39], 0x02)
        XCTAssertEqual(data[40], 0x03)
        XCTAssertEqual(data[41], 0x04)
        XCTAssertEqual(data[42], 0x05)
        XCTAssertEqual(data[43], 0x06)
        XCTAssertEqual(data[44], 0x07)
        XCTAssertEqual(data[45], 0x08)
        // Channel length big-endian (bytes 46..47) -- "AB" is 2 bytes
        XCTAssertEqual(data[46], 0x00)
        XCTAssertEqual(data[47], 0x02)
        // Channel UTF-8 (bytes 48..49)
        XCTAssertEqual(data[48], 0x41) // 'A'
        XCTAssertEqual(data[49], 0x42) // 'B'
        // Payload (byte 50)
        XCTAssertEqual(data[50], 0xFF)
        // Total size: 46 header + 2 channelLen + 2 channel + 1 payload = 51
        XCTAssertEqual(data.count, 51)
    }

    func testControlTypeByte() {
        let packet = makePacket(type: .control, channelID: "", payload: Data())
        let data = packet.serialize()
        XCTAssertEqual(data[0], 0x02)
    }

    // MARK: - Reject malformed data

    func testDeserializeTooShortReturnsNil() {
        let shortData = Data([0x01, 0x04, 0x00])
        XCTAssertNil(MeshPacket.deserialize(shortData))
    }

    func testDeserializeEmptyDataReturnsNil() {
        XCTAssertNil(MeshPacket.deserialize(Data()))
    }

    func testDeserializeInvalidTypeByte() {
        // Build a 48-byte buffer with invalid type byte 0x00
        var data = Data(repeating: 0x00, count: 48)
        data[0] = 0x00 // invalid type
        data[1] = 0x04 // valid TTL
        XCTAssertNil(MeshPacket.deserialize(data))
    }

    func testDeserializeInvalidTypeByteFF() {
        var data = Data(repeating: 0x00, count: 48)
        data[0] = 0xFF // invalid type
        data[1] = 0x02
        XCTAssertNil(MeshPacket.deserialize(data))
    }

    func testDeserializeTTLExceedsMax() {
        var data = Data(repeating: 0x00, count: 48)
        data[0] = 0x01 // valid audio type
        data[1] = 0x09 // TTL 9 exceeds maxTTL (8)
        XCTAssertNil(MeshPacket.deserialize(data))
    }

    func testDeserializeTruncatedChannel() {
        // Build a valid header but set channel length to 100, then provide no channel bytes
        var data = Data(repeating: 0x00, count: 48)
        data[0] = 0x01 // audio
        data[1] = 0x04 // TTL
        // Channel length at bytes 46..47: big-endian 100
        data[46] = 0x00
        data[47] = 0x64 // 100
        // Data only has 48 bytes total, channel would need 100 more
        XCTAssertNil(MeshPacket.deserialize(data))
    }

    func testDeserializeExactlyMinWireSizeSucceeds() {
        // 48 bytes: 46 header + 2 channel length (0) + 0 channel + 0 payload
        var data = Data(repeating: 0x00, count: 48)
        data[0] = 0x01 // audio
        data[1] = 0x04 // TTL 4

        let packet = MeshPacket.deserialize(data)

        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.type, .audio)
        XCTAssertEqual(packet?.ttl, 4)
        XCTAssertEqual(packet?.channelID, "")
        XCTAssertEqual(packet?.payload, Data())
    }

    func testDeserializeOneBelowMinWireSizeReturnsNil() {
        let data = Data(repeating: 0x00, count: 47)
        XCTAssertNil(MeshPacket.deserialize(data))
    }

    // MARK: - Max values

    func testMaxSequenceNumber() {
        let packet = makePacket(sequenceNumber: UInt32.max)
        let deserialized = MeshPacket.deserialize(packet.serialize())
        XCTAssertEqual(deserialized?.sequenceNumber, UInt32.max)
    }

    func testMaxTimestamp() {
        let packet = makePacket(timestamp: UInt64.max)
        let deserialized = MeshPacket.deserialize(packet.serialize())
        XCTAssertEqual(deserialized?.timestamp, UInt64.max)
    }

    func testMaxSequenceAndTimestampTogether() {
        let packet = makePacket(sequenceNumber: UInt32.max, timestamp: UInt64.max)
        let deserialized = MeshPacket.deserialize(packet.serialize())
        XCTAssertEqual(deserialized?.sequenceNumber, UInt32.max)
        XCTAssertEqual(deserialized?.timestamp, UInt64.max)
    }

    // MARK: - MessagePriority Comparable

    func testPriorityOrdering() {
        XCTAssertTrue(MeshPacket.MessagePriority.low < .normal)
        XCTAssertTrue(MeshPacket.MessagePriority.normal < .high)
        XCTAssertTrue(MeshPacket.MessagePriority.high < .critical)
        XCTAssertFalse(MeshPacket.MessagePriority.critical < .low)
    }
}

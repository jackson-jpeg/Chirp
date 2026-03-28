import XCTest
@testable import Chirp

final class AudioPacketTests: XCTestCase {

    // MARK: - Round-trip

    func testSerializeDeserializeRoundTrip() {
        let opusData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03])
        let packet = AudioPacket(sequenceNumber: 42, timestamp: 1_700_000_000, opusData: opusData)

        let serialized = packet.serialize()
        let deserialized = AudioPacket.deserialize(serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, 42)
        XCTAssertEqual(deserialized?.timestamp, 1_700_000_000)
        XCTAssertEqual(deserialized?.opusData, opusData)
    }

    func testRoundTripWithEmptyOpusData() {
        let packet = AudioPacket(sequenceNumber: 0, timestamp: 0, opusData: Data())

        let serialized = packet.serialize()
        let deserialized = AudioPacket.deserialize(serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.sequenceNumber, 0)
        XCTAssertEqual(deserialized?.timestamp, 0)
        XCTAssertEqual(deserialized?.opusData, Data())
    }

    // MARK: - Header format

    func testSerializedHeaderLength() {
        let packet = AudioPacket(sequenceNumber: 1, timestamp: 2, opusData: Data([0xFF]))
        let serialized = packet.serialize()
        // 1 byte type + 4 bytes seq + 8 bytes timestamp + 1 byte opus = 14
        XCTAssertEqual(serialized.count, 14)
    }

    func testTypeByte() {
        let packet = AudioPacket(sequenceNumber: 1, timestamp: 2, opusData: Data())
        let serialized = packet.serialize()
        XCTAssertEqual(serialized[0], 0x01)
    }

    // MARK: - Endianness

    func testSequenceNumberBigEndian() {
        let packet = AudioPacket(sequenceNumber: 0x01020304, timestamp: 0, opusData: Data())
        let serialized = packet.serialize()
        // Bytes 1..4 should be big-endian UInt32
        XCTAssertEqual(serialized[1], 0x01)
        XCTAssertEqual(serialized[2], 0x02)
        XCTAssertEqual(serialized[3], 0x03)
        XCTAssertEqual(serialized[4], 0x04)
    }

    func testTimestampBigEndian() {
        let packet = AudioPacket(sequenceNumber: 0, timestamp: 0x0102030405060708, opusData: Data())
        let serialized = packet.serialize()
        // Bytes 5..12 should be big-endian UInt64
        XCTAssertEqual(serialized[5], 0x01)
        XCTAssertEqual(serialized[6], 0x02)
        XCTAssertEqual(serialized[7], 0x03)
        XCTAssertEqual(serialized[8], 0x04)
        XCTAssertEqual(serialized[9], 0x05)
        XCTAssertEqual(serialized[10], 0x06)
        XCTAssertEqual(serialized[11], 0x07)
        XCTAssertEqual(serialized[12], 0x08)
    }

    // MARK: - Deserialize failures

    func testDeserializeTooShortDataReturnsNil() {
        // Less than 13-byte header
        let shortData = Data([0x01, 0x00, 0x00, 0x00])
        XCTAssertNil(AudioPacket.deserialize(shortData))
    }

    func testDeserializeExactlyHeaderSizeSucceeds() {
        // 13 bytes: type + 4 seq + 8 timestamp, zero opus bytes
        var data = Data([0x01])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x05]) // seq = 5
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A]) // ts = 10
        let packet = AudioPacket.deserialize(data)
        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.sequenceNumber, 5)
        XCTAssertEqual(packet?.timestamp, 10)
        XCTAssertEqual(packet?.opusData, Data())
    }

    func testDeserializeWrongTypeByte() {
        var data = Data([0x02]) // wrong type byte
        data.append(contentsOf: [UInt8](repeating: 0x00, count: 12))
        XCTAssertNil(AudioPacket.deserialize(data))
    }

    func testDeserialize12BytesReturnsNil() {
        // Exactly 12 bytes is one short of minimum header
        let data = Data([UInt8](repeating: 0x00, count: 12))
        XCTAssertNil(AudioPacket.deserialize(data))
    }

    // MARK: - Large sequence/timestamp values

    func testMaxSequenceNumber() {
        let packet = AudioPacket(sequenceNumber: UInt32.max, timestamp: 0, opusData: Data([0xAA]))
        let deserialized = AudioPacket.deserialize(packet.serialize())
        XCTAssertEqual(deserialized?.sequenceNumber, UInt32.max)
    }

    func testMaxTimestamp() {
        let packet = AudioPacket(sequenceNumber: 0, timestamp: UInt64.max, opusData: Data([0xBB]))
        let deserialized = AudioPacket.deserialize(packet.serialize())
        XCTAssertEqual(deserialized?.timestamp, UInt64.max)
    }
}

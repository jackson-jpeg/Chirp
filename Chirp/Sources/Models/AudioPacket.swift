import Foundation

struct AudioPacket: Sendable {
    static let typeAudio: UInt8 = 0x01
    static let headerSize = 13 // 1 + 4 + 8

    let type: UInt8
    let sequenceNumber: UInt32
    let timestamp: UInt64
    let opusData: Data

    init(sequenceNumber: UInt32, timestamp: UInt64, opusData: Data) {
        self.type = Self.typeAudio
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.opusData = opusData
    }

    func serialize() -> Data {
        var data = Data(capacity: Self.headerSize + opusData.count)
        data.append(type)
        // Write big-endian bytes directly to avoid alignment issues
        let seq = sequenceNumber.bigEndian
        withUnsafeBytes(of: seq) { data.append(contentsOf: $0) }
        let ts = timestamp.bigEndian
        withUnsafeBytes(of: ts) { data.append(contentsOf: $0) }
        data.append(opusData)
        return data
    }

    static func deserialize(_ data: Data) -> AudioPacket? {
        guard data.count >= headerSize else { return nil }
        let typeByte = data[data.startIndex]
        guard typeByte == typeAudio else { return nil }

        // Read big-endian integers byte-by-byte to avoid misaligned pointer access
        let s = data.startIndex
        let sequenceNumber: UInt32 =
            UInt32(data[s + 1]) << 24 | UInt32(data[s + 2]) << 16 |
            UInt32(data[s + 3]) << 8  | UInt32(data[s + 4])

        let timestamp: UInt64 =
            UInt64(data[s + 5])  << 56 | UInt64(data[s + 6])  << 48 |
            UInt64(data[s + 7])  << 40 | UInt64(data[s + 8])  << 32 |
            UInt64(data[s + 9])  << 24 | UInt64(data[s + 10]) << 16 |
            UInt64(data[s + 11]) << 8  | UInt64(data[s + 12])

        let opusData = data[(data.startIndex + headerSize)...]
        return AudioPacket(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            opusData: Data(opusData)
        )
    }
}

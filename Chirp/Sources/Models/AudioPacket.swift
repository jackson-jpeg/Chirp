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
        var seqBE = sequenceNumber.bigEndian
        data.append(Data(bytes: &seqBE, count: 4))
        var tsBE = timestamp.bigEndian
        data.append(Data(bytes: &tsBE, count: 8))
        data.append(opusData)
        return data
    }

    static func deserialize(_ data: Data) -> AudioPacket? {
        guard data.count >= headerSize else { return nil }
        let typeByte = data[data.startIndex]
        guard typeByte == typeAudio else { return nil }

        let seqBytes = data[data.startIndex + 1 ..< data.startIndex + 5]
        let sequenceNumber = seqBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        let tsBytes = data[data.startIndex + 5 ..< data.startIndex + 13]
        let timestamp = tsBytes.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }

        let opusData = data[data.startIndex + headerSize...]
        return AudioPacket(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            opusData: Data(opusData)
        )
    }
}

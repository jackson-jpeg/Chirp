import Foundation
import CryptoKit
import OSLog

/// Audio covert channel using inter-packet timing modulation.
///
/// Opus at 24kbps destroys frequency-domain steganography.
/// Instead, CICADA encodes bits in the TIMING between audio packets.
/// Normal inter-packet interval: 20ms. CICADA modulates:
///   - 19ms (-1ms) = bit 0
///   - 21ms (+1ms) = bit 1
/// At 50 packets/second, this gives ~6 bytes/second of covert bandwidth.
/// Imperceptible to listeners. Invisible to codec inspection.
enum AudioStego {

    private static let logger = Logger(subsystem: Constants.subsystem, category: "AudioStego")

    /// Normal Opus frame interval in seconds.
    static let nominalInterval: TimeInterval = 0.020 // 20ms
    /// Timing offset for encoding (+/-1ms).
    static let timingOffset: TimeInterval = 0.001
    /// Threshold for decoding: within 0.5ms of expected timing.
    static let decodingThreshold: TimeInterval = 0.0005

    // MARK: - Encoding (Sender Side)

    /// A timing schedule for encoding hidden data into audio packet intervals.
    struct TimingSchedule: Sendable {
        let bits: [Bool]
        private(set) var currentIndex: Int = 0

        init(hidden: Data, key: SymmetricKey) {
            // Encrypt hidden data
            if let encrypted = Self.encryptPayload(hidden, key: key) {
                var allBits: [Bool] = []
                // Prepend length as 16-bit BE
                let len = UInt16(encrypted.count)
                for shift in stride(from: 15, through: 0, by: -1) {
                    allBits.append((len >> shift) & 1 == 1)
                }
                // Data bits
                for byte in encrypted {
                    for shift in stride(from: 7, through: 0, by: -1) {
                        allBits.append((byte >> shift) & 1 == 1)
                    }
                }
                self.bits = allBits
            } else {
                self.bits = []
            }
        }

        /// Get the delay for the next audio packet. Returns nil when all bits are sent.
        mutating func nextDelay() -> TimeInterval? {
            guard currentIndex < bits.count else { return nil }
            let bit = bits[currentIndex]
            currentIndex += 1
            return bit
                ? nominalInterval + timingOffset   // 21ms = bit 1
                : nominalInterval - timingOffset   // 19ms = bit 0
        }

        /// Whether all bits have been transmitted.
        var isComplete: Bool { currentIndex >= bits.count }

        /// Progress as fraction 0-1.
        var progress: Float {
            guard !bits.isEmpty else { return 1.0 }
            return Float(currentIndex) / Float(bits.count)
        }

        private static func encryptPayload(_ data: Data, key: SymmetricKey) -> Data? {
            guard let sealed = try? AES.GCM.seal(data, using: key),
                  let combined = sealed.combined else { return nil }
            var payload = Data()
            payload.append(Constants.CICADA.version)
            payload.append(combined)
            return payload
        }
    }

    // MARK: - Decoding (Receiver Side)

    /// Collects inter-packet timing intervals and decodes hidden data.
    final class TimingDecoder: @unchecked Sendable {
        private var intervals: [TimeInterval] = []
        private var lastPacketTime: Date?
        private let key: SymmetricKey
        private let logger = Logger(subsystem: Constants.subsystem, category: "AudioStego")

        init(key: SymmetricKey) {
            self.key = key
        }

        /// Record the arrival of an audio packet.
        func recordPacket() {
            let now = Date()
            if let last = lastPacketTime {
                intervals.append(now.timeIntervalSince(last))
            }
            lastPacketTime = now
        }

        /// Attempt to decode hidden data from collected timing intervals.
        /// Call this when PTT transmission ends.
        func decode() -> Data? {
            guard intervals.count >= 16 else { return nil } // Need at least length header

            // Convert intervals to bits
            var bits: [Bool] = []
            for interval in intervals {
                let deviation = interval - nominalInterval
                if abs(deviation) < decodingThreshold {
                    // Too close to nominal — no data encoded in this packet
                    continue
                }
                bits.append(deviation > 0) // positive = 1, negative = 0
            }

            guard bits.count >= 16 else { return nil }

            // Read length (16-bit BE)
            var length: UInt16 = 0
            for i in 0..<16 {
                if bits[i] { length |= (1 << (15 - i)) }
            }

            guard length > 0, length < 1000 else { return nil }
            let dataBitsNeeded = 16 + Int(length) * 8
            guard bits.count >= dataBitsNeeded else { return nil }

            // Extract bytes
            var encrypted = Data(count: Int(length))
            for byteIndex in 0..<Int(length) {
                var byte: UInt8 = 0
                for bitOffset in 0..<8 {
                    let bitPos = 16 + byteIndex * 8 + bitOffset
                    if bits[bitPos] { byte |= (1 << (7 - bitOffset)) }
                }
                encrypted[byteIndex] = byte
            }

            // Decrypt
            return decryptPayload(encrypted)
        }

        /// Reset for a new PTT session.
        func reset() {
            intervals.removeAll()
            lastPacketTime = nil
        }

        private func decryptPayload(_ data: Data) -> Data? {
            guard data.count > 1 else { return nil }
            let version = data[0]
            guard version == Constants.CICADA.version else { return nil }
            let ciphertext = data.dropFirst(1)
            guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
            return try? AES.GCM.open(box, using: key)
        }
    }

    /// Calculate covert bandwidth: bytes per second at 50 packets/sec.
    static var covertBandwidth: Double {
        50.0 / 8.0 // 50 bits/sec = 6.25 bytes/sec
    }

    /// Estimate transmission time for a hidden payload.
    static func estimatedDuration(hiddenBytes: Int) -> TimeInterval {
        let encryptedSize = hiddenBytes + Constants.CICADA.cryptoOverhead
        let totalBits = 16 + encryptedSize * 8  // 16-bit length header + data
        return Double(totalBits) * nominalInterval
    }
}

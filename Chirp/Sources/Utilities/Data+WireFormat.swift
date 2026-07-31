import Foundation

extension Data {
    /// Read a big-endian fixed-width integer that starts `offset` bytes from the
    /// beginning of *this value*. Returns `nil` if there are not enough bytes.
    ///
    /// Every multi-byte integer read out of a received buffer must go through
    /// here. Two distinct hazards live in the obvious alternatives, and both
    /// have crashed this app on real input:
    ///
    /// **1. Alignment.** `data.withUnsafeBytes { $0.load(as: UInt32.self) }`
    /// traps with *"Fatal error: load from misaligned raw pointer"* unless the
    /// pointer happens to be 4-byte aligned. The pointer is `base + startIndex`,
    /// so alignment is decided by whatever arithmetic the caller did to reach
    /// this buffer — not by anything the type system checks. In
    /// `VoiceMessageQueue.decodeFrames` the offset advanced by a frame length
    /// read out of the file itself, which means a peer chose it: a frame length
    /// that is not a multiple of four left the next read misaligned and killed
    /// the process. Reading byte by byte has no alignment requirement at all,
    /// so the hazard stops existing rather than being avoided.
    ///
    /// **2. Absolute indices.** `Data`'s indices are absolute, not relative. For
    /// a slice, `data[0]` is *out of bounds* rather than the first byte, and
    /// `data[4..<8]` addresses the original buffer's bytes 4–8 rather than this
    /// slice's. `count` gives no warning of it. Every offset here is measured
    /// from `startIndex`, so a slice behaves exactly like a fresh copy.
    ///
    /// - Parameters:
    ///   - type: The integer type to read (`UInt32.self`, `UInt16.self`, …).
    ///   - offset: Byte offset from the start of this value, not an index.
    func readBigEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
        let size = MemoryLayout<T>.size
        guard offset >= 0, size <= count, offset <= count - size else { return nil }
        let start = index(startIndex, offsetBy: offset)
        var value: T = 0
        for i in 0..<size {
            value = (value << 8) | T(self[index(start, offsetBy: i)])
        }
        return value
    }

    /// The byte `offset` bytes from the start of this value, or `nil` if short.
    /// Same absolute-index hazard as above: `data[0]` is not the first byte of
    /// a slice.
    func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[index(startIndex, offsetBy: offset)]
    }

    /// The sub-range `offset..<offset+length` measured from the start of this
    /// value, or `nil` if it does not fit.
    func slice(at offset: Int, length: Int) -> Data? {
        guard offset >= 0, length >= 0, length <= count, offset <= count - length else { return nil }
        let start = index(startIndex, offsetBy: offset)
        return self[start..<index(start, offsetBy: length)]
    }

    /// Everything from `offset` bytes in, measured from the start of this value.
    ///
    /// Deliberately not named `suffix(from:)`: `Data.Index` is `Int`, so that
    /// name would silently overload `Collection.suffix(from:)`, which takes an
    /// absolute index — reintroducing the exact bug this file exists to remove.
    func bytes(from offset: Int) -> Data? {
        guard offset >= 0, offset <= count else { return nil }
        return self[index(startIndex, offsetBy: offset)...]
    }
}

import CryptoKit
import Foundation

/// Text steganography using invisible Unicode characters.
///
/// Encodes a hidden byte payload between visible characters of a cover message
/// using zero-width Unicode characters (U+200B = bit 0, U+200C = bit 1).
/// The hidden payload is AES-GCM encrypted before embedding.
enum TextStego {

    // MARK: - Public API

    /// Encode hidden data into a cover text string.
    /// Returns nil if the cover text doesn't have enough capacity.
    static func encode(cover: String, hidden: Data, key: SymmetricKey) -> String? {
        guard !hidden.isEmpty, !cover.isEmpty else { return nil }

        // 1. Encrypt the hidden data
        guard let encrypted = encryptPayload(hidden, key: key) else { return nil }

        // 2. Check capacity
        let visibleChars = Array(cover)
        let positions = visibleChars.count - 1  // inter-character positions
        guard positions > 0 else { return nil }

        let bitsAvailable = positions * Constants.CICADA.bitsPerPosition
        let bitsNeeded = encrypted.count * 8
        guard bitsAvailable >= bitsNeeded else { return nil }

        // 3. Convert encrypted bytes to bit pairs
        let bitPairs = bytesToBitPairs(encrypted)

        // 4. Interleave invisible chars between visible chars
        var result = String(visibleChars[0])
        for i in 1..<visibleChars.count {
            let pairIndex = i - 1
            if pairIndex < bitPairs.count {
                let (b1, b0) = bitPairs[pairIndex]
                result.append(b1 ? Constants.CICADA.bit1 : Constants.CICADA.bit0)
                result.append(b0 ? Constants.CICADA.bit1 : Constants.CICADA.bit0)
            }
            result.append(visibleChars[i])
        }

        // 5. Verify total length fits MeshTextMessage limit
        guard result.count <= MeshTextMessage.maxTextLength else { return nil }

        return result
    }

    /// Decode hidden data from a text string.
    /// Returns nil if no hidden data found or decryption fails.
    static func decode(_ text: String, key: SymmetricKey) -> Data? {
        // 1. Extract invisible characters between visible chars
        let bitPairs = extractBitPairs(from: text)
        guard !bitPairs.isEmpty else { return nil }

        // 2. Convert bit pairs to bytes
        let encrypted = bitPairsToBytes(bitPairs)
        guard !encrypted.isEmpty else { return nil }

        // 3. Decrypt
        return decryptPayload(encrypted, key: key)
    }

    /// Invisible Unicode scalars used for encoding.
    private static let stegoScalars: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}"]

    /// Quick check: does this text contain invisible stego characters?
    static func hasHiddenContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { stegoScalars.contains($0) }
    }

    /// Calculate the maximum number of hidden bytes a cover text of this length can carry.
    static func capacity(coverLength: Int) -> Int {
        guard coverLength > 1 else { return 0 }
        let positions = coverLength - 1
        let totalBits = positions * Constants.CICADA.bitsPerPosition
        let totalBytes = totalBits / 8
        let usable = totalBytes - Constants.CICADA.cryptoOverhead
        return max(0, usable)
    }

    /// Extract only the visible text (strip invisible chars).
    static func visibleText(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if !stegoScalars.contains(scalar) {
                result.append(Character(scalar))
            }
        }
        return result
    }

    // MARK: - Encryption

    private static func encryptPayload(_ data: Data, key: SymmetricKey) -> Data? {
        // Format: [version:1][length:2 BE][AES-GCM sealed box (nonce+ciphertext+tag)]
        guard let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else { return nil }

        var payload = Data()
        payload.append(Constants.CICADA.version)
        var length = UInt16(combined.count).bigEndian
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(combined)
        return payload
    }

    private static func decryptPayload(_ data: Data, key: SymmetricKey) -> Data? {
        guard data.count >= Constants.CICADA.cryptoOverhead else { return nil }

        let version = data[0]
        guard version == Constants.CICADA.version else { return nil }

        let length = UInt16(data[1]) << 8 | UInt16(data[2])
        let ciphertextStart = 3
        guard ciphertextStart + Int(length) <= data.count else { return nil }

        let ciphertext = data[ciphertextStart..<ciphertextStart + Int(length)]
        guard let sealedBox = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Bit Manipulation

    /// Convert bytes to pairs of bits (high bit, low bit) for 2-bit-per-position encoding.
    private static func bytesToBitPairs(_ data: Data) -> [(Bool, Bool)] {
        var pairs: [(Bool, Bool)] = []
        for byte in data {
            // 4 bit pairs per byte, MSB first
            pairs.append((byte & 0x80 != 0, byte & 0x40 != 0))
            pairs.append((byte & 0x20 != 0, byte & 0x10 != 0))
            pairs.append((byte & 0x08 != 0, byte & 0x04 != 0))
            pairs.append((byte & 0x02 != 0, byte & 0x01 != 0))
        }
        return pairs
    }

    /// Extract bit pairs from invisible characters in a text string.
    private static func extractBitPairs(from text: String) -> [(Bool, Bool)] {
        let zwsp: Unicode.Scalar = "\u{200B}"
        let zwnj: Unicode.Scalar = "\u{200C}"
        var pairs: [(Bool, Bool)] = []
        var pendingBit: Bool? = nil

        for scalar in text.unicodeScalars {
            if scalar == zwsp {
                if let first = pendingBit {
                    pairs.append((first, false))
                    pendingBit = nil
                } else {
                    pendingBit = false
                }
            } else if scalar == zwnj {
                if let first = pendingBit {
                    pairs.append((first, true))
                    pendingBit = nil
                } else {
                    pendingBit = true
                }
            }
            // Visible characters are ignored
        }

        return pairs
    }

    /// Convert bit pairs back to bytes.
    private static func bitPairsToBytes(_ pairs: [(Bool, Bool)]) -> Data {
        var bytes = Data()
        // Process 4 pairs at a time (1 byte)
        for i in stride(from: 0, to: pairs.count - 3, by: 4) {
            var byte: UInt8 = 0
            if pairs[i].0     { byte |= 0x80 }
            if pairs[i].1     { byte |= 0x40 }
            if pairs[i + 1].0 { byte |= 0x20 }
            if pairs[i + 1].1 { byte |= 0x10 }
            if pairs[i + 2].0 { byte |= 0x08 }
            if pairs[i + 2].1 { byte |= 0x04 }
            if pairs[i + 3].0 { byte |= 0x02 }
            if pairs[i + 3].1 { byte |= 0x01 }
            bytes.append(byte)
        }
        return bytes
    }
}

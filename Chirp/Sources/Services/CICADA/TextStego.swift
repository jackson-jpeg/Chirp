import CryptoKit
import Foundation

/// Text steganography using invisible Unicode characters.
///
/// Supports three encoding modes:
/// - `.zeroWidth`: Invisible Unicode chars between visible chars (high capacity, detectable by regex)
/// - `.homoglyph`: Cyrillic/Greek look-alikes for Latin chars (medium capacity, visually undetectable)
/// - `.whitespace`: Thin space vs regular space at word boundaries (low capacity, extremely subtle)
enum TextStego {

    // MARK: - Mode

    enum StegoMode: Int, CaseIterable {
        case zeroWidth = 0
        case homoglyph = 1
        case whitespace = 2
    }

    // MARK: - Public API

    /// Encode hidden data into a cover text string.
    /// Returns nil if the cover text doesn't have enough capacity.
    /// Defaults to `.zeroWidth` for backward compatibility.
    static func encode(cover: String, hidden: Data, key: SymmetricKey) -> String? {
        encode(cover: cover, hidden: hidden, key: key, mode: .zeroWidth)
    }

    /// Encode hidden data into a cover text using the specified mode.
    static func encode(cover: String, hidden: Data, key: SymmetricKey, mode: StegoMode) -> String? {
        guard !hidden.isEmpty, !cover.isEmpty else { return nil }

        // 1. Encrypt the hidden data
        guard let encrypted = encryptPayload(hidden, key: key) else { return nil }

        // 2. Dispatch to mode-specific encoder
        let result: String?
        switch mode {
        case .zeroWidth:
            result = encodeZeroWidth(cover: cover, encrypted: encrypted)
        case .homoglyph:
            result = encodeHomoglyph(cover: cover, encrypted: encrypted)
        case .whitespace:
            result = encodeWhitespace(cover: cover, encrypted: encrypted)
        }

        // 3. Verify total length fits MeshTextMessage limit
        guard let encoded = result, encoded.count <= MeshTextMessage.maxTextLength else { return nil }
        return result
    }

    /// Decode hidden data from a text string.
    /// Auto-detects the encoding mode.
    /// Returns nil if no hidden data found or decryption fails.
    static func decode(_ text: String, key: SymmetricKey) -> Data? {
        let mode = detectMode(text)
        guard let mode else { return nil }

        let encrypted: Data
        switch mode {
        case .zeroWidth:
            let bitPairs = extractBitPairs(from: text)
            guard !bitPairs.isEmpty else { return nil }
            encrypted = bitPairsToBytes(bitPairs)
        case .homoglyph:
            encrypted = decodeHomoglyphBits(from: text)
        case .whitespace:
            encrypted = decodeWhitespaceBits(from: text)
        }

        guard !encrypted.isEmpty else { return nil }
        return decryptPayload(encrypted, key: key)
    }

    /// Invisible Unicode scalars used for zero-width encoding.
    private static let stegoScalars: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}"]

    /// Quick check: does this text contain hidden stego content (any mode)?
    static func hasHiddenContent(_ text: String) -> Bool {
        detectMode(text) != nil
    }

    /// Detect which stego mode was used, or nil if no hidden content.
    static func detectMode(_ text: String) -> StegoMode? {
        // Check homoglyph: any Cyrillic homoglyph characters?
        if text.contains(where: { Constants.CICADA.cyrillicHomoglyphs.contains($0) }) {
            return .homoglyph
        }
        // Check whitespace: any thin spaces?
        if text.unicodeScalars.contains(where: { $0 == "\u{2009}" }) {
            return .whitespace
        }
        // Check zero-width: any zero-width chars?
        if text.unicodeScalars.contains(where: { stegoScalars.contains($0) }) {
            return .zeroWidth
        }
        return nil
    }

    /// Calculate the maximum number of hidden bytes a cover text can carry for a given mode.
    static func capacity(coverLength: Int, mode: StegoMode = .zeroWidth) -> Int {
        guard coverLength > 1 else { return 0 }

        let totalBits: Int
        switch mode {
        case .zeroWidth:
            let positions = coverLength - 1
            totalBits = positions * Constants.CICADA.bitsPerPosition
        case .homoglyph:
            // Approximate: assume ~30% of chars are eligible homoglyphs in English text.
            // For exact capacity, caller should use capacity(cover:mode:).
            // Here we use coverLength directly as upper bound of eligible positions.
            totalBits = coverLength  // 1 bit per eligible char (worst case = all eligible)
        case .whitespace:
            // ~1 bit per word boundary. Approximate words = coverLength / 5.
            let approxSpaces = max(0, coverLength / 5 - 1)
            totalBits = approxSpaces
        }

        let totalBytes = totalBits / 8
        let usable = totalBytes - Constants.CICADA.cryptoOverhead
        return max(0, usable)
    }

    /// Calculate exact capacity for a specific cover string and mode.
    static func capacity(cover: String, mode: StegoMode) -> Int {
        let totalBits: Int
        switch mode {
        case .zeroWidth:
            let positions = cover.count - 1
            totalBits = positions * Constants.CICADA.bitsPerPosition
        case .homoglyph:
            totalBits = cover.reduce(0) { count, ch in
                count + (Constants.CICADA.homoglyphMap[ch] != nil ? 1 : 0)
            }
        case .whitespace:
            totalBits = cover.reduce(0) { count, ch in
                count + (ch == " " ? 1 : 0)
            }
        }

        let totalBytes = totalBits / 8
        let usable = totalBytes - Constants.CICADA.cryptoOverhead
        return max(0, usable)
    }

    /// Extract only the visible text (strip invisible chars, normalize homoglyphs back to Latin).
    static func visibleText(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if stegoScalars.contains(scalar) {
                // Zero-width char → skip
                continue
            } else if scalar == "\u{2009}" {
                // Thin space → regular space
                result.append(" ")
            } else if let latin = Constants.CICADA.homoglyphReverse[Character(scalar)] {
                // Cyrillic homoglyph → Latin original
                result.append(latin)
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    // MARK: - Zero-Width Encoder/Decoder

    private static func encodeZeroWidth(cover: String, encrypted: Data) -> String? {
        let visibleChars = Array(cover)
        let positions = visibleChars.count - 1
        guard positions > 0 else { return nil }

        let bitsAvailable = positions * Constants.CICADA.bitsPerPosition
        let bitsNeeded = encrypted.count * 8
        guard bitsAvailable >= bitsNeeded else { return nil }

        let bitPairs = bytesToBitPairs(encrypted)

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

        return result
    }

    // MARK: - Homoglyph Encoder/Decoder

    private static func encodeHomoglyph(cover: String, encrypted: Data) -> String? {
        // Count eligible positions
        let chars = Array(cover)
        let eligibleCount = chars.reduce(0) { $0 + (Constants.CICADA.homoglyphMap[$1] != nil ? 1 : 0) }
        let bitsNeeded = encrypted.count * 8
        guard eligibleCount >= bitsNeeded else { return nil }

        // Convert bytes to individual bits
        let bits = bytesToBits(encrypted)

        var result = ""
        var bitIndex = 0
        for ch in chars {
            if bitIndex < bits.count, let cyrillic = Constants.CICADA.homoglyphMap[ch] {
                // Eligible position: Latin (0) or Cyrillic (1)
                result.append(bits[bitIndex] ? cyrillic : ch)
                bitIndex += 1
            } else {
                result.append(ch)
            }
        }

        return result
    }

    private static func decodeHomoglyphBits(from text: String) -> Data {
        var bits: [Bool] = []
        for ch in text {
            if Constants.CICADA.cyrillicHomoglyphs.contains(ch) {
                bits.append(true)  // Cyrillic = 1
            } else if Constants.CICADA.homoglyphMap[ch] != nil {
                bits.append(false) // Latin eligible char = 0
            }
            // Non-eligible chars are ignored
        }
        return bitsToBytes(bits)
    }

    // MARK: - Whitespace Encoder/Decoder

    private static func encodeWhitespace(cover: String, encrypted: Data) -> String? {
        // Count space positions
        let spaceCount = cover.reduce(0) { $0 + ($1 == " " ? 1 : 0) }
        let bitsNeeded = encrypted.count * 8
        guard spaceCount >= bitsNeeded else { return nil }

        let bits = bytesToBits(encrypted)

        var result = ""
        var bitIndex = 0
        for ch in cover {
            if ch == " " && bitIndex < bits.count {
                result.append(bits[bitIndex] ? Constants.CICADA.space1 : Constants.CICADA.space0)
                bitIndex += 1
            } else {
                result.append(ch)
            }
        }

        return result
    }

    private static func decodeWhitespaceBits(from text: String) -> Data {
        var bits: [Bool] = []
        for scalar in text.unicodeScalars {
            if scalar == "\u{2009}" {
                bits.append(true)  // thin space = 1
            } else if scalar == "\u{0020}" {
                bits.append(false) // regular space = 0
            }
        }
        return bitsToBytes(bits)
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

    /// Convert bytes to individual bits (MSB first).
    private static func bytesToBits(_ data: Data) -> [Bool] {
        var bits: [Bool] = []
        bits.reserveCapacity(data.count * 8)
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                bits.append((byte >> shift) & 1 == 1)
            }
        }
        return bits
    }

    /// Convert individual bits back to bytes.
    private static func bitsToBytes(_ bits: [Bool]) -> Data {
        var bytes = Data()
        for i in stride(from: 0, to: bits.count - 7, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if bits[i + j] { byte |= (1 << (7 - j)) }
            }
            bytes.append(byte)
        }
        return bytes
    }
}

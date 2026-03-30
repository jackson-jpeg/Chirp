import UIKit
import CryptoKit
import Foundation

/// Image steganography using PNG least-significant-bit encoding.
///
/// Hides encrypted data in the LSB of RGB pixel values. A 400x400 image
/// has 480,000 color channels — at 1 bit per channel, that's 60KB capacity.
/// Uses PNG (lossless) so LSBs survive encoding. JPEG would destroy them.
enum ImageStego {

    /// Encode hidden data into an image, returning PNG data.
    /// Returns nil if the image doesn't have enough pixel capacity.
    static func encode(image: UIImage, hidden: Data, key: SymmetricKey) -> Data? {
        guard !hidden.isEmpty else { return nil }

        // Encrypt the hidden data
        guard let encrypted = encryptPayload(hidden, key: key) else { return nil }

        // Get raw pixel data
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height

        // Capacity: 3 channels per pixel x 1 bit per channel = 3 bits per pixel
        // First 4 bytes (32 bits) encode the payload length
        let headerBits = 32
        let dataBits = encrypted.count * 8
        let totalBitsNeeded = headerBits + dataBits
        let bitsAvailable = totalPixels * 3
        guard totalBitsNeeded <= bitsAvailable else { return nil }

        // Create a mutable pixel buffer
        let bytesPerPixel = 4 // RGBA
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw original image into context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Build bit stream: [length:32 bits BE] + [encrypted data bits]
        var bitStream: [Bool] = []
        let length = UInt32(encrypted.count)
        for shift in stride(from: 31, through: 0, by: -1) {
            bitStream.append((length >> shift) & 1 == 1)
        }
        for byte in encrypted {
            for shift in stride(from: 7, through: 0, by: -1) {
                bitStream.append((byte >> shift) & 1 == 1)
            }
        }

        // Embed bits into pixel LSBs (R, G, B channels — skip Alpha)
        var bitIndex = 0
        for pixelOffset in 0..<totalPixels {
            let baseIndex = pixelOffset * bytesPerPixel
            // R channel
            if bitIndex < bitStream.count {
                pixelData[baseIndex] = (pixelData[baseIndex] & 0xFE) | (bitStream[bitIndex] ? 1 : 0)
                bitIndex += 1
            }
            // G channel
            if bitIndex < bitStream.count {
                pixelData[baseIndex + 1] = (pixelData[baseIndex + 1] & 0xFE) | (bitStream[bitIndex] ? 1 : 0)
                bitIndex += 1
            }
            // B channel
            if bitIndex < bitStream.count {
                pixelData[baseIndex + 2] = (pixelData[baseIndex + 2] & 0xFE) | (bitStream[bitIndex] ? 1 : 0)
                bitIndex += 1
            }
            if bitIndex >= bitStream.count { break }
        }

        // Create new CGImage from modified pixels
        guard let modifiedImage = context.makeImage() else { return nil }
        let uiImage = UIImage(cgImage: modifiedImage)

        // Encode as PNG (lossless — preserves LSBs)
        return uiImage.pngData()
    }

    /// Decode hidden data from a PNG image.
    /// Returns nil if no hidden data found or decryption fails.
    static func decode(pngData: Data, key: SymmetricKey) -> Data? {
        guard let uiImage = UIImage(data: pngData),
              let cgImage = uiImage.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Extract bits from pixel LSBs
        var bits: [Bool] = []
        let maxBits = min(totalPixels * 3, 32 + 1024 * 1024 * 8) // Cap at 1MB + header

        for pixelOffset in 0..<totalPixels {
            let baseIndex = pixelOffset * bytesPerPixel
            bits.append(pixelData[baseIndex] & 1 == 1)       // R
            bits.append(pixelData[baseIndex + 1] & 1 == 1)   // G
            bits.append(pixelData[baseIndex + 2] & 1 == 1)   // B
            if bits.count >= maxBits { break }
        }

        // Read length header (first 32 bits)
        guard bits.count >= 32 else { return nil }
        var length: UInt32 = 0
        for i in 0..<32 {
            if bits[i] { length |= (1 << (31 - i)) }
        }

        // Sanity check length
        guard length > 0, length <= 1024 * 1024 else { return nil } // Max 1MB
        let dataBitsNeeded = 32 + Int(length) * 8
        guard bits.count >= dataBitsNeeded else { return nil }

        // Extract data bytes
        var encrypted = Data(count: Int(length))
        for byteIndex in 0..<Int(length) {
            var byte: UInt8 = 0
            for bitOffset in 0..<8 {
                let bitPos = 32 + byteIndex * 8 + bitOffset
                if bits[bitPos] { byte |= (1 << (7 - bitOffset)) }
            }
            encrypted[byteIndex] = byte
        }

        // Decrypt
        return decryptPayload(encrypted, key: key)
    }

    /// Check if PNG data potentially contains stego (checks magic + minimal size).
    static func isPNG(_ data: Data) -> Bool {
        // PNG magic: 89 50 4E 47
        guard data.count > 8 else { return false }
        return data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47
    }

    /// Calculate hidden capacity in bytes for an image of given dimensions.
    static func capacity(width: Int, height: Int) -> Int {
        let totalBits = width * height * 3 // 3 channels, 1 bit each
        let dataBits = totalBits - 32 // subtract header
        let totalBytes = dataBits / 8
        return max(0, totalBytes - Constants.CICADA.cryptoOverhead)
    }

    // MARK: - Encryption (same format as TextStego)

    private static func encryptPayload(_ data: Data, key: SymmetricKey) -> Data? {
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
        let start = 3
        guard start + Int(length) <= data.count else { return nil }
        let ciphertext = data[start..<start + Int(length)]
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

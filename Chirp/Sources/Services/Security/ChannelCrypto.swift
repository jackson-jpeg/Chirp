import CryptoKit
import Foundation
import OSLog

/// Handles per-channel encryption using AES-GCM-256.
/// Each channel has its own symmetric key derived from a shared secret.
struct ChannelCrypto: Sendable {
    private let key: SymmetricKey
    private static let logger = Logger(subsystem: "com.chirp.app", category: "ChannelCrypto")

    /// Create crypto for a channel with a specific key
    init(key: SymmetricKey) {
        self.key = key
    }

    /// Generate a new random channel key
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Create an invite code from a channel key + channel ID
    /// Format: base62-encoded (channelID prefix + key material)
    static func createInviteCode(channelID: String, key: SymmetricKey) -> String {
        let keyData = key.withUnsafeBytes { Data($0) }
        // Take first 4 bytes of channel ID hash + 16 bytes of key = 20 bytes
        let channelHash = SHA256.hash(data: Data(channelID.utf8))
        var combined = Data(channelHash.prefix(4))
        combined.append(keyData.prefix(16))
        return combined.base64EncodedString()
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "=", with: "")
            .prefix(12)
            .uppercased()
    }

    /// Reconstruct a channel key from an invite code
    /// Returns nil if the code is invalid
    static func keyFromInviteCode(_ code: String) -> SymmetricKey? {
        // Pad base64 string back
        var base64 = code
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), data.count >= 20 else {
            return nil
        }
        // Extract key material (skip 4-byte channel hash prefix)
        let keyMaterial = data.suffix(from: 4)
        // Expand 16 bytes to 32 bytes via HKDF
        let expanded = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterial),
            outputByteCount: 32
        )
        return expanded
    }

    /// Encrypt data using AES-GCM
    func encrypt(_ plaintext: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        // Return combined: nonce(12) + ciphertext + tag(16)
        return sealedBox.combined!
    }

    /// Decrypt data using AES-GCM
    func decrypt(_ ciphertext: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Sign data with HMAC-SHA256
    func sign(_ data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(mac)
    }

    /// Verify HMAC-SHA256 signature
    func verify(signature: Data, for data: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data, using: key)
    }
}

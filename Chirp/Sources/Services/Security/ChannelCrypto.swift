import CryptoKit
import Foundation
import OSLog

/// Handles per-channel encryption using AES-GCM-256.
/// Each channel has its own symmetric key derived from a shared secret.
struct ChannelCrypto: Sendable {
    private let key: SymmetricKey
    private static let logger = Logger(subsystem: "com.chirpchirp.app", category: "ChannelCrypto")

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

    /// Errors that can occur during encryption operations.
    enum EncryptionError: Error, LocalizedError {
        case sealedBoxCombinedUnavailable

        var errorDescription: String? {
            switch self {
            case .sealedBoxCombinedUnavailable:
                return "Failed to produce combined sealed box representation."
            }
        }
    }

    // MARK: - Epoch Key Derivation

    /// Derive an epoch-specific key via HKDF ratchet.
    /// Each epoch produces a unique key; knowing epoch N's key
    /// does not reveal epoch N-1's key (forward secrecy).
    func epochKey(epoch: UInt32) -> SymmetricKey {
        guard epoch > 0 else { return key }
        var epochBytes = epoch.bigEndian
        let info = withUnsafeBytes(of: &epochBytes) { Data($0) }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data("ChirpKeyRotation".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    /// Encrypt data using AES-GCM with epoch prefix.
    /// Wire format: [epoch:4 BE][AES-GCM nonce+ciphertext+tag]
    func encrypt(_ plaintext: Data, epoch: UInt32 = 0) throws -> Data {
        let encKey = epochKey(epoch: epoch)
        let sealedBox = try AES.GCM.seal(plaintext, using: encKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealedBoxCombinedUnavailable
        }
        var result = Data(capacity: 4 + combined.count)
        var epochBE = epoch.bigEndian
        withUnsafeBytes(of: &epochBE) { result.append(contentsOf: $0) }
        result.append(combined)
        return result
    }

    /// Decrypt data using AES-GCM, reading epoch from prefix.
    /// Tries the embedded epoch, then falls back to lookback epochs.
    func decrypt(_ ciphertext: Data, currentEpoch: UInt32 = 0, lookback: UInt32 = 2) throws -> Data {
        // Legacy format: no epoch prefix (epoch 0)
        guard ciphertext.count > 4 else {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key)
        }

        let embeddedEpoch = UInt32(bigEndian: ciphertext.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) })
        let sealedData = Data(ciphertext.dropFirst(4))

        // Try the embedded epoch first
        let encKey = epochKey(epoch: embeddedEpoch)
        if let sealedBox = try? AES.GCM.SealedBox(combined: sealedData),
           let plaintext = try? AES.GCM.open(sealedBox, using: encKey) {
            return plaintext
        }

        // Lookback: try nearby epochs for in-flight messages during rotation
        let minEpoch = embeddedEpoch > lookback ? embeddedEpoch - lookback : 0
        let maxEpoch = embeddedEpoch + lookback
        for epoch in minEpoch...maxEpoch where epoch != embeddedEpoch {
            let fallbackKey = epochKey(epoch: epoch)
            if let sealedBox = try? AES.GCM.SealedBox(combined: sealedData),
               let plaintext = try? AES.GCM.open(sealedBox, using: fallbackKey) {
                return plaintext
            }
        }

        // Final fallback: try legacy format (no epoch prefix, raw AES-GCM)
        if let sealedBox = try? AES.GCM.SealedBox(combined: ciphertext),
           let plaintext = try? AES.GCM.open(sealedBox, using: key) {
            return plaintext
        }

        throw EncryptionError.sealedBoxCombinedUnavailable
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

    /// Derive a subkey for a specific purpose (e.g., CICADA steganography).
    func deriveSubkey(salt: String, info: Data = Data()) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(salt.utf8),
            info: info,
            outputByteCount: 32
        )
    }

    /// Derive the MeshShield Layer 1 key from an ephemeral public key.
    ///
    /// Binds the ephemeral DH material to the channel key so that only channel
    /// members can strip Layer 1. Without this, the ephemeral public key (sent
    /// in cleartext) would be sufficient to reconstruct the Layer 1 key.
    func deriveLayer1Key(ephemeralKeyData: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ephemeralKeyData),
            salt: Data("ChirpMeshShield-L1".utf8),
            info: key.withUnsafeBytes { Data($0) },
            outputByteCount: 32
        )
    }
}

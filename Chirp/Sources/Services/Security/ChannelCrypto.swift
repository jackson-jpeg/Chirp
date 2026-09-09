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

    // MARK: - Invite Codes (v1)
    //
    // An invite code is base64url(channelID UUID bytes [16] ‖ seed [16]) — a
    // 43-character string with no padding. The seed, not the derived key, is
    // the shared secret: the channel key is HKDF-derived from the seed, bound
    // to the channel ID, so both the creator and anyone holding the code
    // arrive at the same key. The previous scheme truncated the encoding to
    // 12 uppercased characters, which could never be decoded back — invite
    // codes did not round-trip at all.

    /// Byte length of the invite seed embedded in every invite code.
    static let inviteSeedLength = 16

    /// Generate a fresh random invite seed for a locked channel.
    static func generateInviteSeed() -> Data {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
    }

    /// Derive the channel key from an invite seed, bound to the channel ID.
    static func keyFromInviteSeed(_ seed: Data, channelID: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: seed),
            salt: Data("ChirpChannelInvite-v1".utf8),
            info: Data(channelID.utf8),
            outputByteCount: 32
        )
    }

    /// Encode a channel ID + seed into a shareable invite code.
    /// Returns nil if the channel ID is not a UUID or the seed length is wrong.
    static func createInviteCode(channelID: String, seed: Data) -> String? {
        guard let uuid = UUID(uuidString: channelID),
              seed.count == inviteSeedLength else {
            return nil
        }
        var combined = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        combined.append(seed)
        return base64URLEncode(combined)
    }

    /// Decode an invite code back into its channel ID, seed, and derived key.
    /// Returns nil for anything that is not a well-formed v1 code.
    static func parseInviteCode(_ code: String) -> (channelID: String, seed: Data, key: SymmetricKey)? {
        guard let data = base64URLDecode(code), data.count == 16 + inviteSeedLength else {
            return nil
        }
        let bytes = [UInt8](data.prefix(16))
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        let channelID = uuid.uuidString
        let seed = Data(data.suffix(inviteSeedLength))
        return (channelID, seed, keyFromInviteSeed(seed, channelID: channelID))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
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

        // Byte-by-byte, offset-relative: see Data.readBigEndian. `count > 4` is
        // already guaranteed above, so nil here would mean the guard changed.
        guard let embeddedEpoch = ciphertext.readBigEndian(UInt32.self, at: 0) else {
            throw EncryptionError.sealedBoxCombinedUnavailable
        }
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
}

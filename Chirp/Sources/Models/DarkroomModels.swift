import CryptoKit
import Foundation

// MARK: - DarkroomCrypto

/// Crypto operations for view-once photos using ephemeral ECDH key agreement.
///
/// Forward secrecy is achieved by generating a fresh Curve25519 keypair for every
/// photo. The ephemeral private key is destroyed immediately after the shared
/// secret is derived, so even if long-term keys are later compromised the
/// ciphertext remains safe.
enum DarkroomCrypto {

    // MARK: - Types

    struct SealedPhoto: Codable, Sendable {
        /// 32-byte Curve25519 ephemeral public key used for ECDH.
        let ephemeralPublicKey: Data
        /// AES-GCM-256 combined representation (nonce + ciphertext + tag).
        let ciphertext: Data
        /// Sender's Ed25519 signing public key (identity verification).
        let senderSigningKey: Data
        /// Ed25519 signature over `ciphertext` proving sender authenticity.
        let signature: Data
    }

    enum DarkroomCryptoError: Error, Sendable {
        case sealFailed
        case invalidSignature
        case decryptionFailed
    }

    // MARK: - Seal

    /// Encrypt photo data for a specific recipient using ephemeral ECDH.
    ///
    /// 1. Generate ephemeral Curve25519.KeyAgreement keypair
    /// 2. ECDH with recipient's public key -> SharedSecret
    /// 3. HKDF derive AES-256 key
    /// 4. AES-GCM seal
    /// 5. Sign ciphertext with sender's Ed25519 signing key
    /// 6. Ephemeral private key destroyed (goes out of scope)
    static func seal(
        photoData: Data,
        recipientPublicKey: Curve25519.KeyAgreement.PublicKey,
        senderSigningKey: Curve25519.Signing.PrivateKey
    ) throws -> SealedPhoto {
        // 1. Ephemeral keypair — private key lives only in this scope.
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralPrivateKey.publicKey

        // 2. ECDH shared secret.
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientPublicKey
        )

        // 3. HKDF-SHA256 key derivation.
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("ChirpDarkroom-v1".utf8),
            sharedInfo: ephemeralPublicKey.rawRepresentation + recipientPublicKey.rawRepresentation,
            outputByteCount: 32
        )

        // 4. AES-GCM-256 encryption.
        let sealedBox = try AES.GCM.seal(photoData, using: symmetricKey)
        guard let combined = sealedBox.combined else {
            throw DarkroomCryptoError.sealFailed
        }

        // 5. Sign ciphertext with sender's identity key.
        let signature = try senderSigningKey.signature(for: combined)

        // 6. Ephemeral private key is destroyed here (end of scope).
        return SealedPhoto(
            ephemeralPublicKey: ephemeralPublicKey.rawRepresentation,
            ciphertext: combined,
            senderSigningKey: senderSigningKey.publicKey.rawRepresentation,
            signature: Data(signature)
        )
    }

    // MARK: - Open

    /// Decrypt a sealed photo using the recipient's key-agreement private key.
    ///
    /// Verifies the sender's Ed25519 signature before returning plaintext.
    static func open(
        sealed: SealedPhoto,
        recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // Verify sender signature.
        let signingPublicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: sealed.senderSigningKey
        )
        guard signingPublicKey.isValidSignature(sealed.signature, for: sealed.ciphertext) else {
            throw DarkroomCryptoError.invalidSignature
        }

        // Reconstruct ECDH shared secret.
        let ephemeralPublicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: sealed.ephemeralPublicKey
        )
        let sharedSecret = try recipientPrivateKey.sharedSecretFromKeyAgreement(
            with: ephemeralPublicKey
        )

        // HKDF-SHA256 key derivation (same parameters as seal).
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("ChirpDarkroom-v1".utf8),
            sharedInfo: ephemeralPublicKey.rawRepresentation + recipientPrivateKey.publicKey.rawRepresentation,
            outputByteCount: 32
        )

        // AES-GCM-256 decryption.
        let sealedBox = try AES.GCM.SealedBox(combined: sealed.ciphertext)
        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw DarkroomCryptoError.decryptionFailed
        }
    }
}

// MARK: - DarkroomEnvelope

/// Wire envelope for a view-once photo sent over the mesh network.
///
/// Contains the sealed photo, sender metadata, and an expiry timestamp.
/// Prefixed with `DRK!` magic bytes in the mesh packet payload.
struct DarkroomEnvelope: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let recipientID: String
    let sealedPhoto: DarkroomCrypto.SealedPhoto
    /// SHA-256 hash of the original JPEG data for post-decryption verification.
    let thumbnailHash: Data
    let timestamp: Date
    /// Default 24 h from creation.
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }

    /// ASCII: `DRK!`
    static let magicPrefix: [UInt8] = [0x44, 0x52, 0x4B, 0x21]

    /// Encode this envelope as wire-ready data: magic prefix + JSON.
    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``DarkroomEnvelope`` from a mesh packet payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> DarkroomEnvelope? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(DarkroomEnvelope.self, from: Data(json))
    }
}

// MARK: - DarkroomViewACK

/// Acknowledgement sent back to the sender after a view-once photo has been viewed.
///
/// On receipt the sender knows the photo was opened and can update UI accordingly.
/// Prefixed with `DVK!` magic bytes in the mesh packet payload.
struct DarkroomViewACK: Codable, Sendable {
    let envelopeID: UUID
    let viewerPeerID: String
    let viewedAt: Date

    /// ASCII: `DVK!`
    static let magicPrefix: [UInt8] = [0x44, 0x56, 0x4B, 0x21]

    /// Encode this ACK as wire-ready data: magic prefix + JSON.
    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``DarkroomViewACK`` from a mesh packet payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> DarkroomViewACK? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(DarkroomViewACK.self, from: Data(json))
    }
}

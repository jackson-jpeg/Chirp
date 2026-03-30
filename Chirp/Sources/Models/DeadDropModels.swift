import CryptoKit
import Foundation

// MARK: - DeadDropMessage

/// An encrypted message anchored to a geographic location.
///
/// Dead drops are encrypted with a key derived from the precise geohash of the
/// drop location, so only someone physically present at that spot can decrypt
/// the message. Optional time-locking folds a date string into the key
/// derivation so the message cannot be opened before a specific day.
struct DeadDropMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    /// AES-GCM ciphertext produced by ``DeadDropCrypto/seal(_:geohash:date:)``.
    let encryptedPayload: Data
    /// First 4 characters of the full geohash — used for coarse-area routing
    /// so relay nodes only store drops that are geographically relevant.
    let geohashPrefix: String
    let timestamp: Date
    let expiresAt: Date
    /// When `true` the key derivation includes ``timeLockDate``.
    let isTimeLocked: Bool
    /// ISO date string (`YYYY-MM-DD`) folded into HKDF info when time-locked.
    let timeLockDate: String?
    /// Indicates this drop is part of a scavenger-hunt chain with a next hint.
    let hasNextHint: Bool

    // MARK: - Wire format

    /// Magic bytes prepended to JSON before placing into ``MeshPacket/payload``.
    /// ASCII: `DRP!`
    static let magicPrefix: [UInt8] = [0x44, 0x52, 0x50, 0x21]

    /// Encode this message as wire-ready data: magic prefix + JSON.
    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``DeadDropMessage`` from a mesh packet payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> DeadDropMessage? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(DeadDropMessage.self, from: Data(json))
    }
}

// MARK: - DeadDropPickup

/// Acknowledgement broadcast when a peer successfully picks up a dead drop.
///
/// Relay nodes that receive this can prune the corresponding stored drop.
struct DeadDropPickup: Codable, Sendable {
    let dropID: UUID
    let pickerPeerID: String
    let timestamp: Date

    /// ASCII: `DPK!`
    static let magicPrefix: [UInt8] = [0x44, 0x50, 0x4B, 0x21]

    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    static func from(payload: Data) -> DeadDropPickup? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(DeadDropPickup.self, from: Data(json))
    }
}

// MARK: - DropChainHint

/// Hint embedded in a dead drop that points to the next drop in a scavenger hunt.
struct DropChainHint: Codable, Sendable {
    /// Human-readable clue (e.g. "Look under the bridge by 3rd and Main").
    let hintText: String
    /// Optional precise coordinates for the next drop.
    let nextLatitude: Double?
    let nextLongitude: Double?
    /// Optional time-lock date for the next drop in the chain.
    let nextTimeLockDate: String?
}

// MARK: - DeadDropCrypto

/// Crypto operations for dead drops using geohash-derived symmetric keys.
///
/// The key is derived via HKDF-SHA256 from the geohash string itself, meaning
/// only someone who computes the same geohash (i.e. is at the same location)
/// can decrypt the payload.
enum DeadDropCrypto {

    /// Derive a 256-bit symmetric key from a geohash string.
    ///
    /// When `date` is provided (format `YYYY-MM-DD`) it is appended to the
    /// HKDF info parameter, producing a different key for each calendar day.
    static func deriveKey(geohash: String, date: String? = nil) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(geohash.utf8))
        var info = Data("DeadDrop-v1".utf8)
        if let date {
            info.append(Data(date.utf8))
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data("ChirpDeadDrop".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    /// Encrypt plaintext using AES-GCM with a geohash-derived key.
    ///
    /// Returns the combined representation (nonce + ciphertext + tag).
    static func seal(_ plaintext: Data, geohash: String, date: String? = nil) throws -> Data {
        let key = deriveKey(geohash: geohash, date: date)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw DeadDropCryptoError.sealFailed
        }
        return combined
    }

    /// Decrypt ciphertext using AES-GCM with a geohash-derived key.
    ///
    /// Returns `nil` if the key is wrong (authentication tag mismatch).
    static func open(_ ciphertext: Data, geohash: String, date: String? = nil) -> Data? {
        let key = deriveKey(geohash: geohash, date: date)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: ciphertext) else {
            return nil
        }
        return try? AES.GCM.open(sealedBox, using: key)
    }

    enum DeadDropCryptoError: Error {
        case sealFailed
    }
}

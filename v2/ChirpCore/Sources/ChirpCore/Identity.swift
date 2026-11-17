import CryptoKit
import Foundation

// One identity model for 2.0 (audit section 5: 1.0 had three, display name,
// routing UUID and key fingerprint, and friends, the nearby list and blocking
// disagreed because each used a different one).
//
// A person is their signing key. `PeerID` is derived from it and is the only
// key anything in 2.0 is stored or looked up under: the roster, the block list,
// the floor, texts, acks. A display name is a label carried alongside, never a key.

/// 16 bytes of SHA-256 over the Ed25519 signing public key.
public struct PeerID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let byteCount = 16
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = Data(bytes)
    }

    /// The ID a signing public key maps to. The one place this is computed.
    public init(signingPublicKey: Data) {
        self.bytes = Data(SHA256.hash(data: signingPublicKey).prefix(Self.byteCount))
    }

    /// Lowercase hex, 32 characters.
    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    public init?(hex: String) {
        guard hex.count == Self.byteCount * 2 else { return nil }
        var out = Data(capacity: Self.byteCount)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        self.init(bytes: out)
    }

    /// Short form for people to compare out loud ("a1b2 c3d4").
    public var shortCode: String {
        let h = hex
        return "\(h.prefix(4)) \(h.dropFirst(4).prefix(4))"
    }

    public var description: String { hex }

    public static func < (lhs: PeerID, rhs: PeerID) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }
}

/// Where the private keys live. The app's implementation is the Keychain
/// (this-device-only, so a block keyed to the identity survives a reinstall
/// only as far as the Keychain item does: audit H19); tests use memory.
public protocol KeyStore: Sendable {
    func load(_ account: String) -> Data?
    func save(_ data: Data, account: String) throws
}

/// This device's identity: a signing key (who I am) and an agreement key (so
/// a peer can seal something to me alone, such as a check-in position).
public struct LocalIdentity: Sendable {
    public static let signingAccount = "chirp2.ed25519"
    public static let agreementAccount = "chirp2.x25519"

    public let signingKey: Curve25519.Signing.PrivateKey
    public let agreementKey: Curve25519.KeyAgreement.PrivateKey

    public var peerID: PeerID { PeerID(signingPublicKey: signingKey.publicKey.rawRepresentation) }
    public var signingPublicKey: Data { signingKey.publicKey.rawRepresentation }
    public var agreementPublicKey: Data { agreementKey.publicKey.rawRepresentation }

    public init(signingKey: Curve25519.Signing.PrivateKey, agreementKey: Curve25519.KeyAgreement.PrivateKey) {
        self.signingKey = signingKey
        self.agreementKey = agreementKey
    }

    /// Load both keys, creating and saving any that are missing.
    public static func loadOrCreate(from store: KeyStore) throws -> LocalIdentity {
        let signing: Curve25519.Signing.PrivateKey
        if let raw = store.load(signingAccount),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            signing = key
        } else {
            signing = Curve25519.Signing.PrivateKey()
            try store.save(signing.rawRepresentation, account: signingAccount)
        }
        let agreement: Curve25519.KeyAgreement.PrivateKey
        if let raw = store.load(agreementAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            agreement = key
        } else {
            agreement = Curve25519.KeyAgreement.PrivateKey()
            try store.save(agreement.rawRepresentation, account: agreementAccount)
        }
        return LocalIdentity(signingKey: signing, agreementKey: agreement)
    }

    public func sign(_ data: Data) throws -> Data {
        try signingKey.signature(for: data)
    }

    public static func verify(signature: Data, of data: Data, signingPublicKey: Data) -> Bool {
        guard signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: data)
    }

    /// The symmetric key shared with one peer (X25519 then HKDF). Both sides
    /// reach the same key from opposite halves, with no handshake.
    public func sharedKey(with peerAgreementPublicKey: Data, purpose: String) -> SymmetricKey? {
        guard let peerKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerAgreementPublicKey),
              let secret = try? agreementKey.sharedSecretFromKeyAgreement(with: peerKey) else {
            return nil
        }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("chirp2.pairwise".utf8),
            sharedInfo: Data(purpose.utf8),
            outputByteCount: 32
        )
    }
}

/// In-memory key store for tests and Demo Mode.
public final class MemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    public init() {}
    public func load(_ account: String) -> Data? { lock.withLock { items[account] } }
    public func save(_ data: Data, account: String) throws { lock.withLock { items[account] = data } }
}

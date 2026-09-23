import CryptoKit
import Foundation
import Security
import OSLog

/// Manages the local device's cryptographic identity.
/// Ed25519 keypair stored in iOS Keychain for persistence across installs.
actor PeerIdentity {
    static let shared = PeerIdentity()

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "PeerIdentity")
    private let keychainService = "com.chirpchirp.peerIdentity"
    private let keychainAccount = "ed25519-private-key"

    /// Keychain account for the X25519 key agreement private key.
    ///
    /// Deliberately a second item rather than a reuse of the Ed25519 key:
    /// signing and key agreement are different primitives, and Apple's
    /// requirement that a blocked peer cannot read our position needs a
    /// per-recipient sealed box, which a signing key cannot produce.
    private let agreementKeychainAccount = "x25519-agreement-private-key"

    private var _privateKey: Curve25519.Signing.PrivateKey?
    private var _agreementKey: Curve25519.KeyAgreement.PrivateKey?

    /// The local peer's public key fingerprint (first 8 bytes of SHA256, hex-encoded)
    var fingerprint: String {
        get async {
            let key = getOrCreatePrivateKey()
            let hash = SHA256.hash(data: key.publicKey.rawRepresentation)
            return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// The local peer's public key for sharing with peers
    var publicKey: Curve25519.Signing.PublicKey {
        get async {
            let key = getOrCreatePrivateKey()
            return key.publicKey
        }
    }

    /// Export public key as Data for transmission
    var publicKeyData: Data {
        get async {
            let key = getOrCreatePrivateKey()
            return key.publicKey.rawRepresentation
        }
    }

    /// Sign data with our private key
    func sign(_ data: Data) async throws -> Data {
        let key = getOrCreatePrivateKey()
        let signature = try key.signature(for: data)
        return Data(signature)
    }

    /// Verify a signature from a peer's public key
    func verify(signature: Data, data: Data, publicKey: Data) -> Bool {
        guard let peerKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        guard signature.count == 64 else { return false }
        return peerKey.isValidSignature(signature, for: data)
    }

    // MARK: - Key Agreement (position sealing)

    /// This device's X25519 public key, as it travels in every beacon.
    ///
    /// A public key is public: publishing it in plaintext is what lets a peer
    /// seal a position *to* this device, which is the whole mechanism. What
    /// must never travel in plaintext is the coordinate itself.
    var agreementPublicKey: Data {
        get async {
            getOrCreateAgreementKey().publicKey.rawRepresentation
        }
    }

    /// Derive the symmetric key this device shares with `peerAgreementPublicKey`.
    ///
    /// X25519 shared secret -> HKDF-SHA256. The derivation is commutative by
    /// construction — both sides reach the same bytes from opposite halves of
    /// the pair — which is what allows a sender to seal a coordinate that only
    /// the addressed peer can open, with no handshake and no round trip on a
    /// mesh where there may not be one.
    func sharedPositionKey(with peerAgreementPublicKey: Data) -> SymmetricKey? {
        BeaconIdentity.derivePositionKey(
            privateKey: getOrCreateAgreementKey(),
            peerAgreementPublicKey: peerAgreementPublicKey
        )
    }

    /// The wire-facing bundle of both keys, for the main-actor code that has
    /// to sign and seal on every beacon tick.
    ///
    /// ``MeshBeacon`` broadcasts every ~2s from the main actor and cannot
    /// `await` this actor in that path, so it is handed a value object holding
    /// the same keys plus a derived-key cache. Nothing here is copied out that
    /// is not already needed to put a beacon on the wire.
    func beaconIdentity() -> BeaconIdentity {
        BeaconIdentity(
            signingKey: getOrCreatePrivateKey(),
            agreementKey: getOrCreateAgreementKey()
        )
    }

    // MARK: - Keychain Management

    private func getOrCreateAgreementKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = _agreementKey {
            return existing
        }

        if let keyData = loadFromKeychain(account: agreementKeychainAccount),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData) {
            _agreementKey = key
            logger.info("Loaded key agreement identity from Keychain")
            return key
        }

        let key = Curve25519.KeyAgreement.PrivateKey()
        _agreementKey = key
        saveToKeychain(key.rawRepresentation, account: agreementKeychainAccount)
        logger.info("Generated new key agreement identity")
        return key
    }

    private func getOrCreatePrivateKey() -> Curve25519.Signing.PrivateKey {
        if let existing = _privateKey {
            return existing
        }

        // Try loading from Keychain
        if let keyData = loadFromKeychain() {
            if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) {
                _privateKey = key
                logger.info("Loaded identity from Keychain")
                return key
            }
        }

        // Generate new keypair
        let key = Curve25519.Signing.PrivateKey()
        _privateKey = key
        saveToKeychain(key.rawRepresentation)
        logger.info("Generated new peer identity")
        return key
    }

    private func saveToKeychain(_ data: Data) {
        saveToKeychain(data, account: keychainAccount)
    }

    private func saveToKeychain(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save identity to Keychain (\(account)): \(status)")
        }
    }

    private func loadFromKeychain() -> Data? {
        loadFromKeychain(account: keychainAccount)
    }

    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

// MARK: - Wire-facing identity

/// The half of ``PeerIdentity`` that goes on the wire, plus the two
/// operations a beacon needs on every tick: attesting who we are, and sealing
/// a coordinate that exactly one named peer can open.
///
/// This exists as a separate object because ``MeshBeacon`` is `@MainActor` and
/// broadcasts every ~2 seconds. It cannot `await` an actor inside that loop,
/// so ``PeerIdentity/beaconIdentity()`` hands it an immutable bundle of the
/// same keys. The X25519 derivations are cached per peer public key: a 20-node
/// mesh would otherwise re-run 20 scalar multiplications twice a second for
/// keys that never change.
final class BeaconIdentity: @unchecked Sendable {

    // MARK: Domain separation
    //
    // Fixed salt and info strings, versioned so a future key schedule can be
    // told apart from this one on a mesh running mixed builds. They are
    // constants rather than derived from the peers, because the derivation
    // must be commutative: A deriving with B's public key has to land on the
    // same bytes as B deriving with A's, and anything asymmetric in the salt
    // or info (peer IDs in a fixed order, say) breaks exactly that.

    /// HKDF salt for the per-recipient position key.
    static let positionSalt = Data("ChirpPositionSeal-v1".utf8)

    /// HKDF info for the per-recipient position key.
    static let positionInfo = Data("chirp.beacon.position".utf8)

    /// Prefix of the statement a beacon signs to bind its routing UUID,
    /// fingerprint and agreement key to its Ed25519 identity.
    static let identityStatementPrefix = "chirp.beacon.identity.v1"

    // MARK: Keys

    private let signingKey: Curve25519.Signing.PrivateKey
    private let agreementKey: Curve25519.KeyAgreement.PrivateKey

    /// Ed25519 public key, 32 bytes. Published so peers can verify the
    /// attestation and so the fingerprint can be recomputed rather than
    /// believed.
    let signingPublicKey: Data

    /// X25519 public key, 32 bytes. Published so peers can seal to us.
    let agreementPublicKey: Data

    /// First 8 bytes of SHA-256 over ``signingPublicKey``, hex-encoded — the
    /// same string the settings screen shows, and the stable identity a block
    /// is keyed to. A display name can be changed at will; this cannot,
    /// without also abandoning the keypair.
    let fingerprint: String

    private let lock = NSLock()
    private var derivedKeys: [Data: SymmetricKey] = [:]

    init(signingKey: Curve25519.Signing.PrivateKey, agreementKey: Curve25519.KeyAgreement.PrivateKey) {
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        self.signingPublicKey = signingKey.publicKey.rawRepresentation
        self.agreementPublicKey = agreementKey.publicKey.rawRepresentation
        self.fingerprint = Self.fingerprint(forSigningPublicKey: signingKey.publicKey.rawRepresentation)
    }

    /// An identity backed by fresh in-memory keys.
    ///
    /// Used by tests, and by the seeding paths (Demo Mode, screenshot seeding)
    /// that manufacture beacons attributed to peers whose private keys this
    /// device obviously does not hold. Such a beacon seals a position but
    /// never claims an identity — see ``MeshBeacon/encodeBeacon(_:)``.
    convenience init() {
        self.init(
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: Curve25519.KeyAgreement.PrivateKey()
        )
    }

    // MARK: Fingerprint

    static func fingerprint(forSigningPublicKey key: Data) -> String {
        SHA256.hash(data: key).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Attestation

    /// The exact bytes a beacon signs. Field separators are literal `|`, and
    /// none of the three fields can contain one (a UUID string, a hex
    /// fingerprint and base64), so the statement is unambiguous.
    static func identityStatement(
        routingID: String,
        fingerprint: String,
        agreementPublicKey: Data
    ) -> Data {
        Data("\(identityStatementPrefix)|\(routingID)|\(fingerprint)|\(agreementPublicKey.base64EncodedString())".utf8)
    }

    /// Sign the statement binding this identity to `routingID`.
    func attest(routingID: String) -> Data? {
        let statement = Self.identityStatement(
            routingID: routingID,
            fingerprint: fingerprint,
            agreementPublicKey: agreementPublicKey
        )
        return try? Data(signingKey.signature(for: statement))
    }

    /// Verify a peer's attestation. Returns the verified fingerprint, or nil.
    ///
    /// Two checks, both required. The fingerprint is *recomputed* from the
    /// advertised signing key rather than taken at face value, so a peer
    /// cannot claim someone else's fingerprint; and the signature proves the
    /// holder of that signing key really did bind this routing UUID and this
    /// agreement key together, so a relay cannot swap either in flight.
    static func verifyAttestation(
        routingID: String,
        claimedFingerprint: String,
        signingPublicKey: Data,
        agreementPublicKey: Data,
        signature: Data
    ) -> String? {
        guard signature.count == 64,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)
        else { return nil }

        let recomputed = fingerprint(forSigningPublicKey: signingPublicKey)
        guard recomputed == claimedFingerprint else { return nil }

        let statement = identityStatement(
            routingID: routingID,
            fingerprint: recomputed,
            agreementPublicKey: agreementPublicKey
        )
        guard publicKey.isValidSignature(signature, for: statement) else { return nil }
        return recomputed
    }

    // MARK: Key agreement

    /// The shared key between `privateKey` and `peerAgreementPublicKey`.
    /// Static so a test can prove commutativity from both sides.
    static func derivePositionKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerAgreementPublicKey: Data
    ) -> SymmetricKey? {
        guard let peerKey = try? Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: peerAgreementPublicKey
        ) else { return nil }
        guard let secret = try? privateKey.sharedSecretFromKeyAgreement(with: peerKey) else {
            return nil
        }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: positionSalt,
            sharedInfo: positionInfo,
            outputByteCount: 32
        )
    }

    /// Cached form of ``derivePositionKey(privateKey:peerAgreementPublicKey:)``.
    func positionKey(forPeerAgreementKey peerAgreementPublicKey: Data) -> SymmetricKey? {
        lock.lock()
        if let cached = derivedKeys[peerAgreementPublicKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let derived = Self.derivePositionKey(
            privateKey: agreementKey,
            peerAgreementPublicKey: peerAgreementPublicKey
        ) else { return nil }

        lock.lock()
        derivedKeys[peerAgreementPublicKey] = derived
        lock.unlock()
        return derived
    }

    // MARK: Sealing a coordinate

    /// Wire form of a coordinate: two big-endian IEEE-754 doubles, 16 bytes.
    ///
    /// Fixed width on purpose. A sealed box whose length varies with the
    /// value leaks something about the value; every position seals to exactly
    /// the same number of bytes.
    static func coordinateBytes(latitude: Double, longitude: Double) -> Data {
        var data = Data(capacity: 16)
        withUnsafeBytes(of: latitude.bitPattern.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: longitude.bitPattern.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    static func coordinate(fromBytes data: Data) -> LocationBroadcastGate.Coordinate? {
        guard data.count == 16 else { return nil }
        let bytes = [UInt8](data)
        func double(at offset: Int) -> Double {
            var pattern: UInt64 = 0
            for index in 0..<8 { pattern = (pattern << 8) | UInt64(bytes[offset + index]) }
            return Double(bitPattern: pattern)
        }
        let latitude = double(at: 0)
        let longitude = double(at: 8)
        guard latitude.isFinite, longitude.isFinite else { return nil }
        return LocationBroadcastGate.Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Seal a coordinate for one recipient.
    ///
    /// `context` is authenticated but not encrypted: it carries the sender and
    /// recipient routing IDs, so an entry lifted out of one beacon cannot be
    /// replayed as another peer's position or re-addressed to someone else.
    func sealCoordinate(
        latitude: Double,
        longitude: Double,
        forPeerAgreementKey peerAgreementPublicKey: Data,
        context: Data
    ) -> Data? {
        guard let key = positionKey(forPeerAgreementKey: peerAgreementPublicKey) else { return nil }
        let plaintext = Self.coordinateBytes(latitude: latitude, longitude: longitude)
        guard let box = try? AES.GCM.seal(plaintext, using: key, authenticating: context) else {
            return nil
        }
        return box.combined
    }

    /// Open a coordinate addressed to us, or nil for anything that does not
    /// authenticate — wrong key, wrong context, truncated box, garbage.
    func openCoordinate(
        _ sealed: Data,
        fromPeerAgreementKey peerAgreementPublicKey: Data,
        context: Data
    ) -> LocationBroadcastGate.Coordinate? {
        guard let key = positionKey(forPeerAgreementKey: peerAgreementPublicKey) else { return nil }
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let plaintext = try? AES.GCM.open(box, using: key, authenticating: context)
        else { return nil }
        return Self.coordinate(fromBytes: plaintext)
    }
}

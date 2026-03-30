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
    private let keyAgreementKeychainAccount = "curve25519-keyagreement-key"

    private var _privateKey: Curve25519.Signing.PrivateKey?
    private var _keyAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey?

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

    // MARK: - Key Agreement (Darkroom)

    /// The local peer's Curve25519 key-agreement public key for Darkroom ECDH.
    var keyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey {
        get async {
            let key = getOrCreateKeyAgreementPrivateKey()
            return key.publicKey
        }
    }

    /// Export key-agreement public key as Data for transmission.
    var keyAgreementPublicKeyData: Data {
        get async {
            let key = getOrCreateKeyAgreementPrivateKey()
            return key.publicKey.rawRepresentation
        }
    }

    /// Return the key-agreement private key for Darkroom decryption.
    func getKeyAgreementPrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        getOrCreateKeyAgreementPrivateKey()
    }

    /// Return the signing private key (e.g. for Darkroom photo signing).
    func getSigningPrivateKey() -> Curve25519.Signing.PrivateKey {
        getOrCreatePrivateKey()
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

    // MARK: - Keychain Management

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

    private func getOrCreateKeyAgreementPrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = _keyAgreementPrivateKey {
            return existing
        }

        // Try loading from Keychain.
        if let keyData = loadFromKeychain(account: keyAgreementKeychainAccount) {
            if let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData) {
                _keyAgreementPrivateKey = key
                logger.info("Loaded key-agreement identity from Keychain")
                return key
            }
        }

        // Generate new keypair.
        let key = Curve25519.KeyAgreement.PrivateKey()
        _keyAgreementPrivateKey = key
        saveToKeychain(key.rawRepresentation, account: keyAgreementKeychainAccount)
        logger.info("Generated new key-agreement identity")
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

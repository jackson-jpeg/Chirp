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

    private var _privateKey: Curve25519.Signing.PrivateKey?

    /// The local peer's public key fingerprint (first 8 bytes of SHA256, hex-encoded)
    var fingerprint: String {
        get async {
            let key = await getOrCreatePrivateKey()
            let hash = SHA256.hash(data: key.publicKey.rawRepresentation)
            return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// The local peer's public key for sharing with peers
    var publicKey: Curve25519.Signing.PublicKey {
        get async {
            let key = await getOrCreatePrivateKey()
            return key.publicKey
        }
    }

    /// Export public key as Data for transmission
    var publicKeyData: Data {
        get async {
            let key = await getOrCreatePrivateKey()
            return key.publicKey.rawRepresentation
        }
    }

    /// Sign data with our private key
    func sign(_ data: Data) async throws -> Data {
        let key = await getOrCreatePrivateKey()
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

    private func saveToKeychain(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save identity to Keychain: \(status)")
        }
    }

    private func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

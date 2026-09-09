import Foundation
import OSLog
import Security

/// Keychain storage for locked-channel invite seeds.
///
/// The 16-byte seed is the channel's shared secret: both the AES key and the
/// invite code are derived from it (see ``ChannelCrypto``). Seeds are stored
/// with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, keeping them out
/// of iCloud Keychain and device backups — a locked channel's key never
/// leaves the device except as an invite code the user shares deliberately.
enum ChannelKeyStore: Sendable {

    private static let logger = Logger(subsystem: Constants.subsystem, category: "ChannelKeyStore")
    private static let service = "com.chirpchirp.channelkeys"

    /// Store (or replace) the seed for a channel. Returns false on Keychain failure.
    @discardableResult
    static func storeSeed(_ seed: Data, for channelID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID,
            kSecValueData as String: seed,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Remove any existing item first (idempotent).
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to store channel seed (status \(status))")
        }
        return status == errSecSuccess
    }

    /// Load the seed for a channel, or nil if none is stored.
    static func loadSeed(for channelID: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    /// Delete the seed for a channel. Safe to call when none exists.
    static func deleteSeed(for channelID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: channelID
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete channel seed (status \(status))")
        }
    }
}

import Foundation
import Security
import OSLog

/// Manages the device-specific database encryption key in the Keychain.
///
/// The key is a 32-byte random value stored as a 64-character hex string.
/// It never leaves the device and is excluded from iCloud Keychain backup
/// via `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
enum KeychainHelper: Sendable {

    private static let logger = Logger(subsystem: Constants.subsystem, category: "MessageDB")
    private static let service = "com.chirpchirp.messagedb"
    private static let account = "db-encryption-key"

    /// Returns the existing database encryption key, or generates and stores a new one.
    static func getOrCreateDatabaseKey() -> String {
        if let existing = retrieveKey() {
            return existing
        }

        let newKey = generateRandomHexKey()
        let stored = storeKey(newKey)
        if !stored {
            logger.error("Failed to store database key in Keychain")
        }
        return newKey
    }

    // MARK: - Private

    private static func generateRandomHexKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            logger.fault("SecRandomCopyBytes failed with status \(status)")
            // Fallback: UUID-based key (less entropy but never crashes)
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func storeKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Remove any existing item first (idempotent).
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func retrieveKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }
}

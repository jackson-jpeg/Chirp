import ChirpCore
import Foundation

/// Your birdhouse, kept across launches as its invite link in the Keychain
/// (this device only): the link holds the birdhouse's key, so it never goes
/// to UserDefaults or a backup.
struct BirdhouseStore {
    let keychain = KeychainStore()
    private let account = "birdhouse"
    /// Where TestFlight builds up to 202611172156 kept it, before the group
    /// was renamed. Read once, moved to `account`, then deleted.
    private let legacyAccount = "flock"

    func load() -> Channel? {
        if keychain.load(account) == nil, let old = keychain.load(legacyAccount) {
            try? keychain.save(old, account: account)
            keychain.delete(legacyAccount)
        }
        guard let data = keychain.load(account), let text = String(data: data, encoding: .utf8) else { return nil }
        return BirdhouseInvite.parse(text)
    }

    func save(_ channel: Channel?) {
        keychain.delete(legacyAccount)
        guard let channel, let link = BirdhouseInvite.link(for: channel) else {
            keychain.delete(account)
            return
        }
        try? keychain.save(Data(link.absoluteString.utf8), account: account)
    }
}

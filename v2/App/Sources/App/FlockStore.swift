import ChirpCore
import Foundation

/// Your flock, kept across launches as its invite link in the Keychain
/// (this device only): the link holds the flock's key, so it never goes
/// to UserDefaults or a backup.
struct FlockStore {
    let keychain = KeychainStore()
    private let account = "flock"

    func load() -> Channel? {
        guard let data = keychain.load(account), let text = String(data: data, encoding: .utf8) else { return nil }
        return FlockInvite.parse(text)
    }

    func save(_ channel: Channel?) {
        guard let channel, let link = FlockInvite.link(for: channel) else {
            keychain.delete(account)
            return
        }
        try? keychain.save(Data(link.absoluteString.utf8), account: account)
    }
}

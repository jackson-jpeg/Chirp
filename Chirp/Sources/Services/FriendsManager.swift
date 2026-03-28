import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class FriendsManager {

    // MARK: - Properties

    private(set) var friends: [ChirpFriend] = []

    var onlineFriends: [ChirpFriend] {
        friends.filter(\.isOnline)
    }

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "FriendsManager")
    private let storageKey = "com.chirpchirp.friends"

    // MARK: - Init

    init() {
        loadFriends()
        logger.info("FriendsManager initialized — \(self.friends.count) friends loaded")
    }

    // MARK: - Public API

    func addFriend(id: String, name: String) {
        guard !friends.contains(where: { $0.id == id }) else {
            logger.info("Friend '\(name)' already exists, skipping")
            return
        }

        let friend = ChirpFriend(
            id: id,
            name: name,
            addedAt: Date()
        )
        friends.append(friend)
        saveFriends()
        logger.info("Added friend '\(name)' (\(id))")
    }

    func removeFriend(id: String) {
        friends.removeAll { $0.id == id }
        saveFriends()
        logger.info("Removed friend \(id)")
    }

    func updateOnlineStatus(peerID: String, isOnline: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == peerID }) else { return }

        let wasOnline = friends[index].isOnline
        friends[index].isOnline = isOnline

        if isOnline {
            friends[index].lastSeen = Date()
        }

        if wasOnline != isOnline {
            saveFriends()
            logger.info("Friend \(peerID) is now \(isOnline ? "online" : "offline")")
        }
    }

    func isFriend(peerID: String) -> Bool {
        friends.contains { $0.id == peerID }
    }

    func friend(withID id: String) -> ChirpFriend? {
        friends.first { $0.id == id }
    }

    // MARK: - Persistence

    private func saveFriends() {
        do {
            let data = try JSONEncoder().encode(friends)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save friends: \(error.localizedDescription)")
        }
    }

    private func loadFriends() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            friends = try JSONDecoder().decode([ChirpFriend].self, from: data)
        } catch {
            logger.error("Failed to load friends: \(error.localizedDescription)")
        }
    }
}

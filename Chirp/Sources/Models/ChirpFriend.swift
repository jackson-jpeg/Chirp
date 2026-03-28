import Foundation

struct ChirpFriend: Identifiable, Equatable, Sendable, Codable {
    let id: String           // Peer ID / public key fingerprint
    var name: String         // Display name
    var addedAt: Date        // When they were added as friend
    var isOnline: Bool = false  // Currently in range (not persisted)
    var lastSeen: Date?      // Last time they were in range

    enum CodingKeys: String, CodingKey {
        case id, name, addedAt, lastSeen
        // isOnline is transient — not persisted
    }
}

import Foundation

struct ChirpChannel: Identifiable, Equatable, Sendable, Codable {

    enum AccessMode: String, Codable, Sendable {
        case open
        case locked
    }

    let id: String
    var name: String
    var peers: [ChirpPeer] = []
    var createdAt: Date = Date()
    var accessMode: AccessMode = .open
    var ownerID: String?
    var inviteCode: String?
    var encryptionKeyData: Data?

    var activePeerCount: Int { peers.filter(\.isConnected).count }
}

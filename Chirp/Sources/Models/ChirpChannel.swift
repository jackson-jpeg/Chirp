import Foundation

struct ChirpChannel: Identifiable, Equatable, Sendable, Codable {
    let id: String
    var name: String
    var peers: [ChirpPeer] = []
    var createdAt: Date = Date()

    var activePeerCount: Int { peers.filter(\.isConnected).count }
}

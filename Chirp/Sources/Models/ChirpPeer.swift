import Foundation

struct ChirpPeer: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var isConnected: Bool = false
    var signalStrength: Int = 0  // 0-3 bars
    var lastHeartbeat: Date = Date()
}

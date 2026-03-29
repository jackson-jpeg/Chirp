import Foundation

struct ChirpPeer: Identifiable, Equatable, Sendable, Codable {
    let id: String
    var name: String
    var isConnected: Bool = false
    var signalStrength: Int = 0  // 0-3 bars
    var lastHeartbeat: Date = Date()
    var transportType: TransportType = .multipeer

    enum TransportType: String, Codable, Sendable {
        case multipeer
        case wifiAware
        case both
    }
}

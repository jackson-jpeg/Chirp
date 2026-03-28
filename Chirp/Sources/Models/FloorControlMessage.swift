import Foundation

enum FloorControlMessage: Codable, Sendable {
    case floorRequest(senderID: String, senderName: String, timestamp: Date)
    case floorGranted(speakerID: String)
    case floorRelease(senderID: String)
    case peerJoin(peerID: String, peerName: String)
    case peerLeave(peerID: String)
    case heartbeat(peerID: String, timestamp: Date)
}

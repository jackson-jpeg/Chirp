import ActivityKit
import Foundation

struct ChirpActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var pttState: String // "idle", "transmitting", "receiving", "denied"
        var speakerName: String?
        var channelName: String
        var peerCount: Int
        var inputLevel: Double // 0-1 for waveform animation
    }

    var channelName: String
}

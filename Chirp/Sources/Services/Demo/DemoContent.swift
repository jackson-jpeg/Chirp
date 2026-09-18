import CoreLocation
import Foundation

/// Everything Demo Mode puts on screen: who the simulated people are, what
/// the channels already contain, and which bundled clips they speak with.
///
/// Pure data. Nothing here touches a service; ``DemoMode`` does that.
enum DemoContent {

    // MARK: - People

    struct Peer: Sendable {
        /// A real UUID string: floor control checks a message's claimed sender
        /// against the packet's origin UUID, so demo peers need one to talk.
        let id: String
        let name: String
        let bars: Int
        let battery: Float
        /// Offset from the map anchor in meters, (north, east).
        let offset: (north: Double, east: Double)
        let neighbors: [String]
    }

    static let ridge = Peer(
        id: "DE300000-0000-4000-8000-000000000001", name: "Ridge-7", bars: 3, battery: 0.86,
        offset: (320, 150), neighbors: ["DE300000-0000-4000-8000-000000000002"])
    static let nova = Peer(
        id: "DE300000-0000-4000-8000-000000000002", name: "Nova-12", bars: 3, battery: 0.64,
        offset: (-210, 380), neighbors: ["DE300000-0000-4000-8000-000000000001", "DE300000-0000-4000-8000-000000000003"])
    static let ghost = Peer(
        id: "DE300000-0000-4000-8000-000000000003", name: "Ghost-21", bars: 2, battery: 0.71,
        offset: (90, -420), neighbors: ["DE300000-0000-4000-8000-000000000002"])
    static let wolf = Peer(
        id: "DE300000-0000-4000-8000-000000000004", name: "Wolf-3", bars: 2, battery: 0.42,
        offset: (-380, -160), neighbors: ["DE300000-0000-4000-8000-000000000001"])

    static let peers: [Peer] = [ridge, nova, ghost, wolf]
    static let peerIDs: Set<String> = Set(peers.map(\.id))

    static func peer(named name: String) -> Peer? { peers.first { $0.name == name } }

    static var chirpPeers: [ChirpPeer] {
        peers.map { ChirpPeer(id: $0.id, name: $0.name, isConnected: true, signalStrength: $0.bars) }
    }

    // MARK: - Map

    /// Used when the device has no position to share: Apple Park's visitor
    /// center area, where an App Store reviewer is most likely to be anyway.
    static var fallbackAnchor: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 37.3327, longitude: -122.0053)
    }

    static func coordinate(of peer: Peer, around anchor: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(anchor.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: anchor.latitude + peer.offset.north / metersPerDegreeLat,
            longitude: anchor.longitude + peer.offset.east / max(metersPerDegreeLon, 1)
        )
    }

    // MARK: - Channels

    static let generalID = "\(DemoMode.channelPrefix)general"
    static let trailheadID = "\(DemoMode.channelPrefix)trailhead"
    static let basecampID = "\(DemoMode.channelPrefix)basecamp"

    static func channels(now: Date = .now) -> [ChirpChannel] {
        func channel(_ id: String, _ name: String, _ members: [Peer], hoursAgo: Double) -> ChirpChannel {
            ChirpChannel(
                id: id,
                name: name,
                peers: members.map {
                    ChirpPeer(id: $0.id, name: $0.name, isConnected: true, signalStrength: $0.bars)
                },
                createdAt: now.addingTimeInterval(-hoursAgo * 3600),
                accessMode: .open
            )
        }
        return [
            channel(generalID, "General", peers, hoursAgo: 26),
            channel(trailheadID, "Trailhead", [ridge, wolf, nova], hoursAgo: 5),
            channel(basecampID, "Basecamp", [ghost, nova], hoursAgo: 3),
        ]
    }

    // MARK: - History

    enum Line: Sendable {
        /// A text. `from == nil` is the local user; their status shows ACKs.
        case text(from: Peer?, String, minutesAgo: Double, status: MeshTextMessage.DeliveryStatus = .delivered)
        /// A received chat voice note, played from a bundled AAC clip.
        case voiceNote(from: Peer, clip: String, seconds: Double, minutesAgo: Double)
    }

    static let history: [String: [Line]] = [
        generalID: [
            .text(from: ridge, "Morning all. Mesh is up at the trailhead lot.", minutesAgo: 42),
            .text(from: nil, "Copy. Leaving camp in 10.", minutesAgo: 40, status: .read),
            .text(from: nova, "Creek crossing is running high, take the log bridge.", minutesAgo: 31),
            .voiceNote(from: ghost, clip: "note-ghost", seconds: 4.6, minutesAgo: 24),
            .text(from: nil, "Thanks for the heads up. See you at the overlook.", minutesAgo: 20, status: .delivered),
            .voiceNote(from: wolf, clip: "note-wolf", seconds: 4.8, minutesAgo: 12),
            .text(from: ridge, "Saving you a spot by the big pine.", minutesAgo: 6),
        ],
        trailheadID: [
            .text(from: wolf, "Lot is filling up fast.", minutesAgo: 55),
            .text(from: nil, "On my way, 15 out.", minutesAgo: 54, status: .read),
            .text(from: ridge, "Trail map is posted by the ranger station.", minutesAgo: 50),
            .text(from: nil, "Got it, thanks.", minutesAgo: 48, status: .delivered),
        ],
        basecampID: [
            .text(from: ghost, "Fire's going. Hot water for coffee whenever you're back.", minutesAgo: 90),
            .text(from: nova, "Headlamps are in the blue bin.", minutesAgo: 75),
            .text(from: nil, "Back by sunset.", minutesAgo: 70, status: .delivered),
            .text(from: ghost, "Copy that.", minutesAgo: 65),
        ],
    ]

    // MARK: - Replies

    /// Who answers a text, in rotation, and with what.
    static let textReplies: [(peer: Peer, text: String)] = [
        (ridge, "Copy that. Heading your way."),
        (nova, "Got it, see you there."),
        (ghost, "Roger. Standing by."),
        (wolf, "Loud and clear."),
    ]

    /// Who answers push-to-talk, in rotation, and with which bundled clip.
    static let pttReplies: [(peer: Peer, clip: String)] = [
        (ridge, "ptt-ridge"),
        (nova, "ptt-nova"),
        (ghost, "ptt-ghost"),
    ]

    // MARK: - Voice Messages inbox

    static let inbox: [(peer: Peer, clip: String, minutesAgo: Double)] = [
        (nova, "vm-nova", 11),
        (ridge, "vm-ridge", 34),
    ]

    // MARK: - Bundled audio

    static func clipURL(_ name: String, ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Opus frames of a bundled clip, in the app's voice-message format.
    static func opusFrames(_ name: String) -> [Data]? {
        guard let url = clipURL(name, ext: "opusframes"),
              let data = try? Data(contentsOf: url) else { return nil }
        return VoiceClipPlayer.frames(fromStored: data)
    }
}

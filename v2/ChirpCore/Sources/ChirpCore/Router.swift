import Foundation

/// Decides, for each packet that arrives, whether this device uses it and
/// whether it passes it on. A value type with no callbacks and no clock of its
/// own: the caller passes `now`, so every rule is testable as a plain function.
///
/// Kept from 1.0 (audit section 7, "sound and covered"): drop own echoes, drop
/// blocked origins (no delivery and no relay), dedup, a per-stream replay
/// window that tolerates mesh reordering, TTL. Changed: streams are keyed by
/// (origin, epoch, kind), so a sender that relaunched is a new stream rather
/// than a replay; relay counts are taken only when a relay copy exists; hops
/// are read from the packet, not inferred.
public struct Router: Sendable {
    public enum Drop: Equatable, Sendable {
        case ownEcho, blocked, duplicate, replay
    }

    public struct Decision: Equatable, Sendable {
        /// Use this packet on this device.
        public let deliver: Bool
        /// Send this copy to every link except the one it came in on.
        public let relay: Packet?
        public let dropped: Drop?

        static func drop(_ why: Drop) -> Decision { Decision(deliver: false, relay: nil, dropped: why) }
    }

    /// How far behind a stream's newest sequence a packet may be and still be
    /// accepted (reordering across two paths). Beyond that it is a replay.
    public static let replayWindow: Int32 = 64
    /// How long a seen packet is remembered for dedup.
    public static let dedupLifetime: TimeInterval = 60
    public static let maxRemembered = 4096
    public static let maxStreams = 512

    public let local: PeerID
    public var blocked: Set<PeerID> = []

    private struct StreamKey: Hashable { let origin: PeerID; let epoch: UInt32; let kind: PacketKind }
    private var newest: [StreamKey: (sequence: UInt32, at: Date)] = [:]
    private var seen: [Packet.Key: Date] = [:]
    private var seenOrder: [Packet.Key] = []

    public init(local: PeerID) { self.local = local }

    public mutating func accept(_ packet: Packet, now: Date) -> Decision {
        if packet.origin == local { return .drop(.ownEcho) }
        if blocked.contains(packet.origin) { return .drop(.blocked) }

        forgetOld(now: now)
        if seen[packet.key] != nil { return .drop(.duplicate) }

        let stream = StreamKey(origin: packet.origin, epoch: packet.epoch, kind: packet.kind)
        if let entry = newest[stream] {
            let diff = Int32(bitPattern: packet.sequence &- entry.sequence)
            if diff <= -Self.replayWindow { return .drop(.replay) }
            newest[stream] = (diff > 0 ? packet.sequence : entry.sequence, now)
        } else {
            newest[stream] = (packet.sequence, now)
            if newest.count > Self.maxStreams, let oldest = newest.min(by: { $0.value.at < $1.value.at })?.key {
                newest.removeValue(forKey: oldest)
            }
        }

        seen[packet.key] = now
        seenOrder.append(packet.key)
        return Decision(deliver: true, relay: packet.relayed(), dropped: nil)
    }

    private mutating func forgetOld(now: Date) {
        var cut = 0
        while cut < seenOrder.count {
            let key = seenOrder[cut]
            let tooOld = (seen[key].map { now.timeIntervalSince($0) > Self.dedupLifetime } ?? true)
            let tooMany = seenOrder.count - cut > Self.maxRemembered
            guard tooOld || tooMany else { break }
            seen.removeValue(forKey: key)
            cut += 1
        }
        if cut > 0 { seenOrder.removeFirst(cut) }
    }
}

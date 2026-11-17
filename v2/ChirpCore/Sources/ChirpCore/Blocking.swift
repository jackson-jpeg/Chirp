import Foundation

/// The people this device has blocked (App Review 5.1.2(i)), keyed by `PeerID`
/// and nothing else.
///
/// 1.0 keyed blocks by a routing UUID, added the key fingerprint later, and
/// re-keyed when a blocked identity came back under a new UUID; the nearby
/// bubbles used display names and were never filtered at all (audit section 5,
/// claim H18). With one identity there is nothing to re-key: a block holds for
/// as long as that person's signing key does, and every consumer (router,
/// roster, texts, floor) asks the same set.
public struct BlockList: Equatable, Sendable, Codable {
    public struct Entry: Equatable, Sendable, Codable {
        public let peer: String       // PeerID hex; Codable-friendly
        public let name: String       // the name at block time, for the Settings list
        public let blockedAt: Date
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public var peers: Set<PeerID> { Set(entries.compactMap { PeerID(hex: $0.peer) }) }

    public func isBlocked(_ peer: PeerID) -> Bool { entries.contains { $0.peer == peer.hex } }

    /// Returns false when already blocked.
    @discardableResult
    public mutating func block(_ peer: PeerID, name: String, at: Date) -> Bool {
        guard !isBlocked(peer) else { return false }
        entries.append(Entry(peer: peer.hex, name: name, blockedAt: at))
        return true
    }

    @discardableResult
    public mutating func unblock(_ peer: PeerID) -> Bool {
        let before = entries.count
        entries.removeAll { $0.peer == peer.hex }
        return entries.count != before
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// A file that cannot be read must not silently become "nobody is blocked"
    /// without the caller knowing, so this throws rather than returning empty.
    public static func decode(_ data: Data) throws -> BlockList { try JSONDecoder().decode(BlockList.self, from: data) }
}

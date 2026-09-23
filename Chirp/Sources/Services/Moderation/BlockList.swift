import Foundation
import Observation
import OSLog

/// Per-peer block list, keyed by the peer's stable mesh identity (the
/// origin UUID it stamps on every packet).
///
/// Blocking is enforced in two places: ``MeshRouter`` drops every packet
/// from a blocked origin (audio, text, control — nothing is delivered or
/// relayed), and ``TextMessageService`` hides the blocked peer's stored
/// message history. `AppState` wires both on launch and on every change.
@Observable
@MainActor
final class BlockList {

    /// One blocked peer: the routing UUID that enforcement keys on, the
    /// cryptographic fingerprint that survives a rename, and the display name
    /// at block time so the Settings list stays legible after they go offline.
    ///
    /// `fingerprint` is optional because a peer running a build older than the
    /// attested beacon carries none. Such a block still works; it just cannot
    /// follow them through a reinstall.
    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let blockedAt: Date
        var fingerprint: String?

        // Decoded explicitly so entries written before `fingerprint` existed
        // still load. A failed decode here would silently empty the block
        // list on upgrade, which is the one bug this type cannot have.
        enum CodingKeys: String, CodingKey {
            case id, name, blockedAt, fingerprint
        }

        init(id: String, name: String, blockedAt: Date, fingerprint: String? = nil) {
            self.id = id
            self.name = name
            self.blockedAt = blockedAt
            self.fingerprint = fingerprint
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            blockedAt = try container.decode(Date.self, forKey: .blockedAt)
            fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        }
    }

    private(set) var entries: [Entry] = []

    /// Called whenever the set of blocked IDs changes (including on load).
    /// AppState uses this to push the set into the MeshRouter actor.
    var onChange: ((Set<String>) -> Void)?

    private let logger = Logger(subsystem: Constants.subsystem, category: "BlockList")
    private let storageKey = "com.chirpchirp.blockedPeers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    var blockedIDs: Set<String> { Set(entries.map(\.id)) }

    /// The cryptographic identities that are blocked, which is what makes the
    /// block survive a rename. ``MeshBeacon`` reads this to spot a blocked
    /// identity arriving under a fresh routing UUID.
    var blockedFingerprints: Set<String> { Set(entries.compactMap(\.fingerprint)) }

    func isBlocked(_ peerID: String) -> Bool {
        entries.contains { $0.id == peerID }
    }

    func isBlocked(fingerprint: String) -> Bool {
        entries.contains { $0.fingerprint == fingerprint }
    }

    func block(id: String, name: String, fingerprint: String? = nil) {
        // A block that enforcement will discard is worse than none: it shows
        // the user "Blocked" in Settings while the traffic keeps arriving.
        // `MeshRouter.setBlockedOrigins` keeps only values that parse as a
        // UUID, so anything else (a callsign, an identity fingerprint used by
        // mistake) is refused here, loudly, rather than stored.
        guard UUID(uuidString: id) != nil else {
            logger.error("Refused to block non-routing identifier \(id, privacy: .public)")
            return
        }
        guard !isBlocked(id) else {
            // Already blocked, but we may have learned their fingerprint since.
            if let fingerprint, let index = entries.firstIndex(where: { $0.id == id }),
               entries[index].fingerprint == nil {
                entries[index].fingerprint = fingerprint
                persist()
            }
            return
        }
        entries.append(Entry(id: id, name: name, blockedAt: Date(), fingerprint: fingerprint))
        persist()
        logger.info("Blocked peer \(id, privacy: .public)")
    }

    /// A blocked identity has reappeared under a routing UUID we have not
    /// blocked yet: block that one too, so leaving and rejoining under a new
    /// name does not shake off the block.
    func rekeyBlock(newRoutingID: String, fingerprint: String, name: String) {
        guard isBlocked(fingerprint: fingerprint), !isBlocked(newRoutingID) else { return }
        logger.info("Blocked identity reappeared as \(newRoutingID, privacy: .public)")
        block(id: newRoutingID, name: name, fingerprint: fingerprint)
    }

    /// Unblock every routing UUID that shares this identity. Unblocking one
    /// of them and leaving the rest would be a block the user believes they
    /// lifted.
    func unblock(fingerprint: String) {
        guard isBlocked(fingerprint: fingerprint) else { return }
        entries.removeAll { $0.fingerprint == fingerprint }
        persist()
    }

    func unblock(id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        // Unblocking one routing UUID of an identity that has several (it was
        // re-keyed after a reinstall) has to lift all of them, or the user
        // lifts a block and the peer stays silenced with no way to see why.
        if let fingerprint = entry.fingerprint {
            entries.removeAll { $0.fingerprint == fingerprint }
        } else {
            entries.removeAll { $0.id == id }
        }
        persist()
        logger.info("Unblocked peer \(id, privacy: .public)")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
        onChange?(blockedIDs)
    }
}

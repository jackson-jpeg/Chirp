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

    /// One blocked peer: stable ID plus the display name at block time,
    /// so the Settings list stays legible after the peer goes offline.
    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let blockedAt: Date
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

    func isBlocked(_ peerID: String) -> Bool {
        entries.contains { $0.id == peerID }
    }

    func block(id: String, name: String) {
        guard !isBlocked(id) else { return }
        entries.append(Entry(id: id, name: name, blockedAt: Date()))
        persist()
        logger.info("Blocked peer \(id, privacy: .public)")
    }

    func unblock(id: String) {
        guard isBlocked(id) else { return }
        entries.removeAll { $0.id == id }
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

import Foundation
import OSLog

@Observable
final class StoreAndForwardRelay: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "StoreForward")

    // Pending messages: keyed by recipient peer ID
    private(set) var pendingMessages: [String: [PendingMessage]] = [:]

    // Stats
    private(set) var totalStored: Int = 0
    private(set) var totalDelivered: Int = 0

    struct PendingMessage: Codable, Sendable, Identifiable {
        let id: UUID
        let recipientPeerID: String
        let payload: Data           // The original mesh packet payload
        let channelID: String
        let senderName: String
        let timestamp: Date
        var relayedBy: String?      // Peer name that stored-and-forwarded this

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 24 * 60 * 60  // 24 hours
        }
    }

    init() {
        loadFromDisk()
    }

    // MARK: - Public API

    /// Store a message for later delivery when the recipient comes into range.
    func store(message: PendingMessage) {
        var messages = pendingMessages[message.recipientPeerID] ?? []
        messages.append(message)
        pendingMessages[message.recipientPeerID] = messages
        totalStored += 1
        saveToDisk()
        logger.info("Stored message for peer \(message.recipientPeerID.prefix(8), privacy: .public) from \(message.senderName, privacy: .public)")
    }

    /// Check if we have any pending messages for a newly connected peer.
    /// Returns the valid (non-expired) messages and removes them from the queue.
    func checkPendingForPeer(_ peerID: String) -> [PendingMessage] {
        guard let messages = pendingMessages[peerID] else { return [] }
        let valid = messages.filter { !$0.isExpired }
        // Clear delivered messages
        pendingMessages.removeValue(forKey: peerID)
        totalDelivered += valid.count
        saveToDisk()
        if !valid.isEmpty {
            logger.info("Delivering \(valid.count) stored messages to \(peerID.prefix(8), privacy: .public)")
        }
        return valid
    }

    /// Prune expired messages from the queue.
    func pruneExpired() {
        var prunedCount = 0
        for (peerID, messages) in pendingMessages {
            let valid = messages.filter { !$0.isExpired }
            if valid.count < messages.count {
                prunedCount += messages.count - valid.count
            }
            if valid.isEmpty {
                pendingMessages.removeValue(forKey: peerID)
            } else {
                pendingMessages[peerID] = valid
            }
        }
        if prunedCount > 0 {
            saveToDisk()
            logger.info("Pruned \(prunedCount) expired store-and-forward messages")
        }
    }

    /// Total pending count across all recipients.
    var totalPending: Int {
        pendingMessages.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            // Flatten all messages into a single array for storage
            let allMessages = pendingMessages.values.flatMap { $0 }
            let data = try MeshCodable.encoder.encode(Array(allMessages))
            try data.write(to: storageURL, options: .atomic)
            logger.debug("Saved \(allMessages.count) pending messages to disk")
        } catch {
            logger.error("Failed to save store-and-forward queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let allMessages = try MeshCodable.decoder.decode([PendingMessage].self, from: data)
            // Group by recipient and filter expired
            var grouped: [String: [PendingMessage]] = [:]
            var expiredCount = 0
            for message in allMessages {
                if message.isExpired {
                    expiredCount += 1
                    continue
                }
                grouped[message.recipientPeerID, default: []].append(message)
            }
            pendingMessages = grouped
            if expiredCount > 0 {
                logger.info("Pruned \(expiredCount) expired messages on load")
                saveToDisk()
            }
            let validCount = grouped.values.reduce(0) { $0 + $1.count }
            logger.info("Loaded \(validCount) pending store-and-forward messages from disk")
        } catch {
            logger.error("Failed to load store-and-forward queue: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("store_forward_queue.json")
    }
}

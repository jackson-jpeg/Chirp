import Foundation
import OSLog

/// Manages text messaging over the ChirpChirp mesh network.
///
/// Text messages are encoded as JSON, prefixed with the `TXT!` magic bytes,
/// and sent as ``MeshPacket`` `.control` payloads through the existing mesh
/// relay infrastructure. Every device relays them — no servers involved.
///
/// ## Wiring
/// After creating the service, set ``onSendPacket`` to bridge outgoing
/// messages into the transport layer (e.g. ``MultipeerTransport``).
/// Call ``handlePacket(_:)`` from the mesh router's `onLocalDelivery` callback
/// for every `.control` packet — non-text payloads are silently ignored.
@Observable
@MainActor
final class TextMessageService: @unchecked Sendable {

    // MARK: - Public state

    /// Per-channel message history. Keyed by channel ID.
    private(set) var messagesByChannel: [String: [MeshTextMessage]] = [:]

    // MARK: - Callbacks

    /// Transport hook: `(payload, channelID)`.
    /// The caller wraps the payload in a ``MeshPacket`` and sends it to peers.
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private state

    private let logger = Logger(subsystem: Constants.subsystem, category: "TextMessage")

    /// Maximum messages retained per channel.
    private let maxMessagesPerChannel = 500

    /// Seen message IDs for deduplication.
    private var seenIDs: [UUID: Date] = [:]

    /// Dedup entries older than this are pruned.
    private let deduplicationWindow: TimeInterval = 60

    /// Per-channel count of messages that arrived since the last ``markAsRead(channelID:)``.
    private var unreadCounts: [String: Int] = [:]

    // MARK: - Sending

    /// Compose and send a text message on the given channel.
    ///
    /// - Parameters:
    ///   - text: Message body (truncated to 1000 chars if too long).
    ///   - channelID: Target channel.
    ///   - senderID: Local peer's stable identifier.
    ///   - senderName: Display name for the local peer.
    ///   - replyToID: Optional parent message for threading.
    ///   - attachmentType: Optional attachment kind.
    func send(
        text: String,
        channelID: String,
        senderID: String,
        senderName: String,
        replyToID: UUID? = nil,
        attachmentType: MeshTextMessage.AttachmentType? = nil
    ) {
        let clampedText = String(text.prefix(MeshTextMessage.maxTextLength))

        let message = MeshTextMessage(
            id: UUID(),
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            text: clampedText,
            timestamp: Date(),
            replyToID: replyToID,
            attachmentType: attachmentType
        )

        // Store locally.
        storeMessage(message)

        // Mark our own messages as "seen" so they don't count as unread
        // and won't be duplicated if they echo back through the mesh.
        seenIDs[message.id] = Date()

        // Encode and hand off to transport.
        do {
            let payload = try message.wirePayload()
            onSendPacket?(payload, channelID)
            logger.info("Sent text message \(message.id.uuidString, privacy: .public) on channel \(channelID, privacy: .public)")
        } catch {
            logger.error("Failed to encode text message: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Receiving

    /// Process an incoming ``MeshPacket`` control payload.
    ///
    /// Call this from the mesh router's `onLocalDelivery` for every `.control`
    /// packet. Non-text payloads (missing the `TXT!` prefix) are silently ignored.
    func handlePacket(_ data: Data) {
        guard let message = MeshTextMessage.from(payload: data) else {
            return // Not a text message — ignore.
        }

        // Prune stale dedup entries before checking.
        pruneSeenIDs()

        // Deduplicate: the same message can arrive via multiple mesh paths.
        guard seenIDs[message.id] == nil else {
            logger.trace("Deduplicated text message \(message.id.uuidString, privacy: .public)")
            return
        }
        seenIDs[message.id] = Date()

        storeMessage(message)
        unreadCounts[message.channelID, default: 0] += 1
        logger.info("Received text message \(message.id.uuidString, privacy: .public) from \(message.senderName, privacy: .public) on channel \(message.channelID, privacy: .public)")
    }

    // MARK: - Accessors

    /// All messages for a channel, ordered by timestamp (oldest first).
    func messages(for channelID: String) -> [MeshTextMessage] {
        messagesByChannel[channelID] ?? []
    }

    /// Number of unread messages on a channel since the last ``markAsRead(channelID:)``.
    func unreadCount(for channelID: String) -> Int {
        unreadCounts[channelID] ?? 0
    }

    /// Reset the unread counter for a channel (e.g. when the user opens it).
    func markAsRead(channelID: String) {
        unreadCounts[channelID] = 0
    }

    /// Returns messages in a thread (all messages whose ``MeshTextMessage/replyToID``
    /// matches the given parent, plus the parent itself).
    func thread(for parentID: UUID, channelID: String) -> [MeshTextMessage] {
        let all = messages(for: channelID)
        return all.filter { $0.id == parentID || $0.replyToID == parentID }
    }

    // MARK: - Private

    /// Append a message to its channel history, enforcing the per-channel cap.
    private func storeMessage(_ message: MeshTextMessage) {
        var history = messagesByChannel[message.channelID] ?? []
        history.append(message)

        // Trim oldest messages when over the cap.
        if history.count > maxMessagesPerChannel {
            history.removeFirst(history.count - maxMessagesPerChannel)
        }

        messagesByChannel[message.channelID] = history
    }

    /// Remove dedup entries older than ``deduplicationWindow``.
    private func pruneSeenIDs() {
        let cutoff = Date().addingTimeInterval(-deduplicationWindow)
        seenIDs = seenIDs.filter { $0.value >= cutoff }
    }
}

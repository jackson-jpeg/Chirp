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
final class TextMessageService {

    // MARK: - Public state

    /// Per-channel message history. Keyed by channel ID.
    private(set) var messagesByChannel: [String: [MeshTextMessage]] = [:]

    // MARK: - Callbacks

    /// Transport hook: `(payload, channelID)`.
    /// The caller wraps the payload in a ``MeshPacket`` and sends it to peers.
    var onSendPacket: ((Data, String) -> Void)?

    /// Optional encryption provider: returns ``ChannelCrypto`` for locked channels.
    /// Wired by AppState to ``ChannelManager/getChannelCrypto(for:)``.
    var channelCryptoProvider: ((String) -> ChannelCrypto?)?

    /// Triple-layer encryption for locked channels.
    var meshShield: MeshShield?

    /// CICADA steganography service for hidden message detection.
    var cicadaService: CICADAService?

    /// Epoch provider: returns current epoch and records message for rotation tracking.
    /// Wired by AppState to ``ChannelManager/recordMessageAndGetEpoch(for:)``.
    var epochProvider: ((String) -> UInt32)?

    /// Current epoch provider (for decryption). Returns epoch without advancing.
    /// Wired by AppState to ``ChannelManager/currentEpoch(for:)``.
    var currentEpochProvider: ((String) -> UInt32)?

    /// Per-channel set of peer names currently typing.
    private(set) var typingPeersByChannel: [String: Set<String>] = [:]

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

    /// Timers for auto-expiring typing indicators.
    private var typingTimers: [String: Task<Void, Never>] = [:]

    /// Throttle: last time we sent a typing indicator per channel.
    private var lastTypingSentAt: [String: Date] = [:]

    /// Track which message IDs we've already sent read receipts for.
    private var sentReadReceipts: Set<UUID> = []

    /// Insert a message directly for demo/screenshot purposes.
    func injectDemoMessage(_ message: MeshTextMessage) {
        var messages = messagesByChannel[message.channelID] ?? []
        messages.append(message)
        messagesByChannel[message.channelID] = messages
    }

    /// Encrypted message database. `nil` until ``setupDatabase()`` is called.
    private var database: MessageDatabase?

    /// Tracks which channels have been hydrated from DB into the in-memory cache.
    private var hydratedChannels: Set<String> = []

    // MARK: - Database Setup

    /// Initialize the encrypted message database.
    /// Call once during app startup, before any messages are processed.
    func setupDatabase() {
        do {
            database = try MessageDatabase()
            logger.info("Message database initialized")
        } catch {
            logger.error("Failed to open message database: \(error.localizedDescription, privacy: .public)")
        }
    }

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
        let maxLength = attachmentType == .image
            ? MeshTextMessage.maxImagePayloadLength
            : MeshTextMessage.maxTextLength
        let clampedText = String(text.prefix(maxLength))

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

        // Encode, encrypt, and hand off to transport.
        do {
            let rawPayload = try message.wirePayload()
            let epoch = epochProvider?(channelID) ?? 0
            if let crypto = channelCryptoProvider?(channelID),
               let shield = meshShield {
                // Triple encryption (async due to PeerIdentity actor)
                let sendHook = onSendPacket
                let log = logger
                Task { @MainActor in
                    if let encrypted = await shield.encrypt(rawPayload, channelCrypto: crypto, epoch: epoch) {
                        sendHook?(encrypted, channelID)
                    } else {
                        // Fallback to standard channel encryption
                        if let fallback = try? crypto.encrypt(rawPayload, epoch: epoch) {
                            sendHook?(fallback, channelID)
                        } else {
                            log.error("Both triple-layer and fallback encryption failed for message \(message.id.uuidString, privacy: .public) — sending raw payload")
                            sendHook?(rawPayload, channelID)
                        }
                    }
                    log.info("Sent encrypted text message \(message.id.uuidString, privacy: .public) on channel \(channelID, privacy: .public)")
                }
            } else {
                var payload = rawPayload
                if let crypto = channelCryptoProvider?(channelID) {
                    payload = try crypto.encrypt(payload, epoch: epoch)
                }
                onSendPacket?(payload, channelID)
                logger.info("Sent text message \(message.id.uuidString, privacy: .public) on channel \(channelID, privacy: .public)")
            }
        } catch {
            logger.error("Failed to encode text message: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reactions

    /// Send a reaction emoji for a message on a channel.
    ///
    /// Wire format: `[RXN! magic:4][messageID UUID string][0x00][emoji UTF-8][0x00][senderID][0x00][senderName]`
    func sendReaction(
        emoji: String,
        messageID: UUID,
        channelID: String,
        senderID: String,
        senderName: String
    ) {
        let reaction = MessageReaction(
            id: UUID(),
            messageID: messageID,
            emoji: emoji,
            senderID: senderID,
            senderName: senderName
        )

        // Store locally immediately.
        addReactionToMessage(reaction, channelID: channelID)

        // Build wire payload: RXN! + messageID + 0x00 + emoji + 0x00 + senderID + 0x00 + senderName
        var payload = Data(MeshTextMessage.reactionMagicPrefix)
        payload.append(Data(messageID.uuidString.utf8))
        payload.append(0x00)
        payload.append(Data(emoji.utf8))
        payload.append(0x00)
        payload.append(Data(senderID.utf8))
        payload.append(0x00)
        payload.append(Data(senderName.utf8))

        // Encrypt with channel crypto (same pattern as ACKs).
        do {
            if let crypto = channelCryptoProvider?(channelID) {
                let epoch = currentEpochProvider?(channelID) ?? 0
                payload = try crypto.encrypt(payload, epoch: epoch)
            }
            onSendPacket?(payload, channelID)
            logger.info("Sent reaction \(emoji, privacy: .public) on message \(messageID.uuidString, privacy: .public)")
        } catch {
            logger.error("Failed to send reaction: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handle a decrypted reaction payload. Returns `true` if the payload was a reaction.
    @discardableResult
    func handleReaction(_ data: Data, channelID: String) -> Bool {
        let prefix = Data(MeshTextMessage.reactionMagicPrefix)
        guard data.count > prefix.count,
              data.prefix(prefix.count) == prefix else {
            return false
        }

        let body = Data(data.dropFirst(prefix.count))

        // Split by 0x00 separator: [messageID, emoji, senderID, senderName]
        let parts = body.split(separator: 0x00, maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 4,
              let idString = String(data: Data(parts[0]), encoding: .utf8),
              let messageID = UUID(uuidString: idString),
              let emoji = String(data: Data(parts[1]), encoding: .utf8),
              let senderID = String(data: Data(parts[2]), encoding: .utf8),
              let senderName = String(data: Data(parts[3]), encoding: .utf8) else {
            logger.warning("Malformed reaction payload")
            return true // Still a reaction packet, just invalid
        }

        // Deduplicate by (senderID, messageID, emoji)
        if let messages = messagesByChannel[channelID] {
            if let msgIdx = messages.firstIndex(where: { $0.id == messageID }) {
                let existing = messages[msgIdx].reactions
                if existing.contains(where: { $0.senderID == senderID && $0.emoji == emoji }) {
                    logger.trace("Deduplicated reaction from \(senderID, privacy: .public) on \(messageID.uuidString, privacy: .public)")
                    return true
                }
            }
        }

        let reaction = MessageReaction(
            id: UUID(),
            messageID: messageID,
            emoji: emoji,
            senderID: senderID,
            senderName: senderName
        )

        addReactionToMessage(reaction, channelID: channelID)
        logger.info("Received reaction \(emoji, privacy: .public) from \(senderName, privacy: .public) on message \(messageID.uuidString, privacy: .public)")
        return true
    }

    /// Append a reaction to the matching message in the channel history.
    private func addReactionToMessage(_ reaction: MessageReaction, channelID: String) {
        guard var messages = messagesByChannel[channelID],
              let index = messages.firstIndex(where: { $0.id == reaction.messageID }) else {
            return
        }
        messages[index].reactions.append(reaction)
        messagesByChannel[channelID] = messages
    }

    // MARK: - Typing Indicators

    /// Broadcast a typing indicator on the given channel.
    /// Debounced: won't send more than once every 3 seconds per channel.
    func sendTypingIndicator(channelID: String, senderID: String, senderName: String) {
        let now = Date()
        if let lastSent = lastTypingSentAt[channelID],
           now.timeIntervalSince(lastSent) < 3.0 {
            return // Throttled
        }
        lastTypingSentAt[channelID] = now

        // Wire format: TYP! + senderID + 0x00 + senderName + 0x00 + channelID
        var payload = Data(MeshTextMessage.typingMagicPrefix)
        payload.append(Data(senderID.utf8))
        payload.append(0x00)
        payload.append(Data(senderName.utf8))
        payload.append(0x00)
        payload.append(Data(channelID.utf8))

        do {
            if let crypto = channelCryptoProvider?(channelID) {
                let epoch = currentEpochProvider?(channelID) ?? 0
                payload = try crypto.encrypt(payload, epoch: epoch)
            }
            onSendPacket?(payload, channelID)
            logger.trace("Sent typing indicator on channel \(channelID, privacy: .public)")
        } catch {
            logger.error("Failed to send typing indicator: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handle a decrypted typing indicator payload. Returns `true` if the payload was a typing indicator.
    @discardableResult
    private func handleTypingIndicator(_ data: Data, channelID: String) -> Bool {
        let prefix = Data(MeshTextMessage.typingMagicPrefix)
        guard data.count > prefix.count,
              data.prefix(prefix.count) == prefix else {
            return false
        }

        let body = Data(data.dropFirst(prefix.count))
        let parts = body.split(separator: 0x00, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 3,
              let senderID = String(data: Data(parts[0]), encoding: .utf8),
              let senderName = String(data: Data(parts[1]), encoding: .utf8),
              let peerChannelID = String(data: Data(parts[2]), encoding: .utf8) else {
            logger.warning("Malformed typing indicator payload")
            return true
        }

        // Add typing peer
        var peers = typingPeersByChannel[peerChannelID] ?? []
        peers.insert(senderName)
        typingPeersByChannel[peerChannelID] = peers

        // Auto-expire after 5 seconds
        let timerKey = "\(peerChannelID):\(senderID)"
        typingTimers[timerKey]?.cancel()
        typingTimers[timerKey] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.typingPeersByChannel[peerChannelID]?.remove(senderName)
            if self?.typingPeersByChannel[peerChannelID]?.isEmpty == true {
                self?.typingPeersByChannel.removeValue(forKey: peerChannelID)
            }
        }

        logger.trace("Typing indicator from \(senderName, privacy: .public) on channel \(peerChannelID, privacy: .public)")
        return true
    }

    /// Clear a peer's typing state (e.g. when they send a message).
    private func clearTypingState(senderName: String, channelID: String) {
        typingPeersByChannel[channelID]?.remove(senderName)
        if typingPeersByChannel[channelID]?.isEmpty == true {
            typingPeersByChannel.removeValue(forKey: channelID)
        }
    }

    // MARK: - Read Receipts

    /// Send a read receipt for a message.
    func sendReadReceipt(for messageID: UUID, channelID: String, readerPeerID: String) {
        // Wire format: RRD! + messageID + 0x00 + readerPeerID
        var payload = Data(MeshTextMessage.readReceiptMagicPrefix)
        payload.append(Data(messageID.uuidString.utf8))
        payload.append(0x00)
        payload.append(Data(readerPeerID.utf8))

        do {
            if let crypto = channelCryptoProvider?(channelID) {
                let epoch = currentEpochProvider?(channelID) ?? 0
                payload = try crypto.encrypt(payload, epoch: epoch)
            }
            onSendPacket?(payload, channelID)
            logger.trace("Sent read receipt for \(messageID.uuidString, privacy: .public)")
        } catch {
            logger.error("Failed to send read receipt: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handle a decrypted read receipt payload. Returns `true` if the payload was a read receipt.
    @discardableResult
    private func handleReadReceipt(_ data: Data, channelID: String) -> Bool {
        let prefix = Data(MeshTextMessage.readReceiptMagicPrefix)
        guard data.count > prefix.count,
              data.prefix(prefix.count) == prefix else {
            return false
        }

        let body = Data(data.dropFirst(prefix.count))
        let parts = body.split(separator: 0x00, maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let idString = String(data: Data(parts[0]), encoding: .utf8),
              let messageID = UUID(uuidString: idString) else {
            logger.warning("Malformed read receipt payload")
            return true
        }

        // Update the message's delivery status in memory.
        if var messages = messagesByChannel[channelID] {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].deliveryStatus = .read
                messagesByChannel[channelID] = messages
                logger.info("Message \(messageID.uuidString, privacy: .public) read")
            }
        }

        return true
    }

    /// Mark a message as read and send a receipt if we haven't already.
    func markMessageAsRead(_ messageID: UUID, channelID: String, localPeerID: String) {
        guard !sentReadReceipts.contains(messageID) else { return }
        sentReadReceipts.insert(messageID)
        sendReadReceipt(for: messageID, channelID: channelID, readerPeerID: localPeerID)
    }

    // MARK: - Receiving

    /// Process an incoming ``MeshPacket`` control payload.
    ///
    /// Call this from the mesh router's `onLocalDelivery` for every `.control`
    /// packet. Non-text payloads (missing the `TXT!` prefix) are silently ignored.
    /// - Parameters:
    ///   - data: Raw control payload (may be encrypted).
    ///   - channelID: Channel this packet arrived on (from ``MeshPacket/channelID``).
    func handlePacket(_ data: Data, channelID: String = "") {
        // Decrypt: try triple-layer first, fall back to standard channel encryption.
        let epoch = currentEpochProvider?(channelID) ?? 0
        var decrypted = data
        if let crypto = channelCryptoProvider?(channelID) {
            if let shield = meshShield,
               let plain = shield.decrypt(data, channelCrypto: crypto, currentEpoch: epoch) {
                decrypted = plain
            } else if let plain = try? crypto.decrypt(data, currentEpoch: epoch) {
                decrypted = plain
            }
        }

        // Check for typing indicators.
        if handleTypingIndicator(decrypted, channelID: channelID) {
            return
        }

        // Check for read receipts.
        if handleReadReceipt(decrypted, channelID: channelID) {
            return
        }

        // Check for reaction packets.
        if handleReaction(decrypted, channelID: channelID) {
            return
        }

        // Check for delivery ACK.
        if handleACK(decrypted, channelID: channelID) {
            return
        }

        guard let message = MeshTextMessage.from(payload: decrypted) else {
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

        // Clear typing indicator for this sender — they sent a message.
        clearTypingState(senderName: message.senderName, channelID: message.channelID)

        // CICADA: check for hidden steganographic content
        cicadaService?.decodeAndStore(message: message, channelID: channelID)

        // Send delivery ACK back to sender.
        sendACK(for: message.id, channelID: channelID)

        logger.info("Received text message \(message.id.uuidString, privacy: .public) from \(message.senderName, privacy: .public) on channel \(message.channelID, privacy: .public)")
    }

    // MARK: - Delivery ACK

    /// Send an acknowledgment packet for a received message.
    private func sendACK(for messageID: UUID, channelID: String) {
        guard let idData = messageID.uuidString.data(using: .utf8) else { return }
        var payload = Data(MeshTextMessage.ackMagicPrefix)
        payload.append(idData)

        do {
            if let crypto = channelCryptoProvider?(channelID) {
                let ackEpoch = currentEpochProvider?(channelID) ?? 0
                payload = try crypto.encrypt(payload, epoch: ackEpoch)
            }
            onSendPacket?(payload, channelID)
            logger.trace("Sent ACK for message \(messageID.uuidString, privacy: .public)")
        } catch {
            logger.error("Failed to send ACK: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Check if a decrypted payload is a delivery ACK. If so, update the
    /// corresponding message's status to `.delivered` and return `true`.
    private func handleACK(_ data: Data, channelID: String) -> Bool {
        let prefix = Data(MeshTextMessage.ackMagicPrefix)
        guard data.count > prefix.count,
              data.prefix(prefix.count) == prefix else {
            return false
        }

        let idData = data.dropFirst(prefix.count)
        guard let idString = String(data: Data(idData), encoding: .utf8),
              let messageID = UUID(uuidString: idString) else {
            return false
        }

        // Update the message's delivery status in memory.
        if var messages = messagesByChannel[channelID] {
            if let index = messages.firstIndex(where: { $0.id == messageID }) {
                messages[index].deliveryStatus = .delivered
                messagesByChannel[channelID] = messages
                logger.info("Message \(messageID.uuidString, privacy: .public) delivered")
            }
        }

        return true
    }

    // MARK: - Accessors

    /// All messages for a channel, ordered by timestamp (oldest first).
    /// Hydrates from the database on first access per channel.
    func messages(for channelID: String) -> [MeshTextMessage] {
        hydrateIfNeeded(channelID: channelID)
        return messagesByChannel[channelID] ?? []
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
        // Try database first for complete thread history
        if let db = database {
            let records = db.messagesInThread(parentID: parentID.uuidString, channelID: channelID)
            let converted = records.compactMap { $0.toMeshTextMessage() }
            if !converted.isEmpty { return converted }
        }
        // Fall back to in-memory
        let all = messages(for: channelID)
        return all.filter { $0.id == parentID || $0.replyToID == parentID }
    }

    // MARK: - Private

    /// Hydrate the in-memory cache from the database for a channel, once per session.
    private func hydrateIfNeeded(channelID: String) {
        guard !hydratedChannels.contains(channelID) else { return }
        hydratedChannels.insert(channelID)

        guard let db = database else { return }

        let records = db.messages(forChannel: channelID, limit: maxMessagesPerChannel)
        let messages = records.compactMap { $0.toMeshTextMessage() }

        if !messages.isEmpty {
            messagesByChannel[channelID] = messages
            logger.info("Hydrated \(messages.count) messages for channel \(channelID, privacy: .public)")
        }
    }

    /// Append a message to its channel history, enforcing the per-channel cap.
    /// Persists to the database and updates the in-memory cache.
    private func storeMessage(_ message: MeshTextMessage) {
        // Persist to database
        database?.insert(MessageRecord(from: message))
        database?.deleteOldest(forChannel: message.channelID, keepCount: maxMessagesPerChannel)

        // Update in-memory cache
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

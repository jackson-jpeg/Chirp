import Foundation
import OSLog

/// Stores voice messages for offline delivery via store-and-forward.
///
/// When the recipient is out of mesh range, the audio (Opus frames) is saved
/// to the Documents directory. When the recipient comes back into range,
/// queued messages auto-deliver through the mesh transport layer.
@Observable
@MainActor
final class VoiceMessageQueue {
    static let shared = VoiceMessageQueue()

    // MARK: - Types

    struct PendingMessage: Codable, Identifiable, Sendable {
        let id: UUID
        let senderID: String
        let recipientID: String
        let recipientName: String
        let timestamp: Date
        let durationMs: Int
        let fileName: String
        var delivered: Bool = false
        var deliveredAt: Date?

        /// Human-readable duration string (e.g. "0:12").
        var durationDisplay: String {
            let totalSeconds = durationMs / 1000
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }

    // MARK: - Public State

    private(set) var pendingMessages: [PendingMessage] = []
    private(set) var receivedMessages: [PendingMessage] = []

    /// Number of undelivered messages waiting in the queue.
    var undeliveredCount: Int {
        pendingMessages.filter { !$0.delivered }.count
    }

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "VoiceQueue")
    private let fileManager = FileManager.default

    private static let indexFileName = "voice_queue_index.json"
    private static let receivedIndexFileName = "voice_received_index.json"
    private static let voiceSubdirectory = "VoiceMessages"

    private var voiceDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(Self.voiceSubdirectory, isDirectory: true)
    }

    // MARK: - Init

    private init() {
        ensureDirectoryExists()
        load()
    }

    // MARK: - Queue a Message

    /// Store a voice message for later delivery when the recipient comes into range.
    ///
    /// - Parameters:
    ///   - opusFrames: Array of Opus-encoded audio frames.
    ///   - recipientID: Peer ID of the intended recipient.
    ///   - recipientName: Display name of the recipient.
    ///   - senderID: The local user's peer ID.
    /// - Returns: The created `PendingMessage` metadata.
    @discardableResult
    func queueMessage(
        opusFrames: [Data],
        recipientID: String,
        recipientName: String,
        senderID: String
    ) -> PendingMessage {
        let messageID = UUID()
        let fileName = "\(messageID.uuidString).opus"

        // Concatenate Opus frames with length-prefix encoding so they can
        // be split back apart on the receiving end.
        // Format: [frameCount:4][len1:4][data1][len2:4][data2]...
        var audioData = Data()
        var frameCount = UInt32(opusFrames.count).bigEndian
        audioData.append(Data(bytes: &frameCount, count: 4))
        for frame in opusFrames {
            var frameLen = UInt32(frame.count).bigEndian
            audioData.append(Data(bytes: &frameLen, count: 4))
            audioData.append(frame)
        }

        // Calculate approximate duration from frame count.
        // Each Opus frame is 20ms at our configuration.
        let durationMs = opusFrames.count * Int(Constants.Opus.frameDuration * 1000)

        // Write audio to disk.
        let filePath = voiceDirectory.appendingPathComponent(fileName)
        do {
            try audioData.write(to: filePath, options: .atomic)
        } catch {
            logger.error("Failed to write voice message: \(error.localizedDescription)")
        }

        let message = PendingMessage(
            id: messageID,
            senderID: senderID,
            recipientID: recipientID,
            recipientName: recipientName,
            timestamp: Date(),
            durationMs: durationMs,
            fileName: fileName
        )

        pendingMessages.append(message)
        save()

        logger.info("Queued voice message for \(recipientName, privacy: .public) frames=\(opusFrames.count) duration=\(durationMs)ms")

        return message
    }

    // MARK: - Delivery

    /// Check if any pending messages can be delivered to currently online peers.
    ///
    /// - Parameters:
    ///   - onlinePeerIDs: Set of peer IDs currently reachable in the mesh.
    ///   - sendFunction: Closure that sends data to a specific peer ID.
    func attemptDelivery(
        onlinePeerIDs: Set<String>,
        sendFunction: (String, Data) -> Void
    ) {
        var didDeliver = false

        for index in pendingMessages.indices {
            let message = pendingMessages[index]
            guard !message.delivered else { continue }
            guard onlinePeerIDs.contains(message.recipientID) else { continue }

            // Load audio data from disk.
            let filePath = voiceDirectory.appendingPathComponent(message.fileName)
            guard let audioData = try? Data(contentsOf: filePath) else {
                logger.error("Audio file missing for message \(message.id.uuidString)")
                continue
            }

            // Build the delivery payload: metadata JSON + separator + audio data.
            guard let metadataJSON = try? JSONEncoder().encode(message) else { continue }

            var deliveryPayload = Data()
            // Header: "VMQ!" magic + metadata length (4 bytes) + metadata + audio
            let magic: [UInt8] = [0x56, 0x4D, 0x51, 0x21] // "VMQ!"
            deliveryPayload.append(contentsOf: magic)
            var metaLen = UInt32(metadataJSON.count).bigEndian
            deliveryPayload.append(Data(bytes: &metaLen, count: 4))
            deliveryPayload.append(metadataJSON)
            deliveryPayload.append(audioData)

            sendFunction(message.recipientID, deliveryPayload)

            pendingMessages[index].delivered = true
            pendingMessages[index].deliveredAt = Date()
            didDeliver = true

            logger.info(
                "Delivered voice message to \(message.recipientName, privacy: .public)"
            )
        }

        if didDeliver {
            save()
        }
    }

    // MARK: - Receiving

    /// Process a voice message received from the mesh.
    ///
    /// - Parameters:
    ///   - message: The message metadata.
    ///   - audioData: The raw audio payload (length-prefixed Opus frames).
    func receiveMessage(_ message: PendingMessage, audioData: Data) {
        // Save audio to disk.
        let fileName = "\(message.id.uuidString)_received.opus"
        let filePath = voiceDirectory.appendingPathComponent(fileName)

        do {
            try audioData.write(to: filePath, options: .atomic)
        } catch {
            logger.error("Failed to save received voice message: \(error.localizedDescription)")
            return
        }

        // Store with the local file name.
        var receivedMsg = message
        receivedMsg = PendingMessage(
            id: message.id,
            senderID: message.senderID,
            recipientID: message.recipientID,
            recipientName: message.recipientName,
            timestamp: message.timestamp,
            durationMs: message.durationMs,
            fileName: fileName,
            delivered: true,
            deliveredAt: Date()
        )

        receivedMessages.insert(receivedMsg, at: 0)
        saveReceived()

        logger.info("Received voice message from \(message.senderID, privacy: .public) duration=\(message.durationMs)ms")
    }

    /// Parse a delivery payload received from the mesh into metadata and audio.
    /// Returns nil if the data is malformed.
    func parseDeliveryPayload(_ data: Data) -> (message: PendingMessage, audioData: Data)? {
        let magic: [UInt8] = [0x56, 0x4D, 0x51, 0x21]
        guard data.count > magic.count + 4 else { return nil }

        let header = Array(data.prefix(magic.count))
        guard header == magic else { return nil }

        var offset = magic.count
        let metaLenBytes = data[offset..<(offset + 4)]
        let metaLen = metaLenBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4

        guard offset + Int(metaLen) <= data.count else { return nil }
        let metadataJSON = data[offset..<(offset + Int(metaLen))]
        offset += Int(metaLen)

        guard let message = try? JSONDecoder().decode(PendingMessage.self, from: Data(metadataJSON)) else {
            return nil
        }

        let audioData = Data(data[offset...])
        return (message, audioData)
    }

    // MARK: - Audio Playback Support

    /// Load the Opus frames for a received message from disk.
    /// Returns an array of individual Opus frames.
    func loadOpusFrames(for message: PendingMessage) -> [Data]? {
        let filePath = voiceDirectory.appendingPathComponent(message.fileName)
        guard let rawData = try? Data(contentsOf: filePath) else {
            logger.error("Cannot load audio for message \(message.id.uuidString)")
            return nil
        }

        return decodeFrames(from: rawData)
    }

    /// Decode length-prefixed Opus frames from concatenated data.
    private func decodeFrames(from data: Data) -> [Data]? {
        guard data.count >= 4 else { return nil }

        var offset = 0
        let frameCount = data[offset..<(offset + 4)].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        offset += 4

        var frames: [Data] = []
        frames.reserveCapacity(Int(frameCount))

        for _ in 0..<frameCount {
            guard offset + 4 <= data.count else { return nil }
            let frameLen = data[offset..<(offset + 4)].withUnsafeBytes {
                $0.load(as: UInt32.self).bigEndian
            }
            offset += 4

            guard offset + Int(frameLen) <= data.count else { return nil }
            frames.append(Data(data[offset..<(offset + Int(frameLen))]))
            offset += Int(frameLen)
        }

        return frames
    }

    // MARK: - Deletion

    /// Delete a pending message and its audio file.
    func deletePendingMessage(id: UUID) {
        guard let index = pendingMessages.firstIndex(where: { $0.id == id }) else { return }
        let message = pendingMessages[index]
        deleteAudioFile(message.fileName)
        pendingMessages.remove(at: index)
        save()
        logger.info("Deleted pending message \(id.uuidString)")
    }

    /// Delete a received message and its audio file.
    func deleteReceivedMessage(id: UUID) {
        guard let index = receivedMessages.firstIndex(where: { $0.id == id }) else { return }
        let message = receivedMessages[index]
        deleteAudioFile(message.fileName)
        receivedMessages.remove(at: index)
        saveReceived()
        logger.info("Deleted received message \(id.uuidString)")
    }

    /// Remove all delivered messages older than the given interval.
    func pruneDelivered(olderThan interval: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        let toRemove = pendingMessages.filter { $0.delivered && ($0.deliveredAt ?? $0.timestamp) < cutoff }

        for message in toRemove {
            deleteAudioFile(message.fileName)
        }

        pendingMessages.removeAll { msg in
            toRemove.contains { $0.id == msg.id }
        }

        if !toRemove.isEmpty {
            save()
            logger.info("Pruned \(toRemove.count) delivered messages")
        }
    }

    // MARK: - Persistence

    private func save() {
        let indexURL = voiceDirectory.appendingPathComponent(Self.indexFileName)
        do {
            let data = try JSONEncoder().encode(pendingMessages)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save pending message index: \(error.localizedDescription)")
        }
    }

    private func saveReceived() {
        let indexURL = voiceDirectory.appendingPathComponent(Self.receivedIndexFileName)
        do {
            let data = try JSONEncoder().encode(receivedMessages)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save received message index: \(error.localizedDescription)")
        }
    }

    private func load() {
        let pendingURL = voiceDirectory.appendingPathComponent(Self.indexFileName)
        if let data = try? Data(contentsOf: pendingURL),
           let messages = try? JSONDecoder().decode([PendingMessage].self, from: data) {
            pendingMessages = messages
            logger.info("Loaded \(messages.count) pending voice messages")
        }

        let receivedURL = voiceDirectory.appendingPathComponent(Self.receivedIndexFileName)
        if let data = try? Data(contentsOf: receivedURL),
           let messages = try? JSONDecoder().decode([PendingMessage].self, from: data) {
            receivedMessages = messages
            logger.info("Loaded \(messages.count) received voice messages")
        }
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: voiceDirectory.path) {
            try? fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
        }
    }

    private func deleteAudioFile(_ fileName: String) {
        let filePath = voiceDirectory.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: filePath)
    }
}

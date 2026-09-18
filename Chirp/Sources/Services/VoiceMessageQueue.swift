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
        /// Display name of whoever recorded it. Optional so indexes written
        /// before it existed still decode; rows fall back to the sender ID.
        var senderName: String? = nil

        /// Human-readable duration string (e.g. "0:12").
        var durationDisplay: String {
            let totalSeconds = durationMs / 1000
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }

    // MARK: - Public State

    /// What the Voice Messages screen shows: the real queue, or Demo Mode's
    /// simulated inbox while that is up.
    var pendingMessages: [PendingMessage] { demoOverlay == nil ? storedPending : [] }
    var receivedMessages: [PendingMessage] { demoOverlay?.received ?? storedReceived }

    private var storedPending: [PendingMessage] = []
    private var storedReceived: [PendingMessage] = []

    /// Demo Mode's inbox: messages plus the bundled clip each one plays.
    /// Never written to disk; the real index files are untouched while it is up.
    private var demoOverlay: (received: [PendingMessage], clips: [UUID: URL])?

    func enterDemoOverlay(received: [(PendingMessage, URL)]) {
        demoOverlay = (
            received.map(\.0).sorted { $0.timestamp > $1.timestamp },
            Dictionary(uniqueKeysWithValues: received.map { ($0.0.id, $0.1) })
        )
    }

    func exitDemoOverlay() {
        demoOverlay = nil
    }

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
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Fallback to temp directory if documents is unavailable (should never happen on iOS)
            logger.error("Documents directory unavailable — falling back to temporary directory")
            return fileManager.temporaryDirectory.appendingPathComponent(Self.voiceSubdirectory, isDirectory: true)
        }
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

        storedPending.append(message)
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

        for index in storedPending.indices {
            let message = storedPending[index]
            guard !message.delivered else { continue }
            guard onlinePeerIDs.contains(message.recipientID) else { continue }

            // Load audio data from disk.
            let filePath = voiceDirectory.appendingPathComponent(message.fileName)
            let audioData: Data
            do {
                audioData = try Data(contentsOf: filePath)
            } catch {
                logger.error("Cannot read audio for message \(message.id.uuidString): \(error.localizedDescription)")
                continue
            }

            // Build the delivery payload: metadata JSON + separator + audio data.
            let metadataJSON: Data
            do {
                metadataJSON = try JSONEncoder().encode(message)
            } catch {
                logger.error("Cannot encode metadata for message \(message.id.uuidString): \(error.localizedDescription)")
                continue
            }

            var deliveryPayload = Data()
            // Header: "VMQ!" magic + metadata length (4 bytes) + metadata + audio
            let magic: [UInt8] = [0x56, 0x4D, 0x51, 0x21] // "VMQ!"
            deliveryPayload.append(contentsOf: magic)
            var metaLen = UInt32(metadataJSON.count).bigEndian
            deliveryPayload.append(Data(bytes: &metaLen, count: 4))
            deliveryPayload.append(metadataJSON)
            deliveryPayload.append(audioData)

            sendFunction(message.recipientID, deliveryPayload)

            storedPending[index].delivered = true
            storedPending[index].deliveredAt = Date()
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
            deliveredAt: Date(),
            senderName: message.senderName
        )

        storedReceived.insert(receivedMsg, at: 0)
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

        // All offsets relative to data.startIndex — see Data+WireFormat.
        var offset = magic.count
        guard let metaLen = data.readBigEndian(UInt32.self, at: offset) else { return nil }
        offset += 4

        guard let metadataJSON = data.slice(at: offset, length: Int(metaLen)) else { return nil }
        offset += Int(metaLen)

        guard let message = try? JSONDecoder().decode(PendingMessage.self, from: Data(metadataJSON)) else {
            return nil
        }

        guard let audioBytes = data.bytes(from: offset) else { return nil }
        return (message, Data(audioBytes))
    }

    // MARK: - Audio Playback Support

    /// Load the Opus frames for a received message from disk.
    /// Returns an array of individual Opus frames.
    func loadOpusFrames(for message: PendingMessage) -> [Data]? {
        if let clip = demoOverlay?.clips[message.id] {
            guard let data = try? Data(contentsOf: clip) else { return nil }
            return decodeFrames(from: data)
        }
        let filePath = voiceDirectory.appendingPathComponent(message.fileName)
        let rawData: Data
        do {
            rawData = try Data(contentsOf: filePath)
        } catch {
            logger.error("Cannot load audio for message \(message.id.uuidString): \(error.localizedDescription)")
            return nil
        }

        return decodeFrames(from: rawData)
    }

    /// Decode length-prefixed Opus frames from concatenated data.
    private func decodeFrames(from data: Data) -> [Data]? {
        guard data.count >= 4 else { return nil }

        // `offset` advances by a frame length read out of the file, which for a
        // received voice message means a peer chose it. Any length that is not a
        // multiple of four left the next read misaligned and trapped the
        // process — a remote crash needing nothing but a malformed message.
        // Byte-by-byte reads have no alignment requirement, so the offset being
        // odd is now simply uninteresting. See Data+WireFormat.
        var offset = 0
        guard let frameCount = data.readBigEndian(UInt32.self, at: offset) else { return nil }
        offset += 4

        // Bound the reservation by what the buffer could possibly hold: a frame
        // costs at least its 4-byte length prefix, and frameCount is attacker-
        // supplied, so reserving it directly is an allocation of up to 4 GiB on
        // a 9-byte file.
        var frames: [Data] = []
        frames.reserveCapacity(min(Int(frameCount), data.count / 4))

        for _ in 0..<frameCount {
            guard let frameLen = data.readBigEndian(UInt32.self, at: offset) else { return nil }
            offset += 4

            guard let frame = data.slice(at: offset, length: Int(frameLen)) else { return nil }
            frames.append(Data(frame))
            offset += Int(frameLen)
        }

        return frames
    }

    // MARK: - Deletion

    /// Delete a pending message and its audio file.
    func deletePendingMessage(id: UUID) {
        guard let index = storedPending.firstIndex(where: { $0.id == id }) else { return }
        let message = storedPending[index]
        deleteAudioFile(message.fileName)
        storedPending.remove(at: index)
        save()
        logger.info("Deleted pending message \(id.uuidString)")
    }

    /// Delete a received message and its audio file.
    func deleteReceivedMessage(id: UUID) {
        if var overlay = demoOverlay {
            overlay.received.removeAll { $0.id == id }
            demoOverlay = overlay
            return
        }
        guard let index = storedReceived.firstIndex(where: { $0.id == id }) else { return }
        let message = storedReceived[index]
        deleteAudioFile(message.fileName)
        storedReceived.remove(at: index)
        saveReceived()
        logger.info("Deleted received message \(id.uuidString)")
    }

    /// Remove all delivered messages older than the given interval.
    func pruneDelivered(olderThan interval: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-interval)
        let toRemove = storedPending.filter { $0.delivered && ($0.deliveredAt ?? $0.timestamp) < cutoff }

        for message in toRemove {
            deleteAudioFile(message.fileName)
        }

        storedPending.removeAll { msg in
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
            let data = try JSONEncoder().encode(storedPending)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save pending message index: \(error.localizedDescription)")
        }
    }

    private func saveReceived() {
        let indexURL = voiceDirectory.appendingPathComponent(Self.receivedIndexFileName)
        do {
            let data = try JSONEncoder().encode(storedReceived)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            logger.error("Failed to save received message index: \(error.localizedDescription)")
        }
    }

    private func load() {
        storedPending = loadIndex(named: Self.indexFileName, label: "pending")
        storedReceived = loadIndex(named: Self.receivedIndexFileName, label: "received")
    }

    /// A missing index is normal (first launch, nothing queued yet); an index
    /// that exists but won't read or decode is corruption and gets logged.
    private func loadIndex(named fileName: String, label: String) -> [PendingMessage] {
        let indexURL = voiceDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            let messages = try JSONDecoder().decode([PendingMessage].self, from: data)
            logger.info("Loaded \(messages.count) \(label, privacy: .public) voice messages")
            return messages
        } catch {
            logger.error("Corrupt \(label, privacy: .public) voice index — starting empty: \(error.localizedDescription)")
            return []
        }
    }

    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: voiceDirectory.path) {
            do {
                try fileManager.createDirectory(at: voiceDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Cannot create voice message directory — nothing will persist: \(error.localizedDescription)")
            }
        }
    }

    private func deleteAudioFile(_ fileName: String) {
        let filePath = voiceDirectory.appendingPathComponent(fileName)
        do {
            try fileManager.removeItem(at: filePath)
        } catch {
            logger.error("Could not delete audio file \(fileName, privacy: .public): \(error.localizedDescription)")
        }
    }
}

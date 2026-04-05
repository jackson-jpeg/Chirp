import Foundation
import CryptoKit
import OSLog

struct TransferProgress: Sendable {
    let transferID: UUID
    let fileName: String
    let mimeType: String
    let totalChunks: UInt16
    var receivedChunks: UInt16
    let totalBytes: UInt64
    let isOutbound: Bool
    let senderName: String
    let channelID: String
    var isComplete: Bool
    var localFileURL: URL?

    var progress: Float {
        guard totalChunks > 0 else { return 0 }
        return Float(receivedChunks) / Float(totalChunks)
    }
}

@Observable
@MainActor
final class FileTransferService {

    private let logger = Logger(subsystem: Constants.subsystem, category: "FileTransfer")

    // Public state for UI
    private(set) var activeTransfers: [UUID: TransferProgress] = [:]

    // Callbacks
    var onSendPacket: ((Data, String) -> Void)?
    var channelCryptoProvider: ((String) -> ChannelCrypto?)?
    var onTransferComplete: ((UUID, String, URL) -> Void)? // transferID, channelID, fileURL

    // Inbound tracking
    private var inboundChunks: [UUID: [UInt16: Data]] = [:]
    private var inboundMetadata: [UUID: FileTransferMetadata] = [:]
    private var lastChunkTime: [UUID: Date] = [:]
    private var nackTask: Task<Void, Never>?

    // Outbound tracking
    private var outboundData: [UUID: Data] = [:] // Full file data for NACK resends

    private static let maxConcurrentInbound = 3
    /// Maximum file size: 5 MB. Larger files would overwhelm the mesh.
    static let maxFileSize = 5 * 1_048_576
    /// Stale transfer timeout: incomplete transfers older than 5 minutes are cleaned up.
    private static let staleTransferTimeout: TimeInterval = 300
    private static let transfersDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("transfers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        startNACKMonitor()
    }

    // MARK: - Send

    func sendFile(_ fileData: Data, fileName: String, mimeType: String, channelID: String, senderID: String, senderName: String) {
        guard fileData.count <= Self.maxFileSize else {
            logger.warning("File too large (\(fileData.count) bytes, max \(Self.maxFileSize)): \(fileName)")
            return
        }
        guard !fileName.isEmpty else { return }
        let transferID = UUID()
        let chunkSize = FileChunk.maxChunkSize
        let chunkCount = UInt16(clamping: (fileData.count + chunkSize - 1) / chunkSize)
        let sha256 = SHA256.hash(data: fileData)
        let hashData = Data(sha256)

        let metadata = FileTransferMetadata(
            id: transferID,
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            fileName: fileName,
            mimeType: mimeType,
            totalSize: UInt64(fileData.count),
            chunkCount: chunkCount,
            fileSHA256: hashData,
            timestamp: Date()
        )

        // Track outbound transfer
        activeTransfers[transferID] = TransferProgress(
            transferID: transferID,
            fileName: fileName,
            mimeType: mimeType,
            totalChunks: chunkCount,
            receivedChunks: 0,
            totalBytes: UInt64(fileData.count),
            isOutbound: true,
            senderName: senderName,
            channelID: channelID,
            isComplete: false
        )
        outboundData[transferID] = fileData

        // Send metadata
        if let metaPayload = try? metadata.wirePayload() {
            let encrypted = encryptIfNeeded(metaPayload, channelID: channelID)
            onSendPacket?(encrypted, channelID)
        }

        // Send chunks with pacing
        Task {
            let batchSize = 15
            let batchDelay: Duration = .milliseconds(50)

            for i in 0..<Int(chunkCount) {
                let start = i * chunkSize
                let end = min(start + chunkSize, fileData.count)
                let chunkData = fileData[start..<end]

                let chunk = FileChunk(
                    transferID: transferID,
                    chunkIndex: UInt16(i),
                    data: Data(chunkData)
                )

                let chunkPayload = chunk.wirePayload()
                let encrypted = encryptIfNeeded(chunkPayload, channelID: channelID)
                onSendPacket?(encrypted, channelID)

                // Update progress
                activeTransfers[transferID]?.receivedChunks = UInt16(i + 1)

                // Pace: pause every batchSize chunks
                if (i + 1) % batchSize == 0 {
                    try? await Task.sleep(for: batchDelay)
                }
            }

            activeTransfers[transferID]?.isComplete = true
            logger.info("Sent file \(fileName) (\(fileData.count) bytes, \(chunkCount) chunks)")

            // Clean up outbound data after 60s (keep for NACKs)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.outboundData.removeValue(forKey: transferID)
            }
        }
    }

    // MARK: - Receive

    func handlePacket(_ payload: Data, channelID: String) {
        let decrypted = decryptIfNeeded(payload, channelID: channelID)

        // Try FIL! metadata
        if let metadata = FileTransferMetadata.from(payload: decrypted) {
            handleMetadata(metadata)
            return
        }

        // Try FLC! chunk
        if let chunk = FileChunk.from(payload: decrypted) {
            handleChunk(chunk)
            return
        }

        // Try FNK! chunk request (NACK)
        if let request = FileChunkRequest.from(payload: decrypted) {
            handleNACK(request)
            return
        }
    }

    private func handleMetadata(_ metadata: FileTransferMetadata) {
        let id = metadata.id

        // Limit concurrent inbound
        let inboundCount = activeTransfers.values.filter { !$0.isOutbound && !$0.isComplete }.count
        guard inboundCount < Self.maxConcurrentInbound else {
            logger.warning("Rejecting file transfer \(id) -- too many concurrent transfers")
            return
        }

        // Deduplicate
        guard inboundMetadata[id] == nil else { return }

        // Reject files that exceed our size limit
        guard metadata.totalSize <= UInt64(Self.maxFileSize) else {
            logger.warning("Rejecting file transfer \(id) — \(metadata.totalSize) bytes exceeds \(Self.maxFileSize) limit")
            return
        }

        inboundMetadata[id] = metadata
        inboundChunks[id] = [:]
        lastChunkTime[id] = Date()

        activeTransfers[id] = TransferProgress(
            transferID: id,
            fileName: metadata.fileName,
            mimeType: metadata.mimeType,
            totalChunks: metadata.chunkCount,
            receivedChunks: 0,
            totalBytes: metadata.totalSize,
            isOutbound: false,
            senderName: metadata.senderName,
            channelID: metadata.channelID,
            isComplete: false
        )

        logger.info("Receiving file \(metadata.fileName) (\(metadata.totalSize) bytes, \(metadata.chunkCount) chunks)")
    }

    private func handleChunk(_ chunk: FileChunk) {
        let id = chunk.transferID
        guard inboundMetadata[id] != nil else { return }

        // Deduplicate by transferID + chunkIndex
        if inboundChunks[id]?[chunk.chunkIndex] != nil { return }

        inboundChunks[id]?[chunk.chunkIndex] = chunk.data
        lastChunkTime[id] = Date()

        let received = UInt16(inboundChunks[id]?.count ?? 0)
        activeTransfers[id]?.receivedChunks = received

        // Check completion
        if let metadata = inboundMetadata[id], received == metadata.chunkCount {
            completeTransfer(id)
        }
    }

    private func completeTransfer(_ id: UUID) {
        guard let metadata = inboundMetadata[id],
              let chunks = inboundChunks[id] else { return }

        // Reassemble in order
        var assembled = Data()
        for i in 0..<metadata.chunkCount {
            guard let chunkData = chunks[i] else {
                logger.error("Missing chunk \(i) during assembly for \(id)")
                return
            }
            assembled.append(chunkData)
        }

        // Verify SHA256
        let hash = Data(SHA256.hash(data: assembled))
        guard hash == metadata.fileSHA256 else {
            logger.error("SHA256 mismatch for \(metadata.fileName)")
            return
        }

        // Save to disk
        let fileURL = Self.transfersDirectory
            .appendingPathComponent("\(id.uuidString)_\(metadata.fileName)")
        do {
            try assembled.write(to: fileURL)
            activeTransfers[id]?.isComplete = true
            activeTransfers[id]?.localFileURL = fileURL
            onTransferComplete?(id, metadata.channelID, fileURL)
            logger.info("File transfer complete: \(metadata.fileName) -> \(fileURL.lastPathComponent)")
        } catch {
            logger.error("Failed to save file: \(error.localizedDescription)")
        }

        // Clean up
        inboundChunks.removeValue(forKey: id)
        lastChunkTime.removeValue(forKey: id)
        // Keep metadata for display
    }

    private func handleNACK(_ request: FileChunkRequest) {
        guard let fileData = outboundData[request.transferID] else { return }

        let chunkSize = FileChunk.maxChunkSize
        for index in request.missingIndices {
            let start = Int(index) * chunkSize
            let end = min(start + chunkSize, fileData.count)
            guard start < fileData.count else { continue }

            let chunk = FileChunk(
                transferID: request.transferID,
                chunkIndex: index,
                data: fileData[start..<end]
            )

            let channelID = activeTransfers[request.transferID]?.channelID ?? ""
            let chunkPayload = chunk.wirePayload()
            let encrypted = encryptIfNeeded(chunkPayload, channelID: channelID)
            onSendPacket?(encrypted, channelID)
        }

        logger.info("Resent \(request.missingIndices.count) chunks for \(request.transferID)")
    }

    // MARK: - NACK Monitor

    private func startNACKMonitor() {
        nackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { break }
                self.checkForStalls()
            }
        }
    }

    private func checkForStalls() {
        let now = Date()
        for (id, lastTime) in lastChunkTime {
            guard let metadata = inboundMetadata[id],
                  let chunks = inboundChunks[id],
                  chunks.count < Int(metadata.chunkCount),
                  now.timeIntervalSince(lastTime) > 10 else { continue }

            // Find missing indices
            let received = Set(chunks.keys)
            let missing = (0..<metadata.chunkCount).filter { !received.contains($0) }
            guard !missing.isEmpty else { continue }

            let request = FileChunkRequest(
                transferID: id,
                requestingPeerID: "", // filled by caller
                missingIndices: Array(missing.prefix(50)) // request max 50 at a time
            )

            if let payload = try? request.wirePayload() {
                let encrypted = encryptIfNeeded(payload, channelID: metadata.channelID)
                onSendPacket?(encrypted, metadata.channelID)
            }

            lastChunkTime[id] = now // reset timer
            logger.info("Sent NACK for \(missing.count) chunks of \(id)")
        }

        // Clean up stale incomplete transfers
        for (id, lastTime) in lastChunkTime {
            if now.timeIntervalSince(lastTime) > Self.staleTransferTimeout {
                inboundChunks.removeValue(forKey: id)
                inboundMetadata.removeValue(forKey: id)
                lastChunkTime.removeValue(forKey: id)
                activeTransfers.removeValue(forKey: id)
                logger.info("Cleaned up stale transfer \(id)")
            }
        }

        // Clean up completed outbound transfers from activeTransfers after 5 minutes
        for (id, transfer) in activeTransfers where transfer.isOutbound && transfer.isComplete {
            if let meta = inboundMetadata[id], now.timeIntervalSince(meta.timestamp) > Self.staleTransferTimeout {
                activeTransfers.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Encryption

    private func encryptIfNeeded(_ data: Data, channelID: String) -> Data {
        guard let crypto = channelCryptoProvider?(channelID) else { return data }
        do {
            return try crypto.encrypt(data)
        } catch {
            logger.error("File encryption failed, sending unencrypted: \(error.localizedDescription)")
            return data
        }
    }

    private func decryptIfNeeded(_ data: Data, channelID: String) -> Data {
        guard let crypto = channelCryptoProvider?(channelID) else { return data }
        do {
            return try crypto.decrypt(data)
        } catch {
            logger.error("File decryption failed, returning raw data: \(error.localizedDescription)")
            return data
        }
    }
}

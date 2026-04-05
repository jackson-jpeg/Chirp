import CryptoKit
import Foundation
import Observation
import OSLog

/// Errors that can occur during mesh backup retrieval.
enum MeshCloudError: Error, Sendable {
    case noMetadata
    case timeout
    case missingChunks([UInt16])
    case insufficientShards(have: Int, need: Int)
    case keyReconstructionFailed
    case invalidKeySize(Int)
    case decryptionFailed
    case integrityCheckFailed
    case cancelled
}

/// Distributed encrypted backup service across mesh nodes.
///
/// Uses a hybrid Shamir approach:
/// 1. Encrypt the file with a random AES-256 key
/// 2. Split ONLY the 32-byte key via Shamir's Secret Sharing (k-of-n)
/// 3. Distribute encrypted file chunks to mesh peers (all get same chunks)
/// 4. Each peer gets a unique key shard
/// 5. Retrieval: need k peers to reconstruct the key + any peer for encrypted data
@Observable
@MainActor
final class MeshCloudService {

    // MARK: - Public State

    private(set) var localBackups: [BackupMetadata] = []
    private(set) var storageDonated: Int = 0  // bytes donated to others
    private(set) var storageUsed: Int = 0     // bytes of our own backups on mesh
    private(set) var isRetrieving: Bool = false
    private(set) var retrievalProgress: Float = 0

    var storageQuotaMB: Int = 50 {
        didSet {
            UserDefaults.standard.set(storageQuotaMB, forKey: Keys.quotaMB)
            Task { await chunkStore.setQuota(storageQuotaMB * 1024 * 1024) }
        }
    }

    var isDonating: Bool = true {
        didSet { UserDefaults.standard.set(isDonating, forKey: Keys.donating) }
    }

    // MARK: - Callbacks

    /// Send a packet to a specific peer or broadcast (empty string = broadcast).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private

    private let chunkStore = BackupChunkStore()
    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshCloud")
    private let localPeerID: String
    private let localFingerprint: String

    /// Chunks collected during active retrieval.
    private var retrievalChunks: [UInt16: Data] = [:]
    private var retrievalShards: [ShamirSplitter.Share] = []
    private var activeRetrievalMeta: BackupMetadata?

    /// Continuation for async retrieveBackup flow.
    private var retrievalContinuation: CheckedContinuation<Data, Error>?

    private static let chunkSize = 2048  // 2 KB per chunk
    private static let expiryDays: TimeInterval = 30 * 24 * 60 * 60
    static let defaultRetrievalTimeout: TimeInterval = 60  // seconds per retry round
    static let defaultMaxRetries = 3

    /// Override for testing -- set before calling retrieveBackup.
    var retrievalTimeoutOverride: TimeInterval?
    var maxRetriesOverride: Int?

    private var effectiveTimeout: TimeInterval {
        retrievalTimeoutOverride ?? Self.defaultRetrievalTimeout
    }
    private var effectiveMaxRetries: Int {
        maxRetriesOverride ?? Self.defaultMaxRetries
    }

    private enum Keys {
        static let quotaMB = "com.chirpchirp.meshcloud.quotaMB"
        static let donating = "com.chirpchirp.meshcloud.donating"
        static let localBackups = "com.chirpchirp.meshcloud.localBackups"
    }

    // MARK: - Init

    init(localPeerID: String, localFingerprint: String) {
        self.localPeerID = localPeerID
        self.localFingerprint = localFingerprint

        // Restore persisted settings
        let savedQuota = UserDefaults.standard.integer(forKey: Keys.quotaMB)
        if savedQuota > 0 {
            self.storageQuotaMB = savedQuota
        }
        self.isDonating = UserDefaults.standard.object(forKey: Keys.donating) as? Bool ?? true

        // Restore local backup metadata
        if let data = UserDefaults.standard.data(forKey: Keys.localBackups),
           let backups = try? MeshCodable.decoder.decode([BackupMetadata].self, from: data) {
            self.localBackups = backups
        }

        // Start periodic cleanup
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))  // Every hour
                guard let self else { break }
                await self.chunkStore.cleanupExpired()
                await self.updateStorageStats()
            }
        }

        // Initial stats update
        Task { await updateStorageStats() }
    }

    // MARK: - Backup

    /// Create a mesh backup of the given file data.
    /// Encrypts the file, splits the key via Shamir, and distributes to peers.
    func createBackup(fileData: Data, fileName: String, peerCount: Int) async {
        guard peerCount >= 2 else {
            logger.warning("Need at least 2 peers for mesh backup")
            return
        }

        let n = min(peerCount, 5)
        let k = 2  // threshold: any 2 peers can reconstruct

        // 1. Generate random AES-256 key
        let symmetricKey = SymmetricKey(size: .bits256)
        let keyData = symmetricKey.withUnsafeBytes { Data($0) }

        // 2. Encrypt file with AES-GCM
        guard let sealedBox = try? AES.GCM.seal(fileData, using: symmetricKey),
              let combined = sealedBox.combined else {
            logger.error("Failed to encrypt backup data")
            return
        }

        // 3. Split the 32-byte key via Shamir
        guard let shares = ShamirSplitter.split(secret: keyData, threshold: k, shares: n) else {
            logger.error("Failed to split key via Shamir")
            return
        }

        // 4. Chunk the encrypted data
        let backupID = UUID()
        let chunkCount = UInt16(clamping: (combined.count + Self.chunkSize - 1) / Self.chunkSize)
        let expiresAt = Date().addingTimeInterval(Self.expiryDays)

        // SHA-256 hash of original plaintext for integrity verification on retrieval
        let fileHash = Data(SHA256.hash(data: fileData))

        let metadata = BackupMetadata(
            id: backupID,
            ownerPeerID: localPeerID,
            ownerFingerprint: localFingerprint,
            fileName: fileName,
            totalSize: UInt64(fileData.count),
            chunkCount: chunkCount,
            threshold: k,
            totalShares: n,
            timestamp: Date(),
            fileHash: fileHash
        )

        // Save metadata locally
        localBackups.append(metadata)
        persistLocalBackups()

        logger.info("Creating backup \(backupID): \(fileName), \(combined.count) bytes, \(chunkCount) chunks, \(n) shares (k=\(k))")

        // 5. Distribute chunks to each peer
        for peerIndex in 0..<n {
            let shard = shares[peerIndex]

            for chunkIdx in 0..<chunkCount {
                let start = Int(chunkIdx) * Self.chunkSize
                let end = min(start + Self.chunkSize, combined.count)
                let chunkData = combined[start..<end]

                let chunk = BackupChunk(
                    backupID: backupID,
                    chunkIndex: chunkIdx,
                    encryptedData: Data(chunkData),
                    keyShard: chunkIdx == 0 ? shard : nil,  // Shard only on first chunk
                    metadata: chunkIdx == 0 ? metadata : nil,  // Metadata only on first chunk
                    expiresAt: expiresAt
                )

                do {
                    let payload = try chunk.wirePayload()
                    onSendPacket?(payload, "")  // Broadcast to mesh
                } catch {
                    logger.error("Failed to encode chunk \(chunkIdx) for peer \(peerIndex): \(error.localizedDescription)")
                }
            }
        }

        storageUsed += combined.count
        logger.info("Backup \(backupID) distributed to mesh")
    }

    // MARK: - Retrieval

    /// Request retrieval of a backup from the mesh.
    func requestRetrieval(backupID: UUID) async {
        guard let meta = localBackups.first(where: { $0.id == backupID }) else {
            logger.warning("No local metadata for backup \(backupID)")
            return
        }

        isRetrieving = true
        retrievalProgress = 0
        retrievalChunks = [:]
        retrievalShards = []
        activeRetrievalMeta = meta

        let request = BackupRetrievalRequest(
            backupID: backupID,
            requestingPeerID: localPeerID,
            requestingFingerprint: localFingerprint
        )

        do {
            let payload = try request.wirePayload()
            onSendPacket?(payload, "")  // Broadcast request
            logger.info("Sent retrieval request for backup \(backupID)")
        } catch {
            logger.error("Failed to send retrieval request: \(error.localizedDescription)")
            isRetrieving = false
        }
    }

    /// Cancel an active retrieval.
    func cancelRetrieval() {
        let continuation = retrievalContinuation
        retrievalContinuation = nil
        isRetrieving = false
        retrievalProgress = 0
        retrievalChunks = [:]
        retrievalShards = []
        activeRetrievalMeta = nil
        continuation?.resume(throwing: MeshCloudError.cancelled)
    }

    /// Retrieve and decrypt a backup from the mesh.
    ///
    /// Broadcasts retrieval requests, collects chunks with timeout and retry,
    /// reassembles, reconstructs the AES key, decrypts, and verifies integrity.
    /// Returns the original plaintext data.
    func retrieveBackup(backupID: UUID) async throws -> Data {
        guard let meta = localBackups.first(where: { $0.id == backupID }) else {
            logger.warning("No local metadata for backup \(backupID)")
            throw MeshCloudError.noMetadata
        }

        // Reset retrieval state
        isRetrieving = true
        retrievalProgress = 0
        retrievalChunks = [:]
        retrievalShards = []
        activeRetrievalMeta = meta

        defer {
            isRetrieving = false
            retrievalChunks = [:]
            retrievalShards = []
            activeRetrievalMeta = nil
            retrievalContinuation = nil
        }

        var lastError: Error = MeshCloudError.timeout

        let maxRetries = self.effectiveMaxRetries
        let timeout = self.effectiveTimeout

        for attempt in 1...maxRetries {
            logger.info("Retrieval attempt \(attempt)/\(maxRetries) for backup \(backupID)")

            // Broadcast BRQ! retrieval request
            let request = BackupRetrievalRequest(
                backupID: backupID,
                requestingPeerID: localPeerID,
                requestingFingerprint: localFingerprint
            )

            do {
                let payload = try request.wirePayload()
                onSendPacket?(payload, "")
            } catch {
                logger.error("Failed to send retrieval request: \(error.localizedDescription)")
                lastError = error
                continue
            }

            // Wait for chunks via continuation with timeout
            do {
                let decrypted: Data = try await withCheckedThrowingContinuation { continuation in
                    self.retrievalContinuation = continuation

                    // Start timeout watchdog
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(timeout))
                        guard let self = self, self.retrievalContinuation != nil else { return }
                        let cont = self.retrievalContinuation
                        self.retrievalContinuation = nil
                        cont?.resume(throwing: MeshCloudError.timeout)
                    }
                }

                // Continuation was resumed with decrypted data -- success
                retrievalProgress = 1.0
                return decrypted
            } catch {
                lastError = error
                // Log missing state for retry
                let totalChunks = Int(meta.chunkCount)
                let missing = (0..<UInt16(totalChunks)).filter { retrievalChunks[$0] == nil }
                if !missing.isEmpty {
                    logger.warning("Missing \(missing.count) chunks after attempt \(attempt)")
                }
                if retrievalShards.count < meta.threshold {
                    logger.warning("Only \(self.retrievalShards.count)/\(meta.threshold) shards after attempt \(attempt)")
                }
                // Don't clear collected chunks/shards between retries -- accumulate
                continue
            }
        }

        logger.error("Retrieval failed after \(maxRetries) attempts for backup \(backupID)")
        throw lastError
    }

    // MARK: - Packet Handling

    /// Handle an incoming backup chunk from a peer.
    func handleBackupChunk(_ payload: Data) {
        guard let chunk = BackupChunk.from(payload: payload) else { return }

        // If we're the owner retrieving this backup
        if isRetrieving, let meta = activeRetrievalMeta, chunk.backupID == meta.id {
            handleRetrievalChunk(chunk, metadata: meta)
            return
        }

        // Otherwise, store it as a donation (if donating is enabled)
        guard isDonating else { return }

        Task {
            await chunkStore.storeChunk(chunk)
            await updateStorageStats()
        }

        logger.info("Stored donated chunk: backup=\(chunk.backupID), index=\(chunk.chunkIndex)")
    }

    /// Handle an incoming retrieval request from a peer.
    func handleRetrievalRequest(_ payload: Data) {
        guard let request = BackupRetrievalRequest.from(payload: payload) else { return }

        logger.info("Retrieval request from \(request.requestingPeerID) for backup \(request.backupID)")

        // Check if we have chunks for this backup
        Task {
            let stored = await chunkStore.entriesForBackup(request.backupID)
            guard !stored.isEmpty else {
                logger.info("No chunks stored for backup \(request.backupID)")
                return
            }

            // Send back all chunks we have
            for entry in stored {
                guard let result = await chunkStore.retrieveChunk(
                    backupID: entry.backupID,
                    chunkIndex: entry.chunkIndex
                ) else { continue }

                let chunk = BackupChunk(
                    backupID: entry.backupID,
                    chunkIndex: entry.chunkIndex,
                    encryptedData: result.data,
                    keyShard: entry.keyShard,
                    metadata: entry.metadata,
                    expiresAt: entry.expiresAt
                )

                do {
                    let wireData = try chunk.wirePayload()
                    await MainActor.run {
                        self.onSendPacket?(wireData, "")
                    }
                } catch {
                    Logger(subsystem: Constants.subsystem, category: "MeshCloud")
                        .error("Failed to send stored chunk: \(error.localizedDescription)")
                }
            }

            Logger(subsystem: Constants.subsystem, category: "MeshCloud")
                .info("Sent \(stored.count) stored chunks for backup \(request.backupID)")
        }
    }

    // MARK: - Private: Retrieval Assembly

    private func handleRetrievalChunk(_ chunk: BackupChunk, metadata: BackupMetadata) {
        // Store the encrypted data chunk
        retrievalChunks[chunk.chunkIndex] = chunk.encryptedData

        // Collect key shard if present
        if let shard = chunk.keyShard {
            // Avoid duplicate shards (same x value)
            if !retrievalShards.contains(where: { $0.x == shard.x }) {
                retrievalShards.append(shard)
            }
        }

        // Update progress
        let totalChunks = max(1, Int(metadata.chunkCount))
        retrievalProgress = Float(retrievalChunks.count) / Float(totalChunks)

        logger.info("Retrieval progress: \(self.retrievalChunks.count)/\(totalChunks) chunks, \(self.retrievalShards.count)/\(metadata.threshold) shards")

        // Check if we can reconstruct
        guard retrievalChunks.count == totalChunks,
              retrievalShards.count >= metadata.threshold else {
            return
        }

        // Reconstruct!
        assembleBackup(metadata: metadata)
    }

    private func assembleBackup(metadata: BackupMetadata) {
        // 1. Reconstruct the AES key from shards
        let shardsToUse = Array(retrievalShards.prefix(metadata.threshold))
        guard let keyData = ShamirSplitter.reconstruct(shares: shardsToUse) else {
            logger.error("Failed to reconstruct key from \(shardsToUse.count) shards")
            let cont = retrievalContinuation
            retrievalContinuation = nil
            isRetrieving = false
            cont?.resume(throwing: MeshCloudError.keyReconstructionFailed)
            return
        }

        guard keyData.count == 32 else {
            logger.error("Reconstructed key has wrong size: \(keyData.count)")
            let cont = retrievalContinuation
            retrievalContinuation = nil
            isRetrieving = false
            cont?.resume(throwing: MeshCloudError.invalidKeySize(keyData.count))
            return
        }

        let symmetricKey = SymmetricKey(data: keyData)

        // 2. Reassemble encrypted data in order
        var combinedEncrypted = Data()
        for i in 0..<metadata.chunkCount {
            guard let chunkData = retrievalChunks[i] else {
                logger.error("Missing chunk \(i) during assembly")
                let cont = retrievalContinuation
                retrievalContinuation = nil
                isRetrieving = false
                cont?.resume(throwing: MeshCloudError.missingChunks([i]))
                return
            }
            combinedEncrypted.append(chunkData)
        }

        // 3. Decrypt with AES-GCM
        let decrypted: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedEncrypted)
            decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            logger.error("Failed to decrypt backup: \(error.localizedDescription)")
            let cont = retrievalContinuation
            retrievalContinuation = nil
            isRetrieving = false
            cont?.resume(throwing: MeshCloudError.decryptionFailed)
            return
        }

        // 4. SHA-256 integrity verification
        if let expectedHash = metadata.fileHash {
            let actualHash = Data(SHA256.hash(data: decrypted))
            guard actualHash == expectedHash else {
                logger.error("Integrity check failed: hash mismatch for \(metadata.fileName)")
                let cont = retrievalContinuation
                retrievalContinuation = nil
                isRetrieving = false
                cont?.resume(throwing: MeshCloudError.integrityCheckFailed)
                return
            }
            logger.info("SHA-256 integrity verified for \(metadata.fileName)")
        }

        logger.info("Successfully recovered backup: \(metadata.fileName) (\(decrypted.count) bytes)")

        // Resume continuation if active (async retrieveBackup flow)
        if let cont = retrievalContinuation {
            retrievalContinuation = nil
            retrievalProgress = 1.0
            cont.resume(returning: decrypted)
            return
        }

        // Fallback: save to Documents (legacy requestRetrieval flow)
        do {
            let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = docsDir.appendingPathComponent("recovered_\(metadata.fileName)")
            try decrypted.write(to: fileURL)
        } catch {
            logger.error("Failed to write recovered file: \(error.localizedDescription)")
        }

        // Clean up retrieval state
        isRetrieving = false
        retrievalProgress = 1.0
        retrievalChunks = [:]
        retrievalShards = []
        activeRetrievalMeta = nil
    }

    // MARK: - Storage Stats

    private func updateStorageStats() async {
        storageDonated = await chunkStore.totalBytesUsed
    }

    // MARK: - Persistence

    private func persistLocalBackups() {
        guard let data = try? MeshCodable.encoder.encode(localBackups) else { return }
        UserDefaults.standard.set(data, forKey: Keys.localBackups)
    }
}

// MARK: - BackupChunkStore Quota Extension

extension BackupChunkStore {
    func setQuota(_ bytes: Int) {
        quotaBytes = bytes
    }
}

import Foundation
import OSLog

/// Disk-based storage for other nodes' backup chunks and key shards.
///
/// Each chunk is stored as `{backupID}_{chunkIndex}.dat` inside `Documents/mesh_cloud/`.
/// Metadata is tracked in-memory with periodic disk persistence. LRU eviction
/// when the configurable quota is exceeded. 30-day automatic expiry.
actor BackupChunkStore {

    // MARK: - Types

    struct StoredEntry: Codable, Sendable {
        let backupID: UUID
        let chunkIndex: UInt16
        let keyShard: ShamirSplitter.Share?
        let metadata: BackupMetadata?
        let expiresAt: Date
        let sizeBytes: Int
        var lastAccessDate: Date
    }

    // MARK: - Properties

    private(set) var entries: [String: StoredEntry] = [:]  // key = "{backupID}_{chunkIndex}"
    private(set) var totalBytesUsed: Int = 0
    var quotaBytes: Int = 50 * 1024 * 1024  // 50 MB default

    private let logger = Logger(subsystem: Constants.subsystem, category: "BackupChunkStore")

    private static let storageDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mesh_cloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let manifestURL: URL = {
        storageDirectory.appendingPathComponent("manifest.json")
    }()

    private static let expiryInterval: TimeInterval = 30 * 24 * 60 * 60  // 30 days

    // MARK: - Init

    init() {
        loadManifest()
    }

    // MARK: - Store

    func storeChunk(_ chunk: BackupChunk) {
        let key = chunkKey(backupID: chunk.backupID, chunkIndex: chunk.chunkIndex)
        let fileURL = Self.storageDirectory.appendingPathComponent("\(key).dat")

        // Encode encrypted data to disk
        do {
            try chunk.encryptedData.write(to: fileURL)
        } catch {
            logger.error("Failed to write chunk \(key): \(error.localizedDescription)")
            return
        }

        let entry = StoredEntry(
            backupID: chunk.backupID,
            chunkIndex: chunk.chunkIndex,
            keyShard: chunk.keyShard,
            metadata: chunk.metadata,
            expiresAt: chunk.expiresAt,
            sizeBytes: chunk.encryptedData.count,
            lastAccessDate: Date()
        )

        // If replacing an existing entry, subtract its size first
        if let existing = entries[key] {
            totalBytesUsed -= existing.sizeBytes
        }

        entries[key] = entry
        totalBytesUsed += chunk.encryptedData.count

        // Evict if over quota
        evictIfNeeded()

        // Persist manifest
        saveManifest()

        logger.info("Stored chunk \(key) (\(chunk.encryptedData.count) bytes)")
    }

    // MARK: - Retrieve

    func retrieveChunk(backupID: UUID, chunkIndex: UInt16) -> (data: Data, entry: StoredEntry)? {
        let key = chunkKey(backupID: backupID, chunkIndex: chunkIndex)
        guard var entry = entries[key] else { return nil }

        let fileURL = Self.storageDirectory.appendingPathComponent("\(key).dat")
        guard let data = try? Data(contentsOf: fileURL) else {
            // File missing — remove stale entry
            entries.removeValue(forKey: key)
            totalBytesUsed -= entry.sizeBytes
            saveManifest()
            return nil
        }

        // Update LRU timestamp
        entry.lastAccessDate = Date()
        entries[key] = entry
        saveManifest()

        return (data, entry)
    }

    /// Return all stored entries for a given backup ID.
    func entriesForBackup(_ backupID: UUID) -> [StoredEntry] {
        entries.values.filter { $0.backupID == backupID }
    }

    /// Return unique backup IDs we are storing chunks for.
    func storedBackupIDs() -> Set<UUID> {
        Set(entries.values.map(\.backupID))
    }

    /// Count of unique backups stored.
    var storedBackupCount: Int {
        storedBackupIDs().count
    }

    /// Total number of individual chunks stored.
    var storedChunkCount: Int {
        entries.count
    }

    // MARK: - Expiry

    func cleanupExpired() {
        let now = Date()
        let expired = entries.filter { $0.value.expiresAt < now }

        for (key, entry) in expired {
            let fileURL = Self.storageDirectory.appendingPathComponent("\(key).dat")
            try? FileManager.default.removeItem(at: fileURL)
            entries.removeValue(forKey: key)
            totalBytesUsed -= entry.sizeBytes
        }

        if !expired.isEmpty {
            saveManifest()
            logger.info("Cleaned up \(expired.count) expired chunks")
        }
    }

    // MARK: - LRU Eviction

    private func evictIfNeeded() {
        guard totalBytesUsed > quotaBytes else { return }

        // Sort by last access date (oldest first)
        let sorted = entries.sorted { $0.value.lastAccessDate < $1.value.lastAccessDate }

        for (key, entry) in sorted {
            guard totalBytesUsed > quotaBytes else { break }

            let fileURL = Self.storageDirectory.appendingPathComponent("\(key).dat")
            try? FileManager.default.removeItem(at: fileURL)
            entries.removeValue(forKey: key)
            totalBytesUsed -= entry.sizeBytes

            logger.info("Evicted chunk \(key) (LRU)")
        }

        saveManifest()
    }

    // MARK: - Manifest Persistence

    private func loadManifest() {
        guard let data = try? Data(contentsOf: Self.manifestURL),
              let manifest = try? MeshCodable.decoder.decode([String: StoredEntry].self, from: data) else {
            return
        }

        entries = manifest
        totalBytesUsed = manifest.values.reduce(0) { $0 + $1.sizeBytes }
        logger.info("Loaded manifest: \(manifest.count) entries, \(self.totalBytesUsed) bytes")
    }

    private func saveManifest() {
        guard let data = try? MeshCodable.encoder.encode(entries) else { return }
        try? data.write(to: Self.manifestURL, options: .atomic)
    }

    // MARK: - Helpers

    private func chunkKey(backupID: UUID, chunkIndex: UInt16) -> String {
        "\(backupID.uuidString)_\(chunkIndex)"
    }
}

import CryptoKit
import XCTest
@testable import Chirp

final class MeshCloudTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetadata(fileHash: Data? = nil) -> BackupMetadata {
        BackupMetadata(
            id: UUID(),
            ownerPeerID: "peer-owner",
            ownerFingerprint: "abc123fingerprint",
            fileName: "notes.txt",
            totalSize: 4096,
            chunkCount: 3,
            threshold: 2,
            totalShares: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            fileHash: fileHash
        )
    }

    private func makeShard() -> ShamirSplitter.Share {
        ShamirSplitter.Share(x: 1, y: Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // MARK: - BackupMetadata Codable Round-Trip

    func testBackupMetadataCodableRoundTrip() throws {
        let metadata = makeMetadata()

        let encoded = try MeshCodable.encoder.encode(metadata)
        let decoded = try MeshCodable.decoder.decode(BackupMetadata.self, from: encoded)

        XCTAssertEqual(decoded.id, metadata.id)
        XCTAssertEqual(decoded.ownerPeerID, "peer-owner")
        XCTAssertEqual(decoded.ownerFingerprint, "abc123fingerprint")
        XCTAssertEqual(decoded.fileName, "notes.txt")
        XCTAssertEqual(decoded.totalSize, 4096)
        XCTAssertEqual(decoded.chunkCount, 3)
        XCTAssertEqual(decoded.threshold, 2)
        XCTAssertEqual(decoded.totalShares, 5)
    }

    // MARK: - BackupChunk Wire Round-Trip

    func testBackupChunkWireRoundTrip() throws {
        let metadata = makeMetadata()
        let shard = makeShard()
        let chunk = BackupChunk(
            backupID: metadata.id,
            chunkIndex: 0,
            encryptedData: Data([0x01, 0x02, 0x03, 0x04]),
            keyShard: shard,
            metadata: metadata,
            expiresAt: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let wireData = try chunk.wirePayload()

        // Verify BCK! prefix
        let prefix = Data(BackupChunk.magicPrefix)
        XCTAssertEqual(wireData.prefix(prefix.count), prefix)

        // Decode back
        let decoded = BackupChunk.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.backupID, metadata.id)
        XCTAssertEqual(decoded?.chunkIndex, 0)
        XCTAssertEqual(decoded?.encryptedData, Data([0x01, 0x02, 0x03, 0x04]))
    }

    // MARK: - BackupChunk With KeyShard

    func testBackupChunkWithKeyShard() throws {
        let shard = makeShard()
        let chunk = BackupChunk(
            backupID: UUID(),
            chunkIndex: 0,
            encryptedData: Data([0xFF]),
            keyShard: shard,
            metadata: nil,
            expiresAt: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let wireData = try chunk.wirePayload()
        let decoded = BackupChunk.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertNotNil(decoded?.keyShard)
        XCTAssertEqual(decoded?.keyShard?.x, 1)
        XCTAssertEqual(decoded?.keyShard?.y, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // MARK: - BackupChunk Without KeyShard

    func testBackupChunkWithoutKeyShard() throws {
        let chunk = BackupChunk(
            backupID: UUID(),
            chunkIndex: 2,
            encryptedData: Data([0xAA, 0xBB]),
            keyShard: nil,
            metadata: nil,
            expiresAt: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let wireData = try chunk.wirePayload()
        let decoded = BackupChunk.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.keyShard)
        XCTAssertEqual(decoded?.chunkIndex, 2)
    }

    // MARK: - BackupRetrievalRequest Wire Round-Trip

    func testBackupRetrievalRequestWireRoundTrip() throws {
        let backupID = UUID()
        let request = BackupRetrievalRequest(
            backupID: backupID,
            requestingPeerID: "peer-requester",
            requestingFingerprint: "fp-xyz"
        )

        let wireData = try request.wirePayload()

        // Verify BRQ! prefix
        let prefix = Data(BackupRetrievalRequest.magicPrefix)
        XCTAssertEqual(wireData.prefix(prefix.count), prefix)

        // Decode back
        let decoded = BackupRetrievalRequest.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.backupID, backupID)
        XCTAssertEqual(decoded?.requestingPeerID, "peer-requester")
        XCTAssertEqual(decoded?.requestingFingerprint, "fp-xyz")
    }

    // MARK: - BCK Magic Priority

    func testBCKMagicPriority() {
        let payload = Data([0x42, 0x43, 0x4B, 0x21, 0x00, 0x00])
        let priority = MeshPacket.inferPriority(type: .control, payload: payload)
        XCTAssertEqual(priority, .normal)
    }

    // MARK: - BRQ Magic Priority

    func testBRQMagicPriority() {
        let payload = Data([0x42, 0x52, 0x51, 0x21, 0x00, 0x00])
        let priority = MeshPacket.inferPriority(type: .control, payload: payload)
        XCTAssertEqual(priority, .high)
    }

    // MARK: - Shamir Split / Reconstruct Round-Trip

    func testShamirSplitReconstructRoundTrip() {
        let secret = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                           0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                           0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
                           0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20])

        guard let shares = ShamirSplitter.split(secret: secret, threshold: 2, shares: 3) else {
            XCTFail("Failed to split secret")
            return
        }

        XCTAssertEqual(shares.count, 3)

        // Any 2 shares should reconstruct the secret
        let reconstructed = ShamirSplitter.reconstruct(shares: Array(shares.prefix(2)))
        XCTAssertEqual(reconstructed, secret)

        // Different pair should also work
        let reconstructed2 = ShamirSplitter.reconstruct(shares: [shares[0], shares[2]])
        XCTAssertEqual(reconstructed2, secret)
    }

    // MARK: - Retrieval: Full Encrypt-Chunk-Reassemble Round-Trip

    @MainActor
    func testRetrieveBackupFullRoundTrip() async throws {
        // Clear persisted state from previous runs
        UserDefaults.standard.removeObject(forKey: "com.chirpchirp.meshcloud.localBackups")

        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fp")
        service.retrievalTimeoutOverride = 5
        service.maxRetriesOverride = 1

        // Capture all packets sent during backup creation
        var sentPackets: [Data] = []
        service.onSendPacket = { data, _ in
            sentPackets.append(data)
        }

        let originalData = Data(repeating: 0x42, count: 5000)  // ~3 chunks at 2KB each
        await service.createBackup(fileData: originalData, fileName: "test.bin", peerCount: 3)

        XCTAssertFalse(sentPackets.isEmpty, "Should have sent chunk packets")

        let backupID = service.localBackups.last!.id
        let meta = service.localBackups.last!

        // Parse all sent chunks for this backup
        let chunks = sentPackets.compactMap { BackupChunk.from(payload: $0) }
            .filter { $0.backupID == backupID }
        XCTAssertFalse(chunks.isEmpty)

        // Now simulate retrieval: feed chunks back into the service
        sentPackets = []
        service.onSendPacket = { data, _ in
            sentPackets.append(data)
        }

        // Start retrieval in a task
        let retrievalTask = Task { @MainActor in
            try await service.retrieveBackup(backupID: backupID)
        }

        // Small delay to let the continuation get set up
        try await Task.sleep(for: .milliseconds(50))

        // Feed in chunks from at least 2 peers (need 2 shards for threshold=2)
        var fedShardCount = 0
        var fedChunkIndices = Set<UInt16>()

        for chunk in chunks {
            // We need all chunk indices and at least 2 distinct shards
            if !fedChunkIndices.contains(chunk.chunkIndex) || (chunk.keyShard != nil && fedShardCount < meta.threshold) {
                service.handleBackupChunk(try chunk.wirePayload())
                fedChunkIndices.insert(chunk.chunkIndex)
                if chunk.keyShard != nil {
                    fedShardCount += 1
                }
            }

            // Stop once we have all chunks and enough shards
            if fedChunkIndices.count == Int(meta.chunkCount) && fedShardCount >= meta.threshold {
                break
            }
        }

        let decrypted = try await retrievalTask.value
        XCTAssertEqual(decrypted, originalData, "Decrypted data should match original")
    }

    // MARK: - Retrieval: SHA-256 Integrity Verification

    @MainActor
    func testRetrieveBackupIntegrityCheck() async throws {
        UserDefaults.standard.removeObject(forKey: "com.chirpchirp.meshcloud.localBackups")

        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fp")

        var sentPackets: [Data] = []
        service.onSendPacket = { data, _ in
            sentPackets.append(data)
        }

        let originalData = Data([0xCA, 0xFE, 0xBA, 0xBE])
        await service.createBackup(fileData: originalData, fileName: "tiny.bin", peerCount: 2)

        let meta = service.localBackups.last!

        // Verify the stored hash matches SHA-256 of original data
        let expectedHash = Data(SHA256.hash(data: originalData))
        XCTAssertNotNil(meta.fileHash)
        XCTAssertEqual(meta.fileHash, expectedHash)
    }

    // MARK: - Retrieval: No Metadata Error

    @MainActor
    func testRetrieveBackupNoMetadataThrows() async {
        UserDefaults.standard.removeObject(forKey: "com.chirpchirp.meshcloud.localBackups")

        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fp")
        service.onSendPacket = { _, _ in }

        do {
            _ = try await service.retrieveBackup(backupID: UUID())
            XCTFail("Should have thrown noMetadata error")
        } catch let error as MeshCloudError {
            if case .noMetadata = error {
                // Expected
            } else {
                XCTFail("Expected noMetadata, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Retrieval: Cancel

    @MainActor
    func testCancelRetrievalResetState() async throws {
        UserDefaults.standard.removeObject(forKey: "com.chirpchirp.meshcloud.localBackups")

        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fp")
        service.retrievalTimeoutOverride = 5
        service.maxRetriesOverride = 1

        var sentPackets: [Data] = []
        service.onSendPacket = { data, _ in
            sentPackets.append(data)
        }

        let originalData = Data(repeating: 0xAA, count: 100)
        await service.createBackup(fileData: originalData, fileName: "cancel.bin", peerCount: 2)

        let backupID = service.localBackups.last!.id

        // Start retrieval, then cancel before feeding chunks
        let retrievalTask = Task { @MainActor in
            try await service.retrieveBackup(backupID: backupID)
        }

        try await Task.sleep(for: .milliseconds(50))

        service.cancelRetrieval()

        do {
            _ = try await retrievalTask.value
            XCTFail("Should have thrown cancelled error")
        } catch let error as MeshCloudError {
            if case .cancelled = error {
                // Expected
            } else {
                XCTFail("Expected cancelled, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(service.isRetrieving)
    }

    // MARK: - Retrieval Request Wire Format

    @MainActor
    func testRetrievalBroadcastsBRQPacket() async throws {
        UserDefaults.standard.removeObject(forKey: "com.chirpchirp.meshcloud.localBackups")

        let service = MeshCloudService(localPeerID: "test-peer", localFingerprint: "test-fp")
        service.retrievalTimeoutOverride = 5
        service.maxRetriesOverride = 1

        var sentPackets: [Data] = []
        service.onSendPacket = { data, _ in
            sentPackets.append(data)
        }

        let originalData = Data(repeating: 0xBB, count: 100)
        await service.createBackup(fileData: originalData, fileName: "brq.bin", peerCount: 2)

        let backupID = service.localBackups.last!.id
        sentPackets = []  // Clear creation packets

        // Start retrieval -- it will broadcast BRQ! then wait
        let retrievalTask = Task { @MainActor in
            try await service.retrieveBackup(backupID: backupID)
        }

        try await Task.sleep(for: .milliseconds(50))

        // Verify BRQ! packet was sent
        let brqPrefix = Data(BackupRetrievalRequest.magicPrefix)
        let brqPackets = sentPackets.filter { $0.prefix(brqPrefix.count) == brqPrefix }
        XCTAssertFalse(brqPackets.isEmpty, "Should have broadcast BRQ! request")

        // Verify the BRQ! payload decodes correctly
        let decoded = BackupRetrievalRequest.from(payload: brqPackets[0])
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.backupID, backupID)
        XCTAssertEqual(decoded?.requestingPeerID, "test-peer")

        // Cancel to clean up
        service.cancelRetrieval()
        _ = try? await retrievalTask.value
    }

    // MARK: - Magic Prefix Uniqueness

    func testMagicPrefixUniqueness() {
        // All known V3 magic prefixes -- verify BCK! and BRQ! don't collide
        let allPrefixes: [[UInt8]] = [
            BackupChunk.magicPrefix,             // BCK!
            BackupRetrievalRequest.magicPrefix,  // BRQ!
            [0x46, 0x49, 0x4C, 0x21],           // FIL!
            [0x46, 0x4C, 0x43, 0x21],           // FLC!
            [0x46, 0x4E, 0x4B, 0x21],           // FNK!
            MeshScanReport.magicPrefix,          // SCN!
            SoundAlert.magicPrefix,              // SND!
            [0x41, 0x43, 0x4B, 0x21],           // ACK!
            [0x54, 0x58, 0x54, 0x21],           // TXT!
            [0x53, 0x4F, 0x53, 0x21],           // SOS!
            [0x42, 0x43, 0x4E, 0x21],           // BCN!
            [0x47, 0x57, 0x21, 0x00],           // GW! (may vary -- using placeholder)
            [0x47, 0x52, 0x21, 0x00],           // GR! (may vary -- using placeholder)
        ]

        // Convert to sets of Data for uniqueness check
        let dataSet = Set(allPrefixes.map { Data($0) })
        XCTAssertEqual(dataSet.count, allPrefixes.count, "Duplicate magic prefix detected")

        // Specifically verify BCK! and BRQ! are distinct
        XCTAssertNotEqual(
            Data(BackupChunk.magicPrefix),
            Data(BackupRetrievalRequest.magicPrefix)
        )
    }
}

import XCTest
@testable import Chirp

final class MeshCloudTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetadata() -> BackupMetadata {
        BackupMetadata(
            id: UUID(),
            ownerPeerID: "peer-owner",
            ownerFingerprint: "abc123fingerprint",
            fileName: "notes.txt",
            totalSize: 4096,
            chunkCount: 3,
            threshold: 2,
            totalShares: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
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

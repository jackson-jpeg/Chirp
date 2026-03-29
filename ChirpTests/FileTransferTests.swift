import XCTest
import CryptoKit
@testable import Chirp

final class FileTransferTests: XCTestCase {

    // MARK: - Helpers

    private func makeMetadata(
        id: UUID = UUID(),
        senderID: String = "sender-1",
        senderName: String = "Alice",
        channelID: String = "test-channel",
        fileName: String = "photo.jpg",
        mimeType: String = "image/jpeg",
        totalSize: UInt64 = 5000,
        chunkCount: UInt16 = 3,
        fileSHA256: Data = Data(SHA256.hash(data: Data(repeating: 0xAB, count: 5000))),
        timestamp: Date = Date()
    ) -> FileTransferMetadata {
        FileTransferMetadata(
            id: id,
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            fileName: fileName,
            mimeType: mimeType,
            totalSize: totalSize,
            chunkCount: chunkCount,
            fileSHA256: fileSHA256,
            timestamp: timestamp
        )
    }

    // MARK: - FileTransferMetadata round-trip

    func testFileTransferMetadataRoundTrip() throws {
        let id = UUID()
        let sha = Data(SHA256.hash(data: Data([1, 2, 3])))
        let original = makeMetadata(
            id: id,
            senderID: "peer-42",
            senderName: "Bob",
            channelID: "ch-99",
            fileName: "report.pdf",
            mimeType: "application/pdf",
            totalSize: 12345,
            chunkCount: 7,
            fileSHA256: sha
        )

        let wire = try original.wirePayload()
        let decoded = FileTransferMetadata.from(payload: wire)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, id)
        XCTAssertEqual(decoded?.senderID, "peer-42")
        XCTAssertEqual(decoded?.senderName, "Bob")
        XCTAssertEqual(decoded?.channelID, "ch-99")
        XCTAssertEqual(decoded?.fileName, "report.pdf")
        XCTAssertEqual(decoded?.mimeType, "application/pdf")
        XCTAssertEqual(decoded?.totalSize, 12345)
        XCTAssertEqual(decoded?.chunkCount, 7)
        XCTAssertEqual(decoded?.fileSHA256, sha)
    }

    // MARK: - FileChunk round-trip

    func testFileChunkRoundTrip() {
        let transferID = UUID()
        let chunkData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        let original = FileChunk(transferID: transferID, chunkIndex: 42, data: chunkData)

        let wire = original.wirePayload()
        let decoded = FileChunk.from(payload: wire)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.transferID, transferID)
        XCTAssertEqual(decoded?.chunkIndex, 42)
        XCTAssertEqual(decoded?.data, chunkData)
    }

    // MARK: - FileChunk binary format

    func testFileChunkBinaryFormat() {
        let transferID = UUID(uuid: (
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
        ))
        let chunkData = Data([0xFF, 0xFE])
        let chunk = FileChunk(transferID: transferID, chunkIndex: 0x0102, data: chunkData)

        let wire = chunk.wirePayload()

        // [FLC!:4]
        XCTAssertEqual(Array(wire[0..<4]), [0x46, 0x4C, 0x43, 0x21])

        // [UUID:16]
        for i in 0..<16 {
            XCTAssertEqual(wire[4 + i], UInt8(i), "UUID byte \(i)")
        }

        // [chunkIndex:2 big-endian] = 0x0102
        XCTAssertEqual(wire[20], 0x01)
        XCTAssertEqual(wire[21], 0x02)

        // [data:remaining]
        XCTAssertEqual(wire[22], 0xFF)
        XCTAssertEqual(wire[23], 0xFE)

        // Total: 4 + 16 + 2 + 2 = 24 bytes
        XCTAssertEqual(wire.count, 24)
    }

    // MARK: - FileChunkRequest round-trip

    func testFileChunkRequestRoundTrip() throws {
        let transferID = UUID()
        let missing: [UInt16] = [0, 3, 7, 15, 42]
        let original = FileChunkRequest(
            transferID: transferID,
            requestingPeerID: "requester-99",
            missingIndices: missing
        )

        let wire = try original.wirePayload()
        let decoded = FileChunkRequest.from(payload: wire)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.transferID, transferID)
        XCTAssertEqual(decoded?.requestingPeerID, "requester-99")
        XCTAssertEqual(decoded?.missingIndices, missing)
    }

    // MARK: - Chunking math

    func testChunkingMathProducesCorrectChunkCount() {
        // 5000 bytes / 2048 chunk size = ceil(5000/2048) = 3 chunks
        let fileSize = 5000
        let chunkSize = FileChunk.maxChunkSize // 2048
        let chunkCount = (fileSize + chunkSize - 1) / chunkSize

        XCTAssertEqual(chunkCount, 3)
        XCTAssertEqual(chunkSize, 2048)

        // Verify individual chunk sizes
        let chunk0Size = min(chunkSize, fileSize - 0 * chunkSize)  // 2048
        let chunk1Size = min(chunkSize, fileSize - 1 * chunkSize)  // 2048
        let chunk2Size = fileSize - 2 * chunkSize                   // 904

        XCTAssertEqual(chunk0Size, 2048)
        XCTAssertEqual(chunk1Size, 2048)
        XCTAssertEqual(chunk2Size, 904)
        XCTAssertEqual(chunk0Size + chunk1Size + chunk2Size, fileSize)
    }

    // MARK: - SHA256 integrity

    func testSHA256IntegrityAfterChunkAndReassemble() {
        let fileData = Data((0..<5000).map { UInt8($0 % 256) })
        let originalHash = Data(SHA256.hash(data: fileData))

        let chunkSize = FileChunk.maxChunkSize
        let chunkCount = (fileData.count + chunkSize - 1) / chunkSize

        // Chunk the file
        var chunks: [FileChunk] = []
        let transferID = UUID()
        for i in 0..<chunkCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, fileData.count)
            chunks.append(FileChunk(
                transferID: transferID,
                chunkIndex: UInt16(i),
                data: fileData[start..<end]
            ))
        }

        // Reassemble
        var assembled = Data()
        for i in 0..<chunkCount {
            assembled.append(chunks[i].data)
        }

        let reassembledHash = Data(SHA256.hash(data: assembled))
        XCTAssertEqual(reassembledHash, originalHash)
        XCTAssertEqual(assembled, fileData)
    }

    // MARK: - Magic prefix detection

    func testInferPriorityReturnsNormalForFileTransferMagicPrefixes() {
        // FIL!
        let filPayload = Data([0x46, 0x49, 0x4C, 0x21, 0x01, 0x02])
        XCTAssertEqual(
            MeshPacket.inferPriority(type: .control, payload: filPayload),
            .normal
        )

        // FLC!
        let flcPayload = Data([0x46, 0x4C, 0x43, 0x21, 0x01, 0x02])
        XCTAssertEqual(
            MeshPacket.inferPriority(type: .control, payload: flcPayload),
            .normal
        )

        // FNK!
        let fnkPayload = Data([0x46, 0x4E, 0x4B, 0x21, 0x01, 0x02])
        XCTAssertEqual(
            MeshPacket.inferPriority(type: .control, payload: fnkPayload),
            .normal
        )
    }

    // MARK: - Empty file (totalSize 0)

    func testEmptyFileMetadataEncodesAndDecodes() throws {
        let original = makeMetadata(
            totalSize: 0,
            chunkCount: 0,
            fileSHA256: Data(SHA256.hash(data: Data()))
        )

        let wire = try original.wirePayload()
        let decoded = FileTransferMetadata.from(payload: wire)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.totalSize, 0)
        XCTAssertEqual(decoded?.chunkCount, 0)
    }

    // MARK: - Max file size constant

    @MainActor
    func testMaxFileSizeIsFiveMB() {
        XCTAssertEqual(FileTransferService.maxFileSize, 5 * 1_048_576)
    }
}

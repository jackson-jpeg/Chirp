import CryptoKit
import XCTest
@testable import Chirp

// MARK: - MeshShield Layer 1 Tests

final class MeshShieldLayer1Tests: XCTestCase {

    func testLayer1RequiresChannelKeyToDecrypt() async throws {
        let channelKey = ChannelCrypto.generateKey()
        let crypto = ChannelCrypto(key: channelKey)
        let plaintext = Data("secret message".utf8)

        let encrypted = try await MeshShieldCrypto.encrypt(
            plaintext,
            channelCrypto: crypto,
            peerIdentity: PeerIdentity.shared
        )

        // Decrypt with correct channel key should succeed
        let decrypted = MeshShieldCrypto.decrypt(encrypted, channelCrypto: crypto)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testLayer1FailsWithWrongChannelKey() async throws {
        let correctKey = ChannelCrypto.generateKey()
        let wrongKey = ChannelCrypto.generateKey()
        let correctCrypto = ChannelCrypto(key: correctKey)
        let wrongCrypto = ChannelCrypto(key: wrongKey)
        let plaintext = Data("secret message".utf8)

        let encrypted = try await MeshShieldCrypto.encrypt(
            plaintext,
            channelCrypto: correctCrypto,
            peerIdentity: PeerIdentity.shared
        )

        // Decrypt with wrong channel key should fail — Layer 1 is bound to channel key
        let decrypted = MeshShieldCrypto.decrypt(encrypted, channelCrypto: wrongCrypto)
        XCTAssertNil(decrypted, "Layer 1 should not be decryptable without the correct channel key")
    }

    func testLayer1EphemeralPublicKeyAloneCannotDecrypt() async throws {
        let channelKey = ChannelCrypto.generateKey()
        let crypto = ChannelCrypto(key: channelKey)
        let plaintext = Data("test data".utf8)

        let encrypted = try await MeshShieldCrypto.encrypt(
            plaintext,
            channelCrypto: crypto,
            peerIdentity: PeerIdentity.shared
        )

        // Extract the ephemeral public key from the wire
        let ephemeralKeyData = Data(encrypted.prefix(32))
        let layer1Ciphertext = Data(encrypted.dropFirst(32))

        // Try to derive Layer 1 key from just the ephemeral key (the old vulnerable way)
        let attackerKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ephemeralKeyData),
            salt: Data("ChirpMeshShield-L1".utf8),
            info: Data(),
            outputByteCount: 32
        )

        // This should fail — the attacker doesn't have channel key material in info
        let sealedBox = try? AES.GCM.SealedBox(combined: layer1Ciphertext)
        let decrypted = sealedBox.flatMap { try? AES.GCM.open($0, using: attackerKey) }
        XCTAssertNil(decrypted, "Ephemeral public key alone must not be sufficient to strip Layer 1")
    }

    func testEncryptDecryptRoundTripWithEpoch() async throws {
        let channelKey = ChannelCrypto.generateKey()
        let crypto = ChannelCrypto(key: channelKey)
        let plaintext = Data("epoch-encrypted message".utf8)

        let encrypted = try await MeshShieldCrypto.encrypt(
            plaintext,
            channelCrypto: crypto,
            peerIdentity: PeerIdentity.shared,
            epoch: 5
        )

        let decrypted = MeshShieldCrypto.decrypt(encrypted, channelCrypto: crypto, currentEpoch: 5)
        XCTAssertEqual(decrypted, plaintext)
    }
}

// MARK: - Channel Key Rotation Tests

final class ChannelKeyRotationTests: XCTestCase {

    func testEpochKeyDiffersFromBaseKey() {
        let key = ChannelCrypto.generateKey()
        let crypto = ChannelCrypto(key: key)

        let baseKey = crypto.epochKey(epoch: 0)
        let epoch1Key = crypto.epochKey(epoch: 1)

        // Epoch 0 should return the base key
        let baseBytes = baseKey.withUnsafeBytes { Data($0) }
        let keyBytes = key.withUnsafeBytes { Data($0) }
        XCTAssertEqual(baseBytes, keyBytes)

        // Epoch 1 should be different
        let epoch1Bytes = epoch1Key.withUnsafeBytes { Data($0) }
        XCTAssertNotEqual(epoch1Bytes, keyBytes)
    }

    func testDifferentEpochsProduceDifferentKeys() {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())

        let key1 = crypto.epochKey(epoch: 1).withUnsafeBytes { Data($0) }
        let key2 = crypto.epochKey(epoch: 2).withUnsafeBytes { Data($0) }
        let key3 = crypto.epochKey(epoch: 3).withUnsafeBytes { Data($0) }

        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key2, key3)
        XCTAssertNotEqual(key1, key3)
    }

    func testEpochKeyIsDeterministic() {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())

        let first = crypto.epochKey(epoch: 42).withUnsafeBytes { Data($0) }
        let second = crypto.epochKey(epoch: 42).withUnsafeBytes { Data($0) }

        XCTAssertEqual(first, second)
    }

    func testEncryptDecryptWithMatchingEpoch() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plaintext = Data("rotated message".utf8)

        let encrypted = try crypto.encrypt(plaintext, epoch: 5)
        let decrypted = try crypto.decrypt(encrypted, currentEpoch: 5)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptWithLookbackWindow() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plaintext = Data("in-flight message".utf8)

        // Encrypt with epoch 3
        let encrypted = try crypto.encrypt(plaintext, epoch: 3)

        // Decrypt when current epoch has advanced to 5 (lookback of 2 covers epoch 3)
        let decrypted = try crypto.decrypt(encrypted, currentEpoch: 5, lookback: 2)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testLegacyFormatBackwardCompatibility() throws {
        let key = ChannelCrypto.generateKey()
        let crypto = ChannelCrypto(key: key)
        let plaintext = Data("legacy message".utf8)

        // Simulate legacy format: raw AES-GCM without epoch prefix
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let legacyCiphertext = sealedBox.combined!

        // Should still decrypt via legacy fallback
        let decrypted = try crypto.decrypt(legacyCiphertext, currentEpoch: 0)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEpochPrefixEncodedCorrectly() throws {
        let crypto = ChannelCrypto(key: ChannelCrypto.generateKey())
        let plaintext = Data("test".utf8)

        let encrypted = try crypto.encrypt(plaintext, epoch: 256)

        // First 4 bytes should be epoch 256 in big-endian
        let epochBytes = encrypted.prefix(4)
        let epoch = epochBytes.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        XCTAssertEqual(epoch, 256)
    }
}

// MARK: - Channel Manager Epoch Tests

@MainActor
final class ChannelManagerEpochTests: XCTestCase {

    func testCurrentEpochStartsAtZero() {
        let manager = ChannelManager()
        XCTAssertEqual(manager.currentEpoch(for: "test-channel"), 0)
    }

    func testAdvanceEpochIncrementsCounter() {
        let manager = ChannelManager()
        manager.advanceEpoch(for: "test-channel")
        XCTAssertEqual(manager.currentEpoch(for: "test-channel"), 1)
        manager.advanceEpoch(for: "test-channel")
        XCTAssertEqual(manager.currentEpoch(for: "test-channel"), 2)
    }

    func testHandleKeyRotationAdvancesWhenBehind() {
        let manager = ChannelManager()
        manager.handleKeyRotation(channelID: "test-channel", peerEpoch: 5)
        XCTAssertEqual(manager.currentEpoch(for: "test-channel"), 5)
    }

    func testHandleKeyRotationIgnoresWhenAhead() {
        let manager = ChannelManager()
        manager.advanceEpoch(for: "test-channel")
        manager.advanceEpoch(for: "test-channel")
        manager.advanceEpoch(for: "test-channel")
        // Current is 3, peer sends 1 — should be ignored
        manager.handleKeyRotation(channelID: "test-channel", peerEpoch: 1)
        XCTAssertEqual(manager.currentEpoch(for: "test-channel"), 3)
    }

    func testBuildAndParseKeyRotationPayload() {
        let manager = ChannelManager()
        manager.advanceEpoch(for: "my-channel")
        manager.advanceEpoch(for: "my-channel")

        let payload = manager.buildKeyRotationPayload(channelID: "my-channel")
        let parsed = ChannelManager.parseKeyRotationPayload(payload)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.channelID, "my-channel")
        XCTAssertEqual(parsed?.epoch, 2)
    }

    func testParseKeyRotationPayloadRejectsInvalid() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(ChannelManager.parseKeyRotationPayload(garbage))
    }
}

// MARK: - Replay Protection Tests

final class ReplayProtectionTests: XCTestCase {

    func testDuplicatePacketIDRejected() async {
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(
            onLocalDelivery: { _ in },
            onForward: { _, _ in }
        )

        let packet = MeshPacket(
            type: .control,
            ttl: 4,
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: 1,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: Data("test".utf8)
        )

        let first = await router.handleIncoming(packet: packet, fromPeer: "peer-1")
        let second = await router.handleIncoming(packet: packet, fromPeer: "peer-2")

        XCTAssertTrue(first, "First receipt should be accepted")
        XCTAssertFalse(second, "Duplicate packet ID should be rejected")
    }

    func testReplayedSequenceRejected() async {
        let originID = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(
            onLocalDelivery: { _ in },
            onForward: { _, _ in }
        )

        let packet1 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: 10,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("msg1".utf8)
        )
        let packet2 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: 5,  // lower sequence = replay
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("replayed".utf8)
        )

        let first = await router.handleIncoming(packet: packet1, fromPeer: "peer-1")
        let second = await router.handleIncoming(packet: packet2, fromPeer: "peer-1")

        XCTAssertTrue(first)
        XCTAssertFalse(second, "Packet with lower sequence from same origin should be rejected as replay")
    }

    func testHigherSequenceFromSameOriginAccepted() async {
        let originID = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(
            onLocalDelivery: { _ in },
            onForward: { _, _ in }
        )

        let packet1 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: 5,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("msg1".utf8)
        )
        let packet2 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: 10,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("msg2".utf8)
        )

        let first = await router.handleIncoming(packet: packet1, fromPeer: "peer-1")
        let second = await router.handleIncoming(packet: packet2, fromPeer: "peer-1")

        XCTAssertTrue(first)
        XCTAssertTrue(second, "Higher sequence from same origin should be accepted")
    }

    func testSequenceWraparoundHandled() async {
        let originID = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(
            onLocalDelivery: { _ in },
            onForward: { _, _ in }
        )

        // Start near UInt32.max
        let packet1 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: UInt32.max - 1,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("near-max".utf8)
        )
        // Wraparound to 0
        let packet2 = MeshPacket(
            type: .control, ttl: 4, originID: originID,
            packetID: UUID(), sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "", payload: Data("wrapped".utf8)
        )

        let first = await router.handleIncoming(packet: packet1, fromPeer: "peer-1")
        let second = await router.handleIncoming(packet: packet2, fromPeer: "peer-1")

        XCTAssertTrue(first)
        XCTAssertTrue(second, "Sequence wraparound from UInt32.max to 0 should be accepted")
    }
}

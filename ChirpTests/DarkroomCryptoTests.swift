import CryptoKit
import XCTest
@testable import Chirp

final class DarkroomCryptoTests: XCTestCase {

    // MARK: - Helpers

    private func makeKeyPair() -> (
        agreement: Curve25519.KeyAgreement.PrivateKey,
        signing: Curve25519.Signing.PrivateKey
    ) {
        (Curve25519.KeyAgreement.PrivateKey(), Curve25519.Signing.PrivateKey())
    }

    // MARK: - Seal/open round-trip

    func testSealOpenRoundTrip() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()
        let photoData = Data("JPEG image data here".utf8)

        let sealed = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        let decrypted = try DarkroomCrypto.open(
            sealed: sealed,
            recipientPrivateKey: recipient.agreement
        )

        XCTAssertEqual(decrypted, photoData)
    }

    // MARK: - Forward secrecy: different ephemeral keys

    func testForwardSecrecyDifferentCiphertext() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()
        let photoData = Data("Same photo data".utf8)

        let sealed1 = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        let sealed2 = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        // Different ephemeral keys should produce different ciphertext
        XCTAssertNotEqual(sealed1.ciphertext, sealed2.ciphertext)
        XCTAssertNotEqual(sealed1.ephemeralPublicKey, sealed2.ephemeralPublicKey)

        // Both should still decrypt correctly
        let decrypted1 = try DarkroomCrypto.open(sealed: sealed1, recipientPrivateKey: recipient.agreement)
        let decrypted2 = try DarkroomCrypto.open(sealed: sealed2, recipientPrivateKey: recipient.agreement)
        XCTAssertEqual(decrypted1, photoData)
        XCTAssertEqual(decrypted2, photoData)
    }

    // MARK: - Wrong recipient fails

    func testOpenWithWrongRecipientKeyThrows() throws {
        let sender = makeKeyPair()
        let recipientA = makeKeyPair()
        let recipientB = makeKeyPair()
        let photoData = Data("Secret photo".utf8)

        let sealed = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipientA.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        // Opening with B's key should fail
        XCTAssertThrowsError(try DarkroomCrypto.open(
            sealed: sealed,
            recipientPrivateKey: recipientB.agreement
        ))
    }

    // MARK: - Signature verification

    func testSenderSignatureIsValid() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()
        let photoData = Data("Signed photo".utf8)

        let sealed = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        // Verify sender's Ed25519 signature on the ciphertext
        let signingPublicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: sealed.senderSigningKey
        )
        let isValid = signingPublicKey.isValidSignature(sealed.signature, for: sealed.ciphertext)
        XCTAssertTrue(isValid)
    }

    func testTamperedCiphertextFailsSignatureVerification() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()
        let photoData = Data("Tamper test".utf8)

        let sealed = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        // Tamper with ciphertext
        var tampered = sealed.ciphertext
        tampered[0] ^= 0xFF

        let signingPublicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: sealed.senderSigningKey
        )
        let isValid = signingPublicKey.isValidSignature(sealed.signature, for: tampered)
        XCTAssertFalse(isValid)
    }

    // MARK: - DarkroomEnvelope wire round-trip

    func testDarkroomEnvelopeWireRoundTrip() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()
        let photoData = Data("Envelope test".utf8)

        let sealedPhoto = try DarkroomCrypto.seal(
            photoData: photoData,
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        let envelope = DarkroomEnvelope(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            recipientID: "peer-B",
            sealedPhoto: sealedPhoto,
            thumbnailHash: Data(repeating: 0xAA, count: 32),
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(86400)
        )

        let payload = try envelope.wirePayload()
        let decoded = DarkroomEnvelope.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, envelope.id)
        XCTAssertEqual(decoded?.senderID, "peer-A")
        XCTAssertEqual(decoded?.senderName, "Alice")
        XCTAssertEqual(decoded?.recipientID, "peer-B")
        XCTAssertEqual(decoded?.thumbnailHash, Data(repeating: 0xAA, count: 32))
        XCTAssertEqual(decoded?.sealedPhoto.ephemeralPublicKey, sealedPhoto.ephemeralPublicKey)
        XCTAssertEqual(decoded?.sealedPhoto.ciphertext, sealedPhoto.ciphertext)
    }

    func testDarkroomEnvelopeMagicPrefix() throws {
        let sender = makeKeyPair()
        let recipient = makeKeyPair()

        let sealedPhoto = try DarkroomCrypto.seal(
            photoData: Data("test".utf8),
            recipientPublicKey: recipient.agreement.publicKey,
            senderSigningKey: sender.signing
        )

        let envelope = DarkroomEnvelope(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            recipientID: "peer-B",
            sealedPhoto: sealedPhoto,
            thumbnailHash: Data(),
            timestamp: Date(),
            expiresAt: Date()
        )

        let payload = try envelope.wirePayload()

        // DRK! = 0x44, 0x52, 0x4B, 0x21
        XCTAssertEqual(payload[0], 0x44)
        XCTAssertEqual(payload[1], 0x52)
        XCTAssertEqual(payload[2], 0x4B)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - DarkroomViewACK wire round-trip

    func testDarkroomViewACKWireRoundTrip() throws {
        let ack = DarkroomViewACK(
            envelopeID: UUID(),
            viewerPeerID: "peer-B",
            viewedAt: Date()
        )

        let payload = try ack.wirePayload()
        let decoded = DarkroomViewACK.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.envelopeID, ack.envelopeID)
        XCTAssertEqual(decoded?.viewerPeerID, "peer-B")
    }

    func testDarkroomViewACKMagicPrefix() throws {
        let ack = DarkroomViewACK(
            envelopeID: UUID(),
            viewerPeerID: "peer-B",
            viewedAt: Date()
        )

        let payload = try ack.wirePayload()

        // DVK! = 0x44, 0x56, 0x4B, 0x21
        XCTAssertEqual(payload[0], 0x44)
        XCTAssertEqual(payload[1], 0x56)
        XCTAssertEqual(payload[2], 0x4B)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - Invalid payloads

    func testDarkroomEnvelopeFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(DarkroomEnvelope.from(payload: garbage))
    }

    func testDarkroomViewACKFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(DarkroomViewACK.from(payload: garbage))
    }
}

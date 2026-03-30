import XCTest
@testable import Chirp

final class DeadDropTests: XCTestCase {

    // MARK: - DeadDropCrypto: Key derivation determinism

    func testKeyDerivationDeterminism() {
        let key1 = DeadDropCrypto.deriveKey(geohash: "u4pruyd")
        let key2 = DeadDropCrypto.deriveKey(geohash: "u4pruyd")

        // Same geohash must produce same key
        key1.withUnsafeBytes { buf1 in
            key2.withUnsafeBytes { buf2 in
                XCTAssertEqual(Array(buf1), Array(buf2))
            }
        }
    }

    func testKeyDerivationDifferentGeohashDifferentKey() {
        let key1 = DeadDropCrypto.deriveKey(geohash: "u4pruyd")
        let key2 = DeadDropCrypto.deriveKey(geohash: "u4pruye")

        key1.withUnsafeBytes { buf1 in
            key2.withUnsafeBytes { buf2 in
                XCTAssertNotEqual(Array(buf1), Array(buf2))
            }
        }
    }

    // MARK: - Key derivation with time lock

    func testKeyDerivationSameGeohashDifferentDateDifferentKey() {
        let key1 = DeadDropCrypto.deriveKey(geohash: "u4pruyd", date: "2026-03-30")
        let key2 = DeadDropCrypto.deriveKey(geohash: "u4pruyd", date: "2026-03-31")

        key1.withUnsafeBytes { buf1 in
            key2.withUnsafeBytes { buf2 in
                XCTAssertNotEqual(Array(buf1), Array(buf2))
            }
        }
    }

    func testKeyDerivationWithAndWithoutDateDifferent() {
        let keyNoDate = DeadDropCrypto.deriveKey(geohash: "u4pruyd")
        let keyWithDate = DeadDropCrypto.deriveKey(geohash: "u4pruyd", date: "2026-03-30")

        keyNoDate.withUnsafeBytes { buf1 in
            keyWithDate.withUnsafeBytes { buf2 in
                XCTAssertNotEqual(Array(buf1), Array(buf2))
            }
        }
    }

    // MARK: - Seal/open round-trip

    func testSealOpenRoundTrip() throws {
        let plaintext = Data("Hello dead drop".utf8)
        let geohash = "u4pruyd"

        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: geohash)
        let decrypted = DeadDropCrypto.open(ciphertext, geohash: geohash)

        XCTAssertNotNil(decrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Wrong geohash fails

    func testOpenWithWrongGeohashFails() throws {
        let plaintext = Data("Secret message".utf8)
        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: "u4pruyd")

        let decrypted = DeadDropCrypto.open(ciphertext, geohash: "u4pruye")
        XCTAssertNil(decrypted)
    }

    // MARK: - Time lock

    func testTimeLockCorrectDateSucceeds() throws {
        let plaintext = Data("Time locked secret".utf8)
        let geohash = "u4pruyd"
        let date = "2026-03-30"

        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: geohash, date: date)
        let decrypted = DeadDropCrypto.open(ciphertext, geohash: geohash, date: date)

        XCTAssertNotNil(decrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testTimeLockWrongDateFails() throws {
        let plaintext = Data("Time locked secret".utf8)
        let geohash = "u4pruyd"

        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: geohash, date: "2026-03-30")
        let decrypted = DeadDropCrypto.open(ciphertext, geohash: geohash, date: "2026-04-01")

        XCTAssertNil(decrypted)
    }

    func testTimeLockNoDateOpenFails() throws {
        let plaintext = Data("Time locked".utf8)
        let geohash = "u4pruyd"

        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: geohash, date: "2026-03-30")
        // Try to open without providing date
        let decrypted = DeadDropCrypto.open(ciphertext, geohash: geohash)

        XCTAssertNil(decrypted)
    }

    // MARK: - Fuzzy matching: neighbor geohash fails

    func testOpenAtNeighborGeohashFails() throws {
        let geohash = Geohash.encode(latitude: 37.7749, longitude: -122.4194, precision: 7)
        let neighbors = Geohash.neighbors(of: geohash)
        guard let neighbor = neighbors.first else {
            XCTFail("Expected at least one neighbor")
            return
        }

        let plaintext = Data("Sealed at exact location".utf8)
        let ciphertext = try DeadDropCrypto.seal(plaintext, geohash: geohash)

        let decrypted = DeadDropCrypto.open(ciphertext, geohash: neighbor)
        XCTAssertNil(decrypted, "Decryption with neighbor geohash should fail")
    }

    // MARK: - DeadDropMessage wire format

    func testDeadDropMessageWireRoundTrip() throws {
        let message = DeadDropMessage(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            encryptedPayload: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            geohashPrefix: "u4pr",
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(86400),
            isTimeLocked: false,
            timeLockDate: nil,
            hasNextHint: false
        )

        let payload = try message.wirePayload()
        let decoded = DeadDropMessage.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, message.id)
        XCTAssertEqual(decoded?.senderID, "peer-A")
        XCTAssertEqual(decoded?.senderName, "Alice")
        XCTAssertEqual(decoded?.encryptedPayload, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(decoded?.geohashPrefix, "u4pr")
        XCTAssertEqual(decoded?.isTimeLocked, false)
        XCTAssertNil(decoded?.timeLockDate)
        XCTAssertEqual(decoded?.hasNextHint, false)
    }

    func testDeadDropMessageMagicPrefix() throws {
        let message = DeadDropMessage(
            id: UUID(),
            senderID: "peer-A",
            senderName: "Alice",
            encryptedPayload: Data(),
            geohashPrefix: "u4pr",
            timestamp: Date(),
            expiresAt: Date(),
            isTimeLocked: false,
            timeLockDate: nil,
            hasNextHint: false
        )

        let payload = try message.wirePayload()

        // DRP! = 0x44, 0x52, 0x50, 0x21
        XCTAssertEqual(payload[0], 0x44)
        XCTAssertEqual(payload[1], 0x52)
        XCTAssertEqual(payload[2], 0x50)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - DeadDropPickup wire format

    func testDeadDropPickupWireRoundTrip() throws {
        let pickup = DeadDropPickup(
            dropID: UUID(),
            pickerPeerID: "peer-B",
            timestamp: Date()
        )

        let payload = try pickup.wirePayload()
        let decoded = DeadDropPickup.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.dropID, pickup.dropID)
        XCTAssertEqual(decoded?.pickerPeerID, "peer-B")
    }

    func testDeadDropPickupMagicPrefix() throws {
        let pickup = DeadDropPickup(
            dropID: UUID(),
            pickerPeerID: "peer-B",
            timestamp: Date()
        )

        let payload = try pickup.wirePayload()

        // DPK! = 0x44, 0x50, 0x4B, 0x21
        XCTAssertEqual(payload[0], 0x44)
        XCTAssertEqual(payload[1], 0x50)
        XCTAssertEqual(payload[2], 0x4B)
        XCTAssertEqual(payload[3], 0x21)
    }

    // MARK: - Invalid payloads

    func testDeadDropMessageFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(DeadDropMessage.from(payload: garbage))
    }

    func testDeadDropPickupFromGarbageReturnsNil() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        XCTAssertNil(DeadDropPickup.from(payload: garbage))
    }
}

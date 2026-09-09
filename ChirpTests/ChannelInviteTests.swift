import CryptoKit
import XCTest
@testable import Chirp

// MARK: - Invite Code Round-Trip Tests

final class ChannelInviteCodeTests: XCTestCase {

    func testInviteCodeRoundTrip() {
        let channelID = UUID().uuidString
        let seed = ChannelCrypto.generateInviteSeed()

        let code = ChannelCrypto.createInviteCode(channelID: channelID, seed: seed)
        XCTAssertNotNil(code)

        let parsed = ChannelCrypto.parseInviteCode(code!)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.channelID, channelID)
        XCTAssertEqual(parsed?.seed, seed)

        let expectedKey = ChannelCrypto.keyFromInviteSeed(seed, channelID: channelID)
        XCTAssertEqual(
            parsed?.key.withUnsafeBytes { Data($0) },
            expectedKey.withUnsafeBytes { Data($0) }
        )
    }

    func testCreatorAndJoinerDeriveSameKey() throws {
        let channelID = UUID().uuidString
        let seed = ChannelCrypto.generateInviteSeed()
        let code = try XCTUnwrap(ChannelCrypto.createInviteCode(channelID: channelID, seed: seed))

        // Creator derives from the seed; joiner derives from the code.
        let creatorCrypto = ChannelCrypto(key: ChannelCrypto.keyFromInviteSeed(seed, channelID: channelID))
        let parsed = try XCTUnwrap(ChannelCrypto.parseInviteCode(code))
        let joinerCrypto = ChannelCrypto(key: parsed.key)

        let plaintext = Data("over the wire".utf8)
        let ciphertext = try creatorCrypto.encrypt(plaintext, epoch: 0)
        let decrypted = try joinerCrypto.decrypt(ciphertext, currentEpoch: 0)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testInviteCodeIsURLSafeAndFixedLength() throws {
        let code = try XCTUnwrap(
            ChannelCrypto.createInviteCode(
                channelID: UUID().uuidString,
                seed: ChannelCrypto.generateInviteSeed()
            )
        )
        // 32 bytes -> 43 base64url chars, no padding, no unsafe chars.
        XCTAssertEqual(code.count, 43)
        XCTAssertFalse(code.contains("+"))
        XCTAssertFalse(code.contains("/"))
        XCTAssertFalse(code.contains("="))
    }

    func testKeyIsBoundToChannelID() {
        let seed = ChannelCrypto.generateInviteSeed()
        let keyA = ChannelCrypto.keyFromInviteSeed(seed, channelID: UUID().uuidString)
        let keyB = ChannelCrypto.keyFromInviteSeed(seed, channelID: UUID().uuidString)
        XCTAssertNotEqual(
            keyA.withUnsafeBytes { Data($0) },
            keyB.withUnsafeBytes { Data($0) }
        )
    }

    func testParseRejectsMalformedCodes() {
        XCTAssertNil(ChannelCrypto.parseInviteCode(""))
        XCTAssertNil(ChannelCrypto.parseInviteCode("SHORTCODE"))
        XCTAssertNil(ChannelCrypto.parseInviteCode("ABCDEF123456"))  // legacy 12-char format
        XCTAssertNil(ChannelCrypto.parseInviteCode(String(repeating: "!", count: 43)))
        XCTAssertNil(ChannelCrypto.parseInviteCode(String(repeating: "A", count: 100)))
    }

    func testParseRejectsTruncatedCode() throws {
        let code = try XCTUnwrap(
            ChannelCrypto.createInviteCode(
                channelID: UUID().uuidString,
                seed: ChannelCrypto.generateInviteSeed()
            )
        )
        XCTAssertNil(ChannelCrypto.parseInviteCode(String(code.dropLast(10))))
    }

    func testCreateRejectsBadInputs() {
        XCTAssertNil(
            ChannelCrypto.createInviteCode(
                channelID: "not-a-uuid",
                seed: ChannelCrypto.generateInviteSeed()
            ),
            "Non-UUID channel IDs cannot be encoded"
        )
        XCTAssertNil(
            ChannelCrypto.createInviteCode(
                channelID: UUID().uuidString,
                seed: Data([0x01, 0x02])
            ),
            "Wrong-length seeds must be rejected"
        )
    }
}

// MARK: - ChannelManager Invite + Keychain Tests

@MainActor
final class ChannelManagerInviteTests: XCTestCase {

    private let storageKey = "com.chirpchirp.savedChannels"
    private let activeChannelKey = "com.chirpchirp.activeChannelID"
    private var savedChannelsBlob: Data?
    private var savedActiveID: String?
    private var createdChannelIDs: [String] = []

    override func setUp() {
        super.setUp()
        // These tests run hosted in the app, so UserDefaults is shared with
        // real app state. Snapshot and clear; restore in tearDown.
        savedChannelsBlob = UserDefaults.standard.data(forKey: storageKey)
        savedActiveID = UserDefaults.standard.string(forKey: activeChannelKey)
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: activeChannelKey)
    }

    override func tearDown() {
        for id in createdChannelIDs {
            ChannelKeyStore.deleteSeed(for: id)
        }
        createdChannelIDs = []
        if let blob = savedChannelsBlob {
            UserDefaults.standard.set(blob, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        if let id = savedActiveID {
            UserDefaults.standard.set(id, forKey: activeChannelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeChannelKey)
        }
        super.tearDown()
    }

    func testCreateLockedChannelProducesWorkingInviteCode() throws {
        let manager = ChannelManager()
        let channel = manager.createChannel(name: "Ops", accessMode: .locked, ownerID: "owner-1")
        createdChannelIDs.append(channel.id)

        let code = try XCTUnwrap(channel.inviteCode, "Locked channel must carry an invite code")
        let parsed = try XCTUnwrap(ChannelCrypto.parseInviteCode(code))
        XCTAssertEqual(parsed.channelID, channel.id)
    }

    func testJoinWithInviteCodeForUnknownChannel() throws {
        // Simulate a code created on another device: the channel does not
        // exist locally in any form.
        let remoteChannelID = UUID().uuidString
        let seed = ChannelCrypto.generateInviteSeed()
        let code = try XCTUnwrap(ChannelCrypto.createInviteCode(channelID: remoteChannelID, seed: seed))
        createdChannelIDs.append(remoteChannelID)

        let manager = ChannelManager()
        XCTAssertTrue(manager.joinWithInviteCode(code))

        let joined = try XCTUnwrap(manager.channel(withID: remoteChannelID))
        XCTAssertEqual(joined.accessMode, .locked)
        XCTAssertEqual(manager.activeChannel?.id, remoteChannelID)

        // Both sides must converge on the same key.
        let joinerCrypto = try XCTUnwrap(manager.getChannelCrypto(for: remoteChannelID))
        let creatorCrypto = ChannelCrypto(key: ChannelCrypto.keyFromInviteSeed(seed, channelID: remoteChannelID))
        let plaintext = Data("cross-device".utf8)
        let decrypted = try joinerCrypto.decrypt(try creatorCrypto.encrypt(plaintext))
        XCTAssertEqual(decrypted, plaintext)
    }

    func testJoinWithInviteCodeRejectsGarbage() {
        let manager = ChannelManager()
        XCTAssertFalse(manager.joinWithInviteCode("DEFINITELYNOTACODE"))
        XCTAssertNil(manager.activeChannel)
    }

    func testChannelKeySurvivesRelaunchViaKeychain() throws {
        let first = ChannelManager()
        let channel = first.createChannel(name: "Persisted", accessMode: .locked, ownerID: "owner-1")
        createdChannelIDs.append(channel.id)
        let code = try XCTUnwrap(channel.inviteCode)

        // A second manager models an app relaunch: fresh crypto cache, state
        // reloaded from UserDefaults, key only available via the Keychain.
        let second = ChannelManager()
        let reloaded = try XCTUnwrap(second.channel(withID: channel.id))
        XCTAssertEqual(reloaded.inviteCode, code, "Invite code must be reconstructable after relaunch")

        let crypto = try XCTUnwrap(second.getChannelCrypto(for: channel.id))
        let parsed = try XCTUnwrap(ChannelCrypto.parseInviteCode(code))
        let plaintext = Data("still here".utf8)
        let decrypted = try crypto.decrypt(try ChannelCrypto(key: parsed.key).encrypt(plaintext))
        XCTAssertEqual(decrypted, plaintext)
    }

    func testKeyMaterialNeverPersistedToUserDefaults() throws {
        let manager = ChannelManager()
        let channel = manager.createChannel(name: "Sealed", accessMode: .locked, ownerID: "owner-1")
        createdChannelIDs.append(channel.id)

        let blob = try XCTUnwrap(UserDefaults.standard.data(forKey: storageKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: blob) as? [[String: Any]])
        for stored in json {
            XCTAssertNil(stored["encryptionKeyData"], "Raw keys must not be written to UserDefaults")
            XCTAssertNil(stored["inviteCode"], "Invite codes carry key material and must not be written to UserDefaults")
        }
    }

    func testLegacyChannelMigratesToKeychain() throws {
        // A pre-Keychain save: raw key in UserDefaults, dead 12-char code.
        let legacyID = UUID().uuidString
        createdChannelIDs.append(legacyID)
        let legacy: [[String: Any]] = [[
            "id": legacyID,
            "name": "Legacy Locked",
            "peers": [] as [Any],
            "createdAt": 0 as Double,
            "accessMode": "locked",
            "theme": ["primaryColor": 0xFFB800, "icon": "shield.fill", "emoji": "⚔️"] as [String: Any],
            "ownerID": "owner-legacy",
            "inviteCode": "ABCDEF123456",
            "encryptionKeyData": Data(repeating: 0xAB, count: 32).base64EncodedString()
        ]]
        let blob = try JSONSerialization.data(withJSONObject: legacy)
        UserDefaults.standard.set(blob, forKey: storageKey)

        let manager = ChannelManager()
        let migrated = try XCTUnwrap(manager.channel(withID: legacyID))

        // Key moved to the Keychain; a fresh, working invite code derived.
        XCTAssertNotNil(ChannelKeyStore.loadSeed(for: legacyID))
        let newCode = try XCTUnwrap(migrated.inviteCode)
        XCTAssertEqual(ChannelCrypto.parseInviteCode(newCode)?.channelID, legacyID)
        XCTAssertNotNil(manager.getChannelCrypto(for: legacyID))

        // And the raw key is scrubbed from UserDefaults.
        let savedBlob = try XCTUnwrap(UserDefaults.standard.data(forKey: storageKey))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: savedBlob) as? [[String: Any]])
        for stored in saved {
            XCTAssertNil(stored["encryptionKeyData"])
            XCTAssertNil(stored["inviteCode"])
        }
    }

    func testDeleteChannelRemovesKeychainSeed() {
        let manager = ChannelManager()
        let channel = manager.createChannel(name: "Ephemeral", accessMode: .locked, ownerID: "owner-1")
        createdChannelIDs.append(channel.id)
        XCTAssertNotNil(ChannelKeyStore.loadSeed(for: channel.id))

        manager.deleteChannel(id: channel.id)
        XCTAssertNil(ChannelKeyStore.loadSeed(for: channel.id))
        XCTAssertNil(manager.getChannelCrypto(for: channel.id))
    }
}

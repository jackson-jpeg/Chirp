import XCTest
@testable import Chirp

// MARK: - MeshRouter Blocking

final class MeshRouterBlockingTests: XCTestCase {

    private func makePacket(origin: UUID, sequence: UInt32 = 1) -> MeshPacket {
        MeshPacket(
            type: .control,
            ttl: 4,
            originID: origin,
            packetID: UUID(),
            sequenceNumber: sequence,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "test-channel",
            payload: Data("payload".utf8)
        )
    }

    func testBlockedOriginPacketsAreDropped() async {
        let router = MeshRouter(localPeerID: UUID())
        let blocked = UUID()
        await router.setBlockedOrigins([blocked.uuidString])

        let accepted = await router.handleIncoming(
            packet: makePacket(origin: blocked),
            fromPeer: "peer-1"
        )

        XCTAssertFalse(accepted, "Packets from a blocked origin must be dropped")
        let stats = await router.stats
        XCTAssertEqual(stats.delivered, 0, "Blocked packets must not be delivered locally")
        XCTAssertEqual(stats.relayed, 0, "Blocked packets must not be relayed")
        let blockedCount = await router.packetsBlocked
        XCTAssertEqual(blockedCount, 1)
    }

    func testBlockedOriginNeverReachesCallbacks() async {
        let router = MeshRouter(localPeerID: UUID())
        let blocked = UUID()
        await router.setBlockedOrigins([blocked.uuidString])

        let delivered = Flag()
        let forwarded = Flag()
        await router.setCallbacks(
            onLocalDelivery: { _ in delivered.set() },
            onForward: { _, _ in forwarded.set() }
        )

        await router.handleIncoming(packet: makePacket(origin: blocked), fromPeer: "peer-1")

        XCTAssertFalse(delivered.isSet)
        XCTAssertFalse(forwarded.isSet)
    }

    func testOtherOriginsUnaffectedByBlock() async {
        let router = MeshRouter(localPeerID: UUID())
        await router.setBlockedOrigins([UUID().uuidString])

        let accepted = await router.handleIncoming(
            packet: makePacket(origin: UUID()),
            fromPeer: "peer-1"
        )

        XCTAssertTrue(accepted, "Unrelated origins must still be processed")
    }

    func testUnblockRestoresDelivery() async {
        let router = MeshRouter(localPeerID: UUID())
        let origin = UUID()
        await router.setBlockedOrigins([origin.uuidString])

        let droppedResult = await router.handleIncoming(
            packet: makePacket(origin: origin, sequence: 1),
            fromPeer: "peer-1"
        )
        XCTAssertFalse(droppedResult)

        await router.setBlockedOrigins([])
        let restoredResult = await router.handleIncoming(
            packet: makePacket(origin: origin, sequence: 2),
            fromPeer: "peer-1"
        )
        XCTAssertTrue(restoredResult, "Unblocking must restore packet processing")
    }

    func testNonUUIDBlockedIDsAreIgnored() async {
        let router = MeshRouter(localPeerID: UUID())
        await router.setBlockedOrigins(["not-a-uuid", ""])

        let accepted = await router.handleIncoming(
            packet: makePacket(origin: UUID()),
            fromPeer: "peer-1"
        )
        XCTAssertTrue(accepted, "Garbage block entries must not affect routing")
    }
}

/// Minimal thread-safe flag for asserting a @Sendable callback never fired.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}

// MARK: - BlockList Store

@MainActor
final class BlockListTests: XCTestCase {

    private static let suiteName = "com.chirpchirp.tests.blocklist"

    /// A defaults suite wiped clean, so every test starts from empty state.
    private func makeFreshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    // Routing UUIDs, not "peer-1". These fixtures used to be arbitrary
    // strings, which quietly made the suite green while the app was broken:
    // `MeshRouter.setBlockedOrigins` keeps only values that parse as a UUID,
    // so a block recorded under a callsign was discarded and the peer kept
    // talking. `BlockList` now refuses such an ID outright, and
    // `testBlockRefusesAnIdentifierEnforcementWouldDiscard` covers that.
    private static let peerOne = "11111111-1111-4111-8111-111111111111"
    private static let peerTwo = "22222222-2222-4222-8222-222222222222"

    func testBlockUnblockAndPersistence() {
        let defaults = makeFreshDefaults()
        let list = BlockList(defaults: defaults)
        XCTAssertTrue(list.entries.isEmpty)

        list.block(id: Self.peerOne, name: "Falcon")
        XCTAssertTrue(list.isBlocked(Self.peerOne))
        XCTAssertEqual(list.blockedIDs, [Self.peerOne])

        // Blocking the same peer twice must not duplicate.
        list.block(id: Self.peerOne, name: "Falcon")
        XCTAssertEqual(list.entries.count, 1)

        // A fresh instance models an app relaunch.
        let reloaded = BlockList(defaults: defaults)
        XCTAssertTrue(reloaded.isBlocked(Self.peerOne))
        XCTAssertEqual(reloaded.entries.first?.name, "Falcon")

        reloaded.unblock(id: Self.peerOne)
        XCTAssertFalse(reloaded.isBlocked(Self.peerOne))

        let reloadedAgain = BlockList(defaults: defaults)
        XCTAssertTrue(reloadedAgain.entries.isEmpty, "Unblock must persist")
    }

    func testOnChangeFiresWithUpdatedIDs() {
        let defaults = makeFreshDefaults()
        let list = BlockList(defaults: defaults)
        var observed: [Set<String>] = []
        list.onChange = { observed.append($0) }

        list.block(id: Self.peerOne, name: "Falcon")
        list.block(id: Self.peerTwo, name: "Raven")
        list.unblock(id: Self.peerOne)

        XCTAssertEqual(observed, [[Self.peerOne], [Self.peerOne, Self.peerTwo], [Self.peerTwo]])
    }

    /// The bug this whole identity change exists to kill: a block recorded
    /// against something the enforcement layer will throw away.
    func testBlockRefusesAnIdentifierEnforcementWouldDiscard() {
        let list = BlockList(defaults: makeFreshDefaults())

        // A callsign, which is what `ChirpPeer.id` used to hand to block().
        list.block(id: "Ridge-7", name: "Ridge-7")
        // An identity fingerprint, which is stable but is not what the
        // router filters on.
        list.block(id: "a1b2c3d4e5f60718", name: "Ridge-7")

        XCTAssertTrue(
            list.entries.isEmpty,
            "a block was recorded under an ID MeshRouter.setBlockedOrigins discards, "
                + "which shows the user Blocked while the traffic keeps arriving"
        )
    }

    /// Apple's requirement 1: renaming must not shake off a block.
    func testBlockFollowsTheIdentityAcrossANewRoutingID() {
        let defaults = makeFreshDefaults()
        let list = BlockList(defaults: defaults)
        let fingerprint = "a1b2c3d4e5f60718"

        list.block(id: Self.peerOne, name: "Ridge-7", fingerprint: fingerprint)
        XCTAssertTrue(list.isBlocked(fingerprint: fingerprint))
        XCTAssertEqual(list.blockedFingerprints, [fingerprint])

        // Same person, new install: new routing UUID, new display name, same
        // identity keypair and therefore the same fingerprint.
        list.rekeyBlock(newRoutingID: Self.peerTwo, fingerprint: fingerprint, name: "Nova-12")
        XCTAssertTrue(list.isBlocked(Self.peerTwo), "the rename evaded the block")
        XCTAssertTrue(list.isBlocked(Self.peerOne), "the original block was lost")

        // The block survives a relaunch under both routing IDs.
        let reloaded = BlockList(defaults: defaults)
        XCTAssertTrue(reloaded.isBlocked(Self.peerTwo))

        // Unblocking lifts the whole identity, not one of its addresses.
        reloaded.unblock(id: Self.peerTwo)
        XCTAssertFalse(reloaded.isBlocked(Self.peerOne),
                       "unblocking left another routing ID of the same person blocked")
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    /// A peer blocked before we ever verified their fingerprint gets it
    /// attached once we do, so the block can follow them afterwards.
    func testFingerprintIsBackfilledOnARepeatBlock() {
        let list = BlockList(defaults: makeFreshDefaults())
        list.block(id: Self.peerOne, name: "Ridge-7")
        XCTAssertNil(list.entries.first?.fingerprint)

        list.block(id: Self.peerOne, name: "Ridge-7", fingerprint: "a1b2c3d4e5f60718")
        XCTAssertEqual(list.entries.count, 1, "backfilling must not duplicate the entry")
        XCTAssertEqual(list.entries.first?.fingerprint, "a1b2c3d4e5f60718")
    }
}

// MARK: - TextMessageService Blocking

@MainActor
final class TextMessageBlockingTests: XCTestCase {

    private var blockedIDs: Set<String> = []

    private func makeService() -> TextMessageService {
        let service = TextMessageService()
        service.blockedPeerIDsProvider = { [weak self] in self?.blockedIDs ?? [] }
        return service
    }

    private func makeMessagePayload(
        senderID: String,
        senderName: String = "Falcon",
        channelID: String = "chan-1",
        text: String = "hello"
    ) throws -> Data {
        let message = MeshTextMessage(
            id: UUID(),
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            text: text,
            timestamp: Date()
        )
        return try message.wirePayload()
    }

    func testInboundMessageFromBlockedSenderIsDropped() throws {
        blockedIDs = ["blocked-sender"]
        let service = makeService()

        let payload = try makeMessagePayload(senderID: "blocked-sender")
        service.handlePacket(payload, channelID: "chan-1")

        XCTAssertTrue(service.messages(for: "chan-1").isEmpty)
        XCTAssertEqual(service.unreadCount(for: "chan-1"), 0)
    }

    func testInboundMessageFromUnblockedSenderIsStored() throws {
        let service = makeService()

        let payload = try makeMessagePayload(senderID: "friendly-sender")
        service.handlePacket(payload, channelID: "chan-1")

        XCTAssertEqual(service.messages(for: "chan-1").count, 1)
    }

    func testBlockingHidesExistingHistory() throws {
        let service = makeService()

        service.handlePacket(try makeMessagePayload(senderID: "sender-a", text: "one"), channelID: "chan-1")
        service.handlePacket(try makeMessagePayload(senderID: "sender-b", text: "two"), channelID: "chan-1")
        XCTAssertEqual(service.messages(for: "chan-1").count, 2)

        blockedIDs = ["sender-a"]
        let visible = service.messages(for: "chan-1")
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.senderID, "sender-b")
        XCTAssertEqual(service.lastMessageText(for: "chan-1"), "two")

        // Unblocking restores the hidden history.
        blockedIDs = []
        XCTAssertEqual(service.messages(for: "chan-1").count, 2)
    }

    func testReactionFromBlockedSenderIsIgnored() throws {
        let service = makeService()

        // Store a message from a friendly sender first.
        let message = MeshTextMessage(
            id: UUID(),
            senderID: "friendly-sender",
            senderName: "Raven",
            channelID: "chan-1",
            text: "react to me",
            timestamp: Date()
        )
        service.handlePacket(try message.wirePayload(), channelID: "chan-1")

        blockedIDs = ["blocked-sender"]

        // Reaction wire format: RXN! + messageID + 0x00 + emoji + 0x00 + senderID + 0x00 + senderName
        var payload = Data(MeshTextMessage.reactionMagicPrefix)
        payload.append(Data(message.id.uuidString.utf8))
        payload.append(0x00)
        payload.append(Data("🔥".utf8))
        payload.append(0x00)
        payload.append(Data("blocked-sender".utf8))
        payload.append(0x00)
        payload.append(Data("Falcon".utf8))

        XCTAssertTrue(service.handleReaction(payload, channelID: "chan-1"))
        XCTAssertEqual(service.messages(for: "chan-1").first?.reactions.count, 0)
    }
}

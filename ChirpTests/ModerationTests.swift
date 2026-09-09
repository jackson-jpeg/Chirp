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

    func testBlockUnblockAndPersistence() {
        let defaults = makeFreshDefaults()
        let list = BlockList(defaults: defaults)
        XCTAssertTrue(list.entries.isEmpty)

        list.block(id: "peer-1", name: "Falcon")
        XCTAssertTrue(list.isBlocked("peer-1"))
        XCTAssertEqual(list.blockedIDs, ["peer-1"])

        // Blocking the same peer twice must not duplicate.
        list.block(id: "peer-1", name: "Falcon")
        XCTAssertEqual(list.entries.count, 1)

        // A fresh instance models an app relaunch.
        let reloaded = BlockList(defaults: defaults)
        XCTAssertTrue(reloaded.isBlocked("peer-1"))
        XCTAssertEqual(reloaded.entries.first?.name, "Falcon")

        reloaded.unblock(id: "peer-1")
        XCTAssertFalse(reloaded.isBlocked("peer-1"))

        let reloadedAgain = BlockList(defaults: defaults)
        XCTAssertTrue(reloadedAgain.entries.isEmpty, "Unblock must persist")
    }

    func testOnChangeFiresWithUpdatedIDs() {
        let defaults = makeFreshDefaults()
        let list = BlockList(defaults: defaults)
        var observed: [Set<String>] = []
        list.onChange = { observed.append($0) }

        list.block(id: "peer-1", name: "Falcon")
        list.block(id: "peer-2", name: "Raven")
        list.unblock(id: "peer-1")

        XCTAssertEqual(observed, [["peer-1"], ["peer-1", "peer-2"], ["peer-2"]])
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

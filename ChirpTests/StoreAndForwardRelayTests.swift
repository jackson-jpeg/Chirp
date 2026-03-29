import XCTest
@testable import Chirp

@MainActor
final class StoreAndForwardRelayTests: XCTestCase {

    private var relay: StoreAndForwardRelay!

    override func setUp() async throws {
        relay = StoreAndForwardRelay()
        // Clear any state loaded from disk so each test starts clean
        clearRelay()
    }

    // MARK: - Helpers

    private func makePendingMessage(
        recipientPeerID: String = "peer-ABC",
        channelID: String = "channel-1",
        senderName: String = "Alice",
        timestamp: Date = Date()
    ) -> StoreAndForwardRelay.PendingMessage {
        StoreAndForwardRelay.PendingMessage(
            id: UUID(),
            recipientPeerID: recipientPeerID,
            payload: Data([0xCA, 0xFE]),
            channelID: channelID,
            senderName: senderName,
            timestamp: timestamp
        )
    }

    /// Drains all pending messages so the relay starts empty.
    private func clearRelay() {
        let peerIDs = relay.pendingMessages.keys.map { $0 }
        for peerID in peerIDs {
            _ = relay.checkPendingForPeer(peerID)
        }
    }

    // MARK: - Store and totalPending

    func testStoreMessageAppearsInPending() {
        let msg = makePendingMessage()
        relay.store(message: msg)

        XCTAssertEqual(relay.totalPending, 1)
        XCTAssertEqual(relay.pendingMessages["peer-ABC"]?.count, 1)
        XCTAssertEqual(relay.pendingMessages["peer-ABC"]?.first?.id, msg.id)
    }

    // MARK: - checkPendingForPeer returns and clears

    func testCheckPendingReturnsSoredMessagesAndClearsQueue() {
        let msg1 = makePendingMessage()
        let msg2 = makePendingMessage()
        relay.store(message: msg1)
        relay.store(message: msg2)

        let delivered = relay.checkPendingForPeer("peer-ABC")

        XCTAssertEqual(delivered.count, 2)
        XCTAssertTrue(delivered.contains(where: { $0.id == msg1.id }))
        XCTAssertTrue(delivered.contains(where: { $0.id == msg2.id }))
        // Queue should now be empty for that peer
        XCTAssertEqual(relay.totalPending, 0)
        XCTAssertNil(relay.pendingMessages["peer-ABC"])
    }

    func testCheckPendingForUnknownPeerReturnsEmpty() {
        let delivered = relay.checkPendingForPeer("unknown-peer")
        XCTAssertTrue(delivered.isEmpty)
    }

    // MARK: - Expired messages filtered out

    func testExpiredMessagesFilteredOnCheck() {
        let oldTimestamp = Date().addingTimeInterval(-25 * 60 * 60) // 25 hours ago
        let expired = makePendingMessage(timestamp: oldTimestamp)
        let fresh = makePendingMessage()

        relay.store(message: expired)
        relay.store(message: fresh)

        XCTAssertEqual(relay.totalPending, 2, "Both stored before check")

        let delivered = relay.checkPendingForPeer("peer-ABC")

        XCTAssertEqual(delivered.count, 1, "Only the fresh message should be delivered")
        XCTAssertEqual(delivered.first?.id, fresh.id)
    }

    // MARK: - pruneExpired

    func testPruneExpiredRemovesOldEntries() {
        let oldTimestamp = Date().addingTimeInterval(-25 * 60 * 60)
        let expired1 = makePendingMessage(recipientPeerID: "peer-X", timestamp: oldTimestamp)
        let expired2 = makePendingMessage(recipientPeerID: "peer-Y", timestamp: oldTimestamp)
        let fresh = makePendingMessage(recipientPeerID: "peer-Y")

        relay.store(message: expired1)
        relay.store(message: expired2)
        relay.store(message: fresh)

        XCTAssertEqual(relay.totalPending, 3)

        relay.pruneExpired()

        XCTAssertEqual(relay.totalPending, 1, "Only the fresh message should survive")
        XCTAssertNil(relay.pendingMessages["peer-X"], "Peer X queue fully expired, should be removed")
        XCTAssertEqual(relay.pendingMessages["peer-Y"]?.count, 1)
        XCTAssertEqual(relay.pendingMessages["peer-Y"]?.first?.id, fresh.id)
    }

    func testPruneExpiredNoOpWhenAllFresh() {
        let msg = makePendingMessage()
        relay.store(message: msg)

        relay.pruneExpired()

        XCTAssertEqual(relay.totalPending, 1)
    }

    // MARK: - totalPending accuracy after multiple stores

    func testTotalPendingAccurateAcrossMultiplePeers() {
        let msgA1 = makePendingMessage(recipientPeerID: "peer-A")
        let msgA2 = makePendingMessage(recipientPeerID: "peer-A")
        let msgB1 = makePendingMessage(recipientPeerID: "peer-B")
        let msgC1 = makePendingMessage(recipientPeerID: "peer-C")
        let msgC2 = makePendingMessage(recipientPeerID: "peer-C")
        let msgC3 = makePendingMessage(recipientPeerID: "peer-C")

        relay.store(message: msgA1)
        relay.store(message: msgA2)
        relay.store(message: msgB1)
        relay.store(message: msgC1)
        relay.store(message: msgC2)
        relay.store(message: msgC3)

        XCTAssertEqual(relay.totalPending, 6)
        XCTAssertEqual(relay.pendingMessages.keys.count, 3)

        // Deliver one peer's messages, recheck
        _ = relay.checkPendingForPeer("peer-B")
        XCTAssertEqual(relay.totalPending, 5)

        _ = relay.checkPendingForPeer("peer-A")
        XCTAssertEqual(relay.totalPending, 3)

        _ = relay.checkPendingForPeer("peer-C")
        XCTAssertEqual(relay.totalPending, 0)
    }
}

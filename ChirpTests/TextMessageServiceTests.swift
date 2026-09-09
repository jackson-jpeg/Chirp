import XCTest
@testable import Chirp

@MainActor
final class TextMessageServiceTests: XCTestCase {

    private var service: TextMessageService!
    private var sentPayloads: [(Data, String)]!

    // Same defect as FloorControlTests had: a synchronous `setUp()` override
    // stays nonisolated even inside a @MainActor class, because XCTestCase
    // declares it nonisolated and an override cannot change that. This was
    // constructing and configuring a @MainActor TextMessageService off the main
    // actor — a state the app never reaches. The async overrides do pick up the
    // class's isolation.
    //
    // Unlike FloorSession.sendToAllPeers, `onSendPacket` is not @Sendable:
    // it is a plain closure on a @MainActor type, so it is only ever invoked on
    // the main actor and main-actor recording state is correct here. No lock
    // is needed; the isolation of setUp was the whole problem.
    override func setUp() async throws {
        try await super.setUp()
        sentPayloads = []
        service = TextMessageService()
        service.onSendPacket = { [weak self] payload, channelID in
            self?.sentPayloads.append((payload, channelID))
        }
    }

    override func tearDown() async throws {
        service = nil
        sentPayloads = nil
        try await super.tearDown()
    }

    // MARK: - Send creates message with correct fields and calls onSendPacket

    func testSendCreatesMessageWithCorrectFieldsAndCallsOnSendPacket() {
        service.send(
            text: "Hello mesh",
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice"
        )

        // onSendPacket should have been called exactly once
        XCTAssertEqual(sentPayloads.count, 1)
        XCTAssertEqual(sentPayloads.first?.1, "ch-1")

        // The message should be stored locally
        let messages = service.messages(for: "ch-1")
        XCTAssertEqual(messages.count, 1)

        let msg = messages.first!
        XCTAssertEqual(msg.text, "Hello mesh")
        XCTAssertEqual(msg.channelID, "ch-1")
        XCTAssertEqual(msg.senderID, "peer-A")
        XCTAssertEqual(msg.senderName, "Alice")
        XCTAssertNil(msg.replyToID)
        XCTAssertNil(msg.attachmentType)
    }

    // MARK: - Text clamped to 1000 chars

    func testSendClampsTextTo1000Characters() {
        let longText = String(repeating: "A", count: 2000)

        service.send(
            text: longText,
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice"
        )

        let stored = service.messages(for: "ch-1").first!
        XCTAssertEqual(stored.text.count, MeshTextMessage.maxTextLength)
        XCTAssertEqual(stored.text, String(repeating: "A", count: 1000))
    }

    // MARK: - handlePacket decodes TXT! prefix payloads

    func testHandlePacketDecodesTextPrefixPayload() throws {
        let message = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-1",
            text: "Hi there",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        let payload = try message.wirePayload()

        service.handlePacket(payload, channelID: "ch-1")

        let messages = service.messages(for: "ch-1")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.text, "Hi there")
        XCTAssertEqual(messages.first?.senderID, "peer-B")
        XCTAssertEqual(messages.first?.id, message.id)
    }

    // MARK: - Deduplication: same message ID arriving twice only stored once

    func testDeduplicationPreventsDoubleStorage() throws {
        let message = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-1",
            text: "Dup test",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        let payload = try message.wirePayload()

        service.handlePacket(payload, channelID: "ch-1")
        service.handlePacket(payload, channelID: "ch-1")

        XCTAssertEqual(service.messages(for: "ch-1").count, 1)
    }

    // MARK: - Non-text payloads silently ignored

    func testNonTextPayloadSilentlyIgnored() {
        // Random bytes without TXT! prefix
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        service.handlePacket(garbage, channelID: "ch-1")

        XCTAssertTrue(service.messages(for: "ch-1").isEmpty)
    }

    func testPayloadWithWrongPrefixIgnored() {
        // Starts with "MSG!" instead of "TXT!"
        var data = Data([0x4D, 0x53, 0x47, 0x21])
        data.append(Data("{}".utf8))
        service.handlePacket(data, channelID: "ch-1")

        XCTAssertTrue(service.messages(for: "ch-1").isEmpty)
    }

    // MARK: - wirePayload round-trip: encode -> from(payload:) -> equal

    func testWirePayloadRoundTrip() throws {
        let original = MeshTextMessage(
            id: UUID(),
            senderID: "peer-C",
            senderName: "Charlie",
            channelID: "ch-2",
            text: "Round trip",
            timestamp: Date(),
            replyToID: UUID(),
            attachmentType: .location
        )

        let payload = try original.wirePayload()
        let decoded = MeshTextMessage.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, original.id)
        XCTAssertEqual(decoded?.senderID, original.senderID)
        XCTAssertEqual(decoded?.senderName, original.senderName)
        XCTAssertEqual(decoded?.channelID, original.channelID)
        XCTAssertEqual(decoded?.text, original.text)
        XCTAssertEqual(decoded?.replyToID, original.replyToID)
        XCTAssertEqual(decoded?.attachmentType, original.attachmentType)
    }

    func testWirePayloadRoundTripWithNilOptionals() throws {
        let original = MeshTextMessage(
            id: UUID(),
            senderID: "peer-D",
            senderName: "Dana",
            channelID: "ch-3",
            text: "No optionals",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )

        let payload = try original.wirePayload()
        let decoded = MeshTextMessage.from(payload: payload)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.id, original.id)
        XCTAssertNil(decoded?.replyToID)
        XCTAssertNil(decoded?.attachmentType)
    }

    // MARK: - Thread support: replyToID preserved through encode/decode

    func testReplyToIDPreservedThroughEncodeDecode() throws {
        let parentID = UUID()
        let reply = MeshTextMessage(
            id: UUID(),
            senderID: "peer-E",
            senderName: "Eve",
            channelID: "ch-1",
            text: "Thread reply",
            timestamp: Date(),
            replyToID: parentID,
            attachmentType: nil
        )

        let payload = try reply.wirePayload()
        service.handlePacket(payload, channelID: "ch-1")

        let stored = service.messages(for: "ch-1").first
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.replyToID, parentID)
    }

    func testSendWithReplyToIDStoresCorrectly() {
        let parentID = UUID()

        service.send(
            text: "Replying",
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice",
            replyToID: parentID
        )

        let stored = service.messages(for: "ch-1").first
        XCTAssertEqual(stored?.replyToID, parentID)
    }

    // MARK: - Unread counts increment on receive, reset on markAsRead

    func testUnreadCountIncrementsOnReceive() throws {
        let msg1 = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-1",
            text: "First",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        let msg2 = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-1",
            text: "Second",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )

        XCTAssertEqual(service.unreadCount(for: "ch-1"), 0)

        service.handlePacket(try msg1.wirePayload(), channelID: "ch-1")
        XCTAssertEqual(service.unreadCount(for: "ch-1"), 1)

        service.handlePacket(try msg2.wirePayload(), channelID: "ch-1")
        XCTAssertEqual(service.unreadCount(for: "ch-1"), 2)
    }

    func testMarkAsReadResetsUnreadCount() throws {
        let msg = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-1",
            text: "Unread",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        service.handlePacket(try msg.wirePayload(), channelID: "ch-1")
        XCTAssertEqual(service.unreadCount(for: "ch-1"), 1)

        service.markAsRead(channelID: "ch-1")
        XCTAssertEqual(service.unreadCount(for: "ch-1"), 0)
    }

    func testSentMessagesDoNotIncrementUnreadCount() {
        service.send(
            text: "My own message",
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice"
        )

        XCTAssertEqual(service.unreadCount(for: "ch-1"), 0)
    }

    // MARK: - Per-channel message cap enforced -- oldest trimmed

    /// The cap under test. Read from the app's own constant rather than
    /// restated here: these tests previously hard-coded 500 while the service
    /// enforced 200, and nothing detected the drift because the test target had
    /// never been built. Neither number was "right" — holding it twice was the bug.
    private var cap: Int { Constants.TextMessages.maxPerChannel }

    func testPerChannelMessageCapEnforced() throws {
        // Fill the channel exactly to the cap via handlePacket
        for i in 0..<cap {
            let msg = MeshTextMessage(
                id: UUID(),
                senderID: "peer-B",
                senderName: "Bob",
                channelID: "ch-cap",
                text: "Message \(i)",
                timestamp: Date(),
                replyToID: nil,
                attachmentType: nil
            )
            service.handlePacket(try msg.wirePayload(), channelID: "ch-cap")
        }
        XCTAssertEqual(service.messages(for: "ch-cap").count, cap)

        // Add one more -- should trim the oldest
        let overflow = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-cap",
            text: "Overflow",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        service.handlePacket(try overflow.wirePayload(), channelID: "ch-cap")

        let messages = service.messages(for: "ch-cap")
        XCTAssertEqual(messages.count, cap)
        // Oldest message ("Message 0") should have been trimmed
        XCTAssertEqual(messages.first?.text, "Message 1")
        // Newest message should be the overflow
        XCTAssertEqual(messages.last?.text, "Overflow")
    }

    func testCapAppliesPerChannelIndependently() throws {
        // Put one message in ch-other
        let otherMsg = MeshTextMessage(
            id: UUID(),
            senderID: "peer-B",
            senderName: "Bob",
            channelID: "ch-other",
            text: "Other channel",
            timestamp: Date(),
            replyToID: nil,
            attachmentType: nil
        )
        service.handlePacket(try otherMsg.wirePayload(), channelID: "ch-other")

        // Fill ch-cap one past the limit
        for i in 0..<(cap + 1) {
            let msg = MeshTextMessage(
                id: UUID(),
                senderID: "peer-B",
                senderName: "Bob",
                channelID: "ch-cap",
                text: "Msg \(i)",
                timestamp: Date(),
                replyToID: nil,
                attachmentType: nil
            )
            service.handlePacket(try msg.wirePayload(), channelID: "ch-cap")
        }

        // ch-cap trimmed to the cap, ch-other untouched
        XCTAssertEqual(service.messages(for: "ch-cap").count, cap)
        XCTAssertEqual(service.messages(for: "ch-other").count, 1)
    }

    // MARK: - Delivery ACK updates message status

    func testDeliveryACKUpdatesMessageStatus() {
        // Send a message so it appears in the channel history with .sent status.
        service.send(
            text: "Awaiting ACK",
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice"
        )

        let messages = service.messages(for: "ch-1")
        XCTAssertEqual(messages.count, 1)
        let messageID = messages.first!.id
        XCTAssertEqual(messages.first!.deliveryStatus, .sent)

        // Build an ACK payload: "ACK!" prefix + UUID string
        var ackPayload = Data(MeshTextMessage.ackMagicPrefix)
        ackPayload.append(Data(messageID.uuidString.utf8))

        // Simulate receiving the ACK through handlePacket
        service.handlePacket(ackPayload, channelID: "ch-1")

        // The message's deliveryStatus should now be .delivered
        let updated = service.messages(for: "ch-1")
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated.first!.deliveryStatus, .delivered)
    }

    func testACKForUnknownMessageIsIgnored() {
        // Send a real message first so there is something in the channel
        service.send(
            text: "Real message",
            channelID: "ch-1",
            senderID: "peer-A",
            senderName: "Alice"
        )

        let originalMessages = service.messages(for: "ch-1")
        XCTAssertEqual(originalMessages.count, 1)
        let originalStatus = originalMessages.first!.deliveryStatus

        // Build an ACK for a random UUID that does not match any sent message
        let unknownID = UUID()
        var ackPayload = Data(MeshTextMessage.ackMagicPrefix)
        ackPayload.append(Data(unknownID.uuidString.utf8))

        // Should not crash and should not change any message status
        service.handlePacket(ackPayload, channelID: "ch-1")

        let afterMessages = service.messages(for: "ch-1")
        XCTAssertEqual(afterMessages.count, 1)
        XCTAssertEqual(afterMessages.first!.deliveryStatus, originalStatus)
    }
}

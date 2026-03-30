import XCTest
@testable import Chirp

final class DualTransportTests: XCTestCase {

    private var router: MeshRouter!
    private let localPeerID = UUID()
    private let remotePeerID = UUID()
    // Reference-type wrappers for Sendable closure capture
    private final class PacketBox: @unchecked Sendable {
        var delivered: [MeshPacket] = []
        var forwarded: [(MeshPacket, String)] = []
    }
    private var box: PacketBox!

    override func setUp() {
        super.setUp()
        box = PacketBox()
        router = MeshRouter(localPeerID: localPeerID)
    }

    override func tearDown() {
        router = nil
        box = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func installCallbacks() async {
        let b = box!
        await router.setCallbacks(
            onLocalDelivery: { packet in
                b.delivered.append(packet)
            },
            onForward: { packet, fromPeer in
                b.forwarded.append((packet, fromPeer))
            }
        )
    }

    private func makePacket(
        ttl: UInt8 = 4,
        originID: UUID? = nil,
        packetID: UUID = UUID()
    ) -> MeshPacket {
        MeshPacket(
            type: .audio,
            ttl: ttl,
            originID: originID ?? remotePeerID,
            packetID: packetID,
            sequenceNumber: 1,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: Data([0x00, 0x01])
        )
    }

    // MARK: - Tests

    func testPacketDeliveredLocally() async {
        await installCallbacks()
        let packet = makePacket()

        let accepted = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertTrue(accepted)
        XCTAssertEqual(box.delivered.count, 1)
        XCTAssertEqual(box.delivered.first?.packetID, packet.packetID)
        let delivered = await router.packetsDelivered
        XCTAssertEqual(delivered, 1)
    }

    func testDuplicatePacketIsDeduplicated() async {
        await installCallbacks()
        let packet = makePacket()

        let first = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")
        let second = await router.handleIncoming(packet: packet, fromPeer: "peer-wifi")

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(box.delivered.count, 1, "Duplicate packet should not be delivered a second time")
        let deduped = await router.packetsDeduplicated
        XCTAssertEqual(deduped, 1)
    }

    func testForwardedPacketHasTTLDecremented() async {
        await installCallbacks()
        let packet = makePacket(ttl: 4)

        _ = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertEqual(box.forwarded.count, 1)
        let forwarded = box.forwarded.first?.0
        XCTAssertEqual(forwarded?.ttl, 3, "Forwarded packet should have TTL decremented by 1")
        XCTAssertEqual(forwarded?.packetID, packet.packetID, "Forwarded packet should retain the same packetID")
    }

    func testTTL1PacketDeliveredButNotForwarded() async {
        await installCallbacks()
        let packet = makePacket(ttl: 1)

        let accepted = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertTrue(accepted)
        XCTAssertEqual(box.delivered.count, 1, "TTL-1 packet should still be delivered locally")
        XCTAssertTrue(box.forwarded.isEmpty, "TTL-1 packet should NOT be forwarded")
        let relayed = await router.packetsRelayed
        XCTAssertEqual(relayed, 0)
    }

    func testPacketFromOwnOriginIDIsDropped() async {
        await installCallbacks()
        let packet = makePacket(originID: localPeerID)

        let accepted = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertFalse(accepted)
        XCTAssertTrue(box.delivered.isEmpty, "Own packets should be dropped, not delivered")
        XCTAssertTrue(box.forwarded.isEmpty, "Own packets should be dropped, not forwarded")
    }
}

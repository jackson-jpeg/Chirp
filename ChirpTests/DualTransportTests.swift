import XCTest
@testable import Chirp

final class DualTransportTests: XCTestCase {

    private var router: MeshRouter!
    private let localPeerID = UUID()
    private let remotePeerID = UUID()
    private var deliveredPackets: [MeshPacket]!
    private var forwardedPackets: [(MeshPacket, String)]!

    override func setUp() {
        super.setUp()
        deliveredPackets = []
        forwardedPackets = []
        router = MeshRouter(localPeerID: localPeerID)
    }

    override func tearDown() {
        router = nil
        deliveredPackets = nil
        forwardedPackets = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func installCallbacks() async {
        await router.setCallbacks(
            onLocalDelivery: { [weak self] packet in
                self?.deliveredPackets.append(packet)
            },
            onForward: { [weak self] packet, fromPeer in
                self?.forwardedPackets.append((packet, fromPeer))
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
        XCTAssertEqual(deliveredPackets.count, 1)
        XCTAssertEqual(deliveredPackets.first?.packetID, packet.packetID)
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
        XCTAssertEqual(deliveredPackets.count, 1, "Duplicate packet should not be delivered a second time")
        let deduped = await router.packetsDeduplicated
        XCTAssertEqual(deduped, 1)
    }

    func testForwardedPacketHasTTLDecremented() async {
        await installCallbacks()
        let packet = makePacket(ttl: 4)

        _ = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertEqual(forwardedPackets.count, 1)
        let forwarded = forwardedPackets.first?.0
        XCTAssertEqual(forwarded?.ttl, 3, "Forwarded packet should have TTL decremented by 1")
        XCTAssertEqual(forwarded?.packetID, packet.packetID, "Forwarded packet should retain the same packetID")
    }

    func testTTL1PacketDeliveredButNotForwarded() async {
        await installCallbacks()
        let packet = makePacket(ttl: 1)

        let accepted = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertTrue(accepted)
        XCTAssertEqual(deliveredPackets.count, 1, "TTL-1 packet should still be delivered locally")
        XCTAssertTrue(forwardedPackets.isEmpty, "TTL-1 packet should NOT be forwarded")
        let relayed = await router.packetsRelayed
        XCTAssertEqual(relayed, 0)
    }

    func testPacketFromOwnOriginIDIsDropped() async {
        await installCallbacks()
        let packet = makePacket(originID: localPeerID)

        let accepted = await router.handleIncoming(packet: packet, fromPeer: "peer-ble")

        XCTAssertFalse(accepted)
        XCTAssertTrue(deliveredPackets.isEmpty, "Own packets should be dropped, not delivered")
        XCTAssertTrue(forwardedPackets.isEmpty, "Own packets should be dropped, not forwarded")
    }
}

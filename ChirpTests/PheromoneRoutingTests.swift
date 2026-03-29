import XCTest
@testable import Chirp

final class PheromoneRoutingTests: XCTestCase {

    private var intel: MeshIntelligence!

    override func setUp() {
        super.setUp()
        intel = MeshIntelligence()
    }

    override func tearDown() {
        intel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePacket(
        type: MeshPacket.PacketType = .control,
        ttl: UInt8 = MeshPacket.defaultTTL,
        channelID: String = "test-channel",
        payload: Data = Data()
    ) -> MeshPacket {
        MeshPacket(
            type: type,
            ttl: ttl,
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: payload
        )
    }

    // MARK: - Deposit and route

    func testDepositAndRoute() async {
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")

        let routes = await intel.pheromoneRoute(for: "channel:test")
        XCTAssertNotNil(routes)
        XCTAssertEqual(routes?.count, 1)
        XCTAssertEqual(routes?.first?.neighbor, "peer1")
        XCTAssertEqual(routes?.first?.score, 1.0, accuracy: 0.001)
    }

    // MARK: - Multiple deposits accumulate

    func testMultipleDepositsAccumulate() async {
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")

        let routes = await intel.pheromoneRoute(for: "channel:test")
        XCTAssertNotNil(routes)
        XCTAssertEqual(routes?.first?.score, 3.0, accuracy: 0.001)
    }

    // MARK: - Multiple neighbors ranked

    func testMultipleNeighborsRankedByScore() async {
        // Deposit 2.0 for peer1
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")

        // Deposit 1.0 for peer2
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer2")

        let routes = await intel.pheromoneRoute(for: "channel:test")
        XCTAssertNotNil(routes)
        XCTAssertEqual(routes?.count, 2)
        XCTAssertEqual(routes?[0].neighbor, "peer1")
        XCTAssertEqual(routes?[0].score, 2.0, accuracy: 0.001)
        XCTAssertEqual(routes?[1].neighbor, "peer2")
        XCTAssertEqual(routes?[1].score, 1.0, accuracy: 0.001)
    }

    // MARK: - Evaporation

    func testEvaporationDecaysScores() async {
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1")

        await intel.evaporatePheromones()

        let routes = await intel.pheromoneRoute(for: "channel:test")
        XCTAssertNotNil(routes)

        // decayFactor = 0.5^(5/30) ≈ 0.891
        let expectedScore = pow(0.5, 5.0 / 30.0)
        XCTAssertEqual(routes?.first?.score ?? 0, expectedScore, accuracy: 0.001)
    }

    // MARK: - Evaporation prunes below minimum

    func testEvaporationPrunesBelowMinimum() async {
        // Deposit a tiny amount: 0.02
        await intel.depositPheromone(destination: "channel:test", viaNeighbor: "peer1", amount: 0.02)

        // Evaporate multiple times until below minPheromone (0.01)
        // 0.02 * 0.891 = 0.01782
        // 0.01782 * 0.891 = 0.01588
        // 0.01588 * 0.891 = 0.01415
        // 0.01415 * 0.891 = 0.01261
        // 0.01261 * 0.891 = 0.01123
        // 0.01123 * 0.891 = 0.01001 -- still above
        // 0.01001 * 0.891 = 0.00892 -- below 0.01, pruned
        for _ in 0..<10 {
            await intel.evaporatePheromones()
        }

        let routes = await intel.pheromoneRoute(for: "channel:test")
        XCTAssertNil(routes, "Trail should be pruned after sufficient evaporation")
    }

    // MARK: - Spore mode detection

    func testSporeModeWithNoPeers() async {
        await intel.updateVisiblePeerCount(0)
        // No link metrics recorded = 0 active links

        let spore = await intel.isInSporeMode()
        XCTAssertTrue(spore, "Should be in spore mode with 0 visible peers and 0 active links")
    }

    func testNotInSporeModeWithPeers() async {
        await intel.updateVisiblePeerCount(2)

        let spore = await intel.isInSporeMode()
        XCTAssertFalse(spore, "Should not be in spore mode with 2 visible peers")
    }

    // MARK: - Select relay peers — no data

    func testSelectRelayPeersReturnsNilWithNoPheromoneData() async {
        let packet = makePacket(channelID: "some-channel")
        let result = await intel.selectRelayPeers(for: packet, allPeers: ["p1", "p2", "p3"])
        XCTAssertNil(result, "Should return nil (broadcast fallback) with no pheromone data")
    }

    // MARK: - Select relay peers — with data

    func testSelectRelayPeersReturnsPeersWithPheromoneData() async {
        // Deposit pheromone for the channel key that selectRelayPeers uses
        await intel.depositPheromone(destination: "channel:test-channel", viaNeighbor: "p1")
        await intel.depositPheromone(destination: "channel:test-channel", viaNeighbor: "p1")
        await intel.depositPheromone(destination: "channel:test-channel", viaNeighbor: "p2")

        let packet = makePacket(channelID: "test-channel")
        let result = await intel.selectRelayPeers(for: packet, allPeers: ["p1", "p2", "p3"])

        XCTAssertNotNil(result)
        // Should include pheromone peers and possibly an exploration peer
        XCTAssertTrue(result?.contains("p1") == true, "Should include top pheromone peer")
    }

    // MARK: - Critical packets bypass pheromone

    func testCriticalPacketsBroadcast() async {
        await intel.depositPheromone(destination: "channel:sos-channel", viaNeighbor: "p1")

        // SOS payload triggers critical priority
        let sosPayload = Data("{\"type\":\"SOS\"}".utf8)
        let packet = makePacket(type: .control, channelID: "sos-channel", payload: sosPayload)

        let result = await intel.selectRelayPeers(for: packet, allPeers: ["p1", "p2", "p3"])
        XCTAssertNil(result, "Critical packets should return nil to broadcast to all peers")
    }

    // MARK: - Broadcast packets bypass pheromone

    func testBroadcastPacketsReturnNil() async {
        await intel.depositPheromone(destination: "channel:", viaNeighbor: "p1")

        let packet = makePacket(channelID: "")
        let result = await intel.selectRelayPeers(for: packet, allPeers: ["p1", "p2", "p3"])
        XCTAssertNil(result, "Packets with empty channelID should return nil (broadcast to all)")
    }

    // MARK: - Pheromone summary

    func testPheromoneSummaryReturnsTop10() async {
        // Deposit for 15 destinations
        for i in 0..<15 {
            await intel.depositPheromone(
                destination: "dest-\(i)",
                viaNeighbor: "peer1",
                amount: Double(i + 1)
            )
        }

        let summary = await intel.pheromoneSummary()
        XCTAssertEqual(summary.count, 10, "Summary should return only top 10 destinations")

        // Verify the top 10 are the ones with highest scores (dest-5 through dest-14)
        for i in 5..<15 {
            XCTAssertNotNil(summary["dest-\(i)"], "dest-\(i) should be in top 10")
        }
    }

    // MARK: - Merge pheromones from beacon

    func testMergePheromonesWithDiscount() async {
        let trails: [String: Double] = [
            "channel:alpha": 4.0,
            "channel:beta": 2.0
        ]

        await intel.mergePheromones(from: "neighbor-1", trails: trails, discount: 0.5)

        let alphaRoutes = await intel.pheromoneRoute(for: "channel:alpha")
        XCTAssertNotNil(alphaRoutes)
        XCTAssertEqual(alphaRoutes?.first?.score ?? 0, 2.0, accuracy: 0.001)

        let betaRoutes = await intel.pheromoneRoute(for: "channel:beta")
        XCTAssertNotNil(betaRoutes)
        XCTAssertEqual(betaRoutes?.first?.score ?? 0, 1.0, accuracy: 0.001)
    }

    // MARK: - DeliveryACK round-trip

    func testDeliveryACKRoundTrip() throws {
        let packetID = UUID()
        let original = DeliveryACK(
            ackedPacketID: packetID,
            originalSenderID: "sender-abc",
            ackerID: "acker-xyz",
            channelID: "channel-42",
            hopCount: 3
        )

        let wire = try original.wirePayload()

        // Verify ACK! prefix
        XCTAssertEqual(Array(wire[0..<4]), [0x41, 0x43, 0x4B, 0x21])

        let decoded = DeliveryACK.from(payload: wire)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.ackedPacketID, packetID)
        XCTAssertEqual(decoded?.originalSenderID, "sender-abc")
        XCTAssertEqual(decoded?.ackerID, "acker-xyz")
        XCTAssertEqual(decoded?.channelID, "channel-42")
        XCTAssertEqual(decoded?.hopCount, 3)
    }

    // MARK: - ACK magic priority

    func testACKMagicPriorityIsNormal() {
        let ackPayload = Data([0x41, 0x43, 0x4B, 0x21, 0x01, 0x02])
        let priority = MeshPacket.inferPriority(type: .control, payload: ackPayload)
        XCTAssertEqual(priority, .normal)
    }
}

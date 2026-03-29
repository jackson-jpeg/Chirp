import XCTest
@testable import Chirp

final class MeshIntelligenceTests: XCTestCase {

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

    /// Build a MeshPacket with sensible defaults for testing.
    private func makePacket(
        type: MeshPacket.PacketType = .audio,
        ttl: UInt8 = MeshPacket.defaultTTL,
        originID: UUID = UUID(),
        channelID: String = "test",
        payload: Data = Data()
    ) -> MeshPacket {
        MeshPacket(
            type: type,
            ttl: ttl,
            originID: originID,
            packetID: UUID(),
            sequenceNumber: 0,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: payload
        )
    }

    // MARK: - shouldRelay: Battery Thresholds

    func testShouldRelayReturnsFalseForLowPriorityAtCriticalBattery() async {
        let packet = makePacket()
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 0.05, priority: .low)
        XCTAssertFalse(result, "Low-priority packets should be dropped at critical battery (<10%)")
    }

    func testShouldRelayReturnsTrueForCriticalSOSAtCriticalBattery() async {
        let packet = makePacket(type: .control)
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 0.05, priority: .critical)
        XCTAssertTrue(result, "Critical SOS packets should still relay even at critical battery")
    }

    func testShouldRelayReturnsFalseForLowPriorityAtLowBattery() async {
        let packet = makePacket()
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 0.15, priority: .low)
        XCTAssertFalse(result, "Low-priority packets should be dropped at low battery (<20%)")
    }

    func testShouldRelayReturnsTrueForHighPriorityTextAtLowBattery() async {
        let packet = makePacket(type: .control)
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 0.15, priority: .high)
        XCTAssertTrue(result, "High-priority text packets should relay at low battery")
    }

    // MARK: - shouldRelay: Congestion

    func testCongestionDropsLowPriorityPackets() async {
        await intel.updateOutboundQueueCount(51)
        let packet = makePacket()
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 1.0, priority: .low)
        XCTAssertFalse(result, "Low-priority packets should be dropped when outbound queue exceeds 50")
    }

    // MARK: - shouldRelay: Rate Limiting

    func testRateLimitingThrottlesExcessivePacketsFromSameOrigin() async {
        let origin = UUID()

        // Send 100 packets to fill the rate window
        for _ in 0..<100 {
            let packet = makePacket(originID: origin)
            _ = await intel.shouldRelay(packet: packet, batteryLevel: 1.0, priority: .high)
        }

        // The 101st packet from the same origin should be throttled
        let packet = makePacket(originID: origin)
        let result = await intel.shouldRelay(packet: packet, batteryLevel: 1.0, priority: .high)
        XCTAssertFalse(result, "Packets exceeding 100/second from the same origin should be rate limited")
    }

    // MARK: - recordReceive

    func testRecordReceiveUpdatesLinkMetrics() async {
        let peerID = "peer-A"

        await intel.recordReceive(fromPeer: peerID, latencyMs: 50.0)
        let metrics = await intel.metricsForPeer(peerID)

        XCTAssertNotNil(metrics)
        XCTAssertEqual(metrics?.packetsReceived, 1)
        XCTAssertEqual(metrics?.avgLatencyMs ?? 0, 50.0, accuracy: 0.01)
        XCTAssertGreaterThan(metrics?.signalQuality ?? 0, 0)
    }

    // MARK: - meshHealthScore

    func testMeshHealthScoreReturnsZeroWithNoActivePeers() async {
        let score = await intel.meshHealthScore
        XCTAssertEqual(score, 0, "Health score should be 0 with no active peers")
    }

    // MARK: - bestPath

    func testBestPathBFSFindsCorrectMultiHopRoute() async {
        // Set up: self -> A -> B -> destination
        // Record receives so A is a direct (non-stale) peer
        await intel.recordReceive(fromPeer: "A", latencyMs: 10)

        // Build topology: A connects to B, B connects to destination
        await intel.updateTopology(peerID: "A", connectedTo: ["B"])
        await intel.updateTopology(peerID: "B", connectedTo: ["destination"])

        let path = await intel.bestPath(to: "destination")
        XCTAssertEqual(path, ["A", "B", "destination"])
    }

    func testBestPathReturnsNilForUnreachableDestination() async {
        // Record a direct peer but no topology connecting to the destination
        await intel.recordReceive(fromPeer: "A", latencyMs: 10)
        await intel.updateTopology(peerID: "A", connectedTo: ["B"])

        let path = await intel.bestPath(to: "unreachable-node")
        XCTAssertNil(path, "Should return nil when destination is not reachable through the mesh")
    }

    // MARK: - pruneStaleEntries

    func testPruneStaleEntriesRemovesOldData() async {
        // Record a peer so it exists in link metrics
        await intel.recordReceive(fromPeer: "stale-peer", latencyMs: 20)

        // Verify the peer exists
        let before = await intel.metricsForPeer("stale-peer")
        XCTAssertNotNil(before)

        // Prune with interval of 0 seconds (everything is older than "now")
        await intel.pruneStaleEntries(olderThan: 0)

        let after = await intel.metricsForPeer("stale-peer")
        XCTAssertNil(after, "Stale entries should be removed after pruning")
    }
}

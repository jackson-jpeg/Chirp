import MultipeerConnectivity
import os
import XCTest
@testable import Chirp

/// Demo Mode must never put a byte on the air. These tests spy on the one
/// seam between the app and the radio (``MeshRadio``) and count what reaches
/// it, first transport-only and then through the whole app stack with the
/// simulated peers answering.
@MainActor
final class DemoTransportIsolationTests: XCTestCase {

    // MARK: - Spy

    /// Stands in for `MCSession`: reports one connected peer so every send
    /// path has a recipient, and records every send it is handed.
    final class SpyRadio: MeshRadio, @unchecked Sendable {
        private let sent = OSAllocatedUnfairLock(initialState: [Data]())
        let peer = MCPeerID(displayName: "spy-peer")

        var connectedPeers: [MCPeerID] { [peer] }

        func send(_ data: Data, toPeers peerIDs: [MCPeerID], with mode: MCSessionSendDataMode) throws {
            sent.withLock { $0.append(data) }
        }

        var sendCount: Int { sent.withLock { $0.count } }
        var packets: [Data] { sent.withLock { $0 } }
    }

    private var spy: SpyRadio!
    private var transport: MultipeerTransport!

    override func setUp() async throws {
        try await super.setUp()
        spy = SpyRadio()
        transport = MultipeerTransport(
            displayName: "test",
            meshRouter: MeshRouter(localPeerID: UUID()),
            localPeerID: UUID().uuidString,
            localPeerName: "test",
            radio: spy
        )
    }

    override func tearDown() async throws {
        transport?.stop()
        transport = nil
        spy = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func wirePacket(channelID: String, type: MeshPacket.PacketType = .control) -> (packet: Data, wire: Data) {
        let packet = MeshPacket(
            type: type,
            ttl: 3,
            originID: UUID(),
            packetID: UUID(),
            sequenceNumber: 1,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: channelID,
            payload: Data("hello".utf8)
        ).serialize()
        var wire = Data([0xAA])
        wire.append(packet)
        return (packet, wire)
    }

    /// Every outbound entry point on the transport, once each. The async ones
    /// build their packet in a Task, so callers wait before counting.
    private func sendThroughEveryPath(channelID: String) throws {
        try transport.sendAudio(Data([1, 2, 3]), channelID: channelID)
        try transport.sendControl(
            .floorRequest(senderID: "me", senderName: "Me", timestamp: Date()),
            channelID: channelID
        )
        try transport.sendControlData(Data("TXT!x".utf8), channelID: channelID)
        let built = wirePacket(channelID: channelID)
        transport.forwardPacket(built.packet, excludePeer: "someone-else")
        transport.sendRawWireData(built.wire, reliable: true)
    }

    private func wait(_ seconds: Double = 1.0) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    /// Poll until `condition` holds or `timeout` passes. Returns whether it held.
    private func eventually(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    // MARK: - (a) Control: the spy sees real traffic

    /// Without this, a spy that never records anything would pass every
    /// "zero sends" assertion below.
    func testRealChannelReachesTheRadio() async throws {
        try sendThroughEveryPath(channelID: "real-channel")
        let allFive = await eventually(timeout: 3) { spy.sendCount == 5 }
        XCTAssertTrue(allFive, "expected all 5 send paths to reach the radio, got \(spy.sendCount)")
        XCTAssertEqual(transport.droppedOutboundCount, 0)
    }

    // MARK: - (b) Sandboxed: nothing reaches the radio

    func testSandboxBlocksEverySendPath() async throws {
        transport.setSandboxed(true)
        XCTAssertTrue(transport.isSandboxed)

        try sendThroughEveryPath(channelID: "real-channel")
        try sendThroughEveryPath(channelID: "")
        await wait(1.5)

        XCTAssertEqual(spy.sendCount, 0, "sandboxed transport handed \(spy.sendCount) packets to the radio")
        XCTAssertEqual(transport.droppedOutboundCount, 10)
    }

    // MARK: - (c) Demo channel: blocked even outside the sandbox

    func testDemoChannelIsNeverTransmitted() async throws {
        XCTAssertFalse(transport.isSandboxed)
        for channel in ["demo-general", "demo-trailhead", "demo-basecamp"] {
            try sendThroughEveryPath(channelID: channel)
        }
        await wait(1.5)

        XCTAssertEqual(spy.sendCount, 0, "demo-channel packets reached the radio: \(spy.sendCount)")
        XCTAssertEqual(transport.droppedOutboundCount, 15)
        XCTAssertTrue(MultipeerTransport.isDemoTraffic(wirePacket(channelID: "demo-general").wire))
        XCTAssertFalse(MultipeerTransport.isDemoTraffic(wirePacket(channelID: "general").wire))
    }

    // MARK: - (d) Full stack

    /// The whole app with Demo Mode on: the user sends a text and uses
    /// push-to-talk, the simulated peers ACK, reply and talk back, and the
    /// radio sees nothing. Then Demo Mode goes off and the same floor path
    /// does reach the radio.
    func testDemoModeEndToEndSendsNothing() async throws {
        let suite = "DemoTransportIsolationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let stackSpy = SpyRadio()
        let app = AppState(radio: stackSpy, demoDefaults: defaults)
        let transport = app.multipeerTransport
        defer { transport.stop() }

        // What PTTEngine wires at launch (PTTEngine.swift, "Floor control ->
        // network"): floor messages go out through the transport.
        app.floorSession.sendToAllPeers = { [weak transport] message in
            Task { @MainActor in try? transport?.sendControl(message, channelID: nil) }
        }

        app.demoMode.setEnabled(true)
        XCTAssertTrue(app.demoMode.isActive)
        XCTAssertTrue(transport.isSandboxed)
        XCTAssertTrue(defaults.bool(forKey: DemoMode.defaultsKey), "Demo Mode must persist")
        XCTAssertGreaterThan(app.connectedPeerCount, 0)

        let channelID = try XCTUnwrap(app.channelManager.activeChannel?.id)
        XCTAssertTrue(DemoMode.isDemoChannel(channelID))
        XCTAssertFalse(app.textMessageService.messages(for: channelID).isEmpty, "seeded history")

        // Text: sent, ACKed, answered.
        app.textMessageService.send(
            text: "Anyone at the trailhead?",
            channelID: channelID,
            senderID: app.localPeerID,
            senderName: app.localPeerName
        )
        let mine = try XCTUnwrap(app.textMessageService.messages(for: channelID).last)
        let acked = await eventually(timeout: 6) {
            app.textMessageService.messages(for: channelID).first { $0.id == mine.id }?.deliveryStatus != .sent
        }
        XCTAssertTrue(acked, "the simulated peer's ACK never arrived")
        let answered = await eventually(timeout: 8) {
            app.textMessageService.messages(for: channelID).contains { $0.replyToID == mine.id }
        }
        XCTAssertTrue(answered, "the simulated peer never replied")

        // Push-to-talk: press, "speak" (the encoder's output goes to
        // sendAudio, as PTTEngine does), release, and a peer answers.
        app.floorSession.requestFloor()
        for _ in 0..<5 { try transport.sendAudio(Data([0xF8, 0xFF, 0xFE]), channelID: nil) }
        await wait(0.3)
        app.floorSession.releaseFloor()
        let replied = await eventually(timeout: 10) {
            if case .receiving(let name, _) = app.floorSession.state {
                return DemoContent.peers.map(\.name).contains(name)
            }
            return false
        }
        XCTAssertTrue(replied, "no simulated push-to-talk reply")

        // Beacons and every other subsystem ran for this whole window.
        await wait(1.0)
        XCTAssertEqual(stackSpy.sendCount, 0, "Demo Mode put \(stackSpy.sendCount) packets on the radio")
        XCTAssertGreaterThan(transport.droppedOutboundCount, 0, "the sends above should have hit the gate")

        // Off again: the real channel list is back and the radio is live.
        app.demoMode.setEnabled(false)
        XCTAssertFalse(app.demoMode.isActive)
        XCTAssertFalse(transport.isSandboxed)
        XCTAssertFalse(defaults.bool(forKey: DemoMode.defaultsKey))
        XCTAssertFalse(app.channelManager.channels.contains { DemoMode.isDemoChannel($0.id) })
        XCTAssertEqual(app.connectedPeerCount, 0)

        let idle = await eventually(timeout: 8) { app.floorSession.state == .idle }
        XCTAssertTrue(idle)
        app.floorSession.requestFloor()
        let live = await eventually(timeout: 3) { stackSpy.sendCount > 0 }
        XCTAssertTrue(live, "with Demo Mode off the floor request should reach the radio")
        app.floorSession.releaseFloor()
        for packet in stackSpy.packets {
            XCTAssertFalse(MultipeerTransport.isDemoTraffic(packet))
        }
    }
}

/// The Friends screen is one of the paths App Review is told to take to
/// block someone, and Demo Mode is how they test it on one device. So the
/// simulated peers have to be in the friends list while Demo Mode is on —
/// and out of it, with nothing written to storage, the moment it is off.
@MainActor
final class DemoFriendsOverlayTests: XCTestCase {

    func testDemoFriendsAppearAndTheRealListComesBackUntouched() {
        let manager = FriendsManager()
        let realIDs = manager.friends.map(\.id)

        manager.enterDemoOverlay(DemoContent.chirpFriends())

        XCTAssertEqual(
            Set(manager.friends.map(\.name)),
            Set(DemoContent.peers.map(\.name)),
            "Demo Mode left the Friends screen without the simulated peers on it"
        )

        manager.exitDemoOverlay()
        XCTAssertEqual(manager.friends.map(\.id), realIDs,
                       "the real friends list did not come back as it was")
    }

    func testTheOverlayIsNeverWrittenToStorage() {
        let key = "com.chirpchirp.friends"
        let before = UserDefaults.standard.data(forKey: key)

        let manager = FriendsManager()
        manager.enterDemoOverlay(DemoContent.chirpFriends())
        let during = UserDefaults.standard.data(forKey: key)
        manager.exitDemoOverlay()

        XCTAssertEqual(during, before, "Demo Mode saved simulated friends over the real ones")

        // A fresh manager reads storage, so this is the check that survives a
        // relaunch: nobody inherits a simulated friend.
        let reloaded = FriendsManager()
        XCTAssertTrue(
            reloaded.friends.allSatisfy { !DemoContent.peerIDs.contains($0.id) },
            "a simulated friend survived into a fresh launch"
        )
    }

    /// The whole point of putting them there: a demo friend carries the
    /// routing UUID blocking enforces on, not a callsign.
    func testADemoFriendCarriesTheRoutingIdentity() {
        for friend in DemoContent.chirpFriends() {
            XCTAssertNotNil(UUID(uuidString: friend.id),
                            "demo friend \(friend.name) has no routing UUID to block")
        }
    }
}

/// Diagnostics is the sixth path the review notes give for blocking someone,
/// and its node list comes from the peer tracker, which the radio feeds and
/// Demo Mode deliberately never touches. So the view has to fall back to the
/// simulated peers, or that path dead-ends on an empty list.
@MainActor
final class DemoDiagnosticsPeersTests: XCTestCase {

    func testTheSimulatedPeersAreAvailableToDiagnostics() {
        let app = AppState()
        XCTAssertTrue(app.demoMode.peers.isEmpty, "Demo Mode offers peers while inactive")

        app.demoMode.setEnabled(true)
        defer { app.demoMode.setEnabled(false) }

        XCTAssertTrue(app.demoMode.isActive)
        XCTAssertEqual(
            Set(app.demoMode.peers.map(\.name)),
            Set(DemoContent.peers.map(\.name)),
            "Diagnostics would show an empty node list in Demo Mode"
        )
        XCTAssertTrue(
            app.demoMode.peers.allSatisfy { UUID(uuidString: $0.id) != nil },
            "a node in Diagnostics carries no routing UUID to block"
        )
    }
}

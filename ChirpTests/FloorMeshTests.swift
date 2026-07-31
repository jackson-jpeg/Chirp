import XCTest
@testable import Chirp

/// Multi-device floor-control tests.
///
/// `FloorControlTests` drives one `FloorController` and feeds it messages by
/// hand, which means every "collision" test there is really a test of one
/// device's reaction to a message the test author wrote. These tests wire real
/// controllers to each other through `FloorMeshHarness`, so the messages come
/// from the other device's actual behaviour and the test asserts on what the
/// devices collectively believe.
///
/// The property that matters across the whole mesh: **at most one device is
/// transmitting at any moment.** Two live microphones is the failure the user
/// hears as garbled or one-sided audio.
@MainActor
final class FloorMeshTests: XCTestCase {

    private var harness: FloorMeshHarness!

    override func setUp() async throws {
        try await super.setUp()
        harness = FloorMeshHarness(peers: [
            (id: "peer-A", name: "Alice"),
            (id: "peer-B", name: "Bob"),
        ])
    }

    override func tearDown() async throws {
        harness = nil
        try await super.tearDown()
    }

    // MARK: - Uncontested floor

    func testSingleSpeakerIsSeenAsSpeakerByEveryoneElse() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(harness.transmittingNodeIDs, ["peer-A"])
        XCTAssertEqual(
            harness["peer-B"].state,
            .receiving(speakerName: "Alice", speakerID: "peer-A")
        )
        XCTAssertEqual(harness.speakerIDs, ["peer-A": "peer-A", "peer-B": "peer-A"])
    }

    func testReleaseReturnsEveryDeviceToIdle() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        harness["peer-A"].releaseFloor()
        try harness.deliverAll()

        XCTAssertEqual(harness.states, ["peer-A": .idle, "peer-B": .idle])
        XCTAssertTrue(harness.speakerIDs.isEmpty, "Nobody should still be shown as speaking")
    }

    // MARK: - Simultaneous press

    /// Both users press talk before either device has heard the other. This is
    /// the collision the timestamp comparison exists for, and it is the case
    /// that cannot be aimed at on real hardware.
    ///
    /// Peer IDs are chosen so that the lexicographic tiebreak agrees with the
    /// timestamp ordering: if the two `Date()` values were to land on the same
    /// instant, "peer-A" still wins, so this test has one expected outcome
    /// rather than two.
    func testSimultaneousPressLeavesExactlyOneTransmitter() throws {
        harness["peer-A"].requestFloor()
        harness["peer-B"].requestFloor()

        XCTAssertEqual(
            harness.transmittingNodeIDs.sorted(),
            ["peer-A", "peer-B"],
            "Both devices optimistically grant themselves the floor before the collision is known — that part is by design"
        )

        try harness.deliverAll()

        XCTAssertEqual(
            harness.transmittingNodeIDs,
            ["peer-A"],
            "After the devices have heard each other, only the earlier requester may still hold the floor"
        )
        XCTAssertEqual(
            harness["peer-B"].state,
            .receiving(speakerName: "Alice", speakerID: "peer-A")
        )
    }

    func testSimultaneousPressLeavesBothDevicesAgreeingOnTheSpeaker() throws {
        harness["peer-A"].requestFloor()
        harness["peer-B"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(
            harness.speakerIDs,
            ["peer-A": "peer-A", "peer-B": "peer-A"],
            "A disagreement here is a split-brain mesh: each device shows a different person talking"
        )
    }

    /// Three devices pressing at once, to check the protocol converges rather
    /// than settling only in the two-device case. `deliverAll` throws if the
    /// devices keep answering each other, so a broadcast storm fails here.
    func testThreeWayCollisionConvergesOnOneSpeaker() throws {
        harness = FloorMeshHarness(peers: [
            (id: "peer-A", name: "Alice"),
            (id: "peer-B", name: "Bob"),
            (id: "peer-C", name: "Carol"),
        ])

        harness["peer-A"].requestFloor()
        harness["peer-B"].requestFloor()
        harness["peer-C"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(harness.transmittingNodeIDs, ["peer-A"])
        XCTAssertEqual(
            harness.speakerIDs,
            ["peer-A": "peer-A", "peer-B": "peer-A", "peer-C": "peer-A"]
        )
    }

    // MARK: - A device that never heard the request

    /// The dual-transmit case. peer-B never receives peer-A's floor request —
    /// it was in flight while peer-B was in `.denied`, or the radio dropped it
    /// — so peer-B believes the floor is free and takes it.
    ///
    /// peer-A wins the resulting collision on timestamp. What used to happen
    /// then was nothing: the winner said nothing, and peer-B had never seen the
    /// request it would have needed in order to work out that it had lost. Both
    /// microphones stayed open until somebody let go.
    func testDeviceThatNeverHeardTheRequestStopsOnceTheHolderRestatesIt() throws {
        harness["peer-A"].requestFloor()
        XCTAssertEqual(harness.dropMessages(from: "peer-A").count, 1, "peer-B must not hear this")

        harness["peer-B"].requestFloor()

        XCTAssertEqual(
            harness.transmittingNodeIDs.sorted(),
            ["peer-A", "peer-B"],
            "Both believe they hold the floor — this is the state the fix has to get out of"
        )

        try harness.deliverAll()

        XCTAssertEqual(
            harness.transmittingNodeIDs,
            ["peer-A"],
            "peer-B must give up the floor once it learns peer-A asked first"
        )
        XCTAssertEqual(
            harness["peer-B"].state,
            .receiving(speakerName: "Alice", speakerID: "peer-A"),
            "peer-B should be shown the speaker's name, which it can only have learned from the restatement"
        )
    }

    /// The same situation with a third device that also missed the request.
    /// Both latecomers have to yield, and the mesh still has to settle.
    func testTwoDevicesThatMissedTheRequestBothYieldToTheHolder() throws {
        harness = FloorMeshHarness(peers: [
            (id: "peer-A", name: "Alice"),
            (id: "peer-B", name: "Bob"),
            (id: "peer-C", name: "Carol"),
        ])

        harness["peer-A"].requestFloor()
        harness.dropMessages(from: "peer-A")

        harness["peer-B"].requestFloor()
        harness["peer-C"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(
            harness.transmittingNodeIDs,
            ["peer-A"],
            "Every device that took the floor without knowing about peer-A must have given it up"
        )
        XCTAssertEqual(harness.speakerIDs["peer-B"], "peer-A")

        // NOT asserted: that peer-C also ends up naming peer-A as the speaker.
        // It does not. peer-C hears peer-B's request first, enters `.receiving`,
        // and `.receiving` ignores every later request — so peer-C is left
        // displaying peer-B as the speaker while peer-B is itself listening to
        // peer-A. That is a separate, pre-existing defect: a device that is
        // already receiving never re-evaluates who holds the floor. No
        // microphone is open in that state, so it costs a wrong name rather
        // than crossed audio, and fixing it changes what the user sees
        // mid-transmission — queued rather than folded into this commit.
    }

    /// Losing the floor has to be announced, because the microphone is owned by
    /// `PTTEngine` and it has no other way to find out.
    func testLosingTheFloorFiresTheRevokeCallbackOnTheLoserOnly() throws {
        var revokedNodes: [String] = []
        for node in harness.nodes {
            let id = node.id
            node.controller.onFloorRevoked = { revokedNodes.append(id) }
        }

        harness["peer-A"].requestFloor()
        harness.dropMessages(from: "peer-A")
        harness["peer-B"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(
            revokedNodes,
            ["peer-B"],
            "Only the device that lost a floor it was actively holding should be told"
        )
    }

    func testWinningAnUncontestedFloorNeverFiresTheRevokeCallback() throws {
        var revokedNodes: [String] = []
        for node in harness.nodes {
            let id = node.id
            node.controller.onFloorRevoked = { revokedNodes.append(id) }
        }

        harness["peer-A"].requestFloor()
        try harness.deliverAll()
        harness["peer-A"].releaseFloor()
        try harness.deliverAll()

        XCTAssertTrue(revokedNodes.isEmpty, "Nobody lost a floor here: \(revokedNodes)")
    }

    /// A device that was never transmitting has no microphone to close, so a
    /// denied request must not raise the revoke signal.
    func testADeniedRequestDoesNotFireTheRevokeCallback() throws {
        var revoked = false
        harness["peer-B"].onFloorRevoked = { revoked = true }

        harness["peer-A"].requestFloor()
        try harness.deliverAll()
        harness["peer-B"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(harness["peer-B"].state, .denied)
        XCTAssertFalse(revoked)
    }

    /// The restatement is the fix's only new traffic, so it must not appear
    /// when there was no collision — otherwise every transmission would carry
    /// avoidable chatter.
    func testTheHolderOnlyRestatesItsClaimWhenChallenged() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        let requestsFromA = harness.delivered.filter {
            $0.from == "peer-A" && $0.message.isFloorRequest
        }
        XCTAssertEqual(requestsFromA.count, 1, "An unchallenged speaker should ask exactly once")
    }

    // MARK: - Ordering

    /// The floor request lands before the second user presses talk, so there is
    /// no collision to resolve — the second device knows the floor is taken and
    /// refuses locally.
    func testLateRequesterIsDeniedWithoutDisturbingTheSpeaker() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        harness["peer-B"].requestFloor()

        XCTAssertEqual(harness["peer-B"].state, .denied)
        XCTAssertEqual(harness.transmittingNodeIDs, ["peer-A"])

        try harness.deliverAll()

        XCTAssertEqual(
            harness.transmittingNodeIDs,
            ["peer-A"],
            "A denied request must not interrupt the device that legitimately holds the floor"
        )
    }

    /// A denied request broadcasts nothing at all, so it cannot disturb the
    /// mesh even in principle.
    func testDeniedRequestPutsNothingOnTheWire() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        harness["peer-B"].requestFloor()

        XCTAssertTrue(
            harness.inFlight.isEmpty,
            "Denied request should emit no messages, but sent: \(harness.inFlight.map(\.message))"
        )
    }

    // MARK: - Harness self-checks

    /// The harness is only trustworthy if withholding a message really does
    /// withhold it — several tests below depend on a device not having heard
    /// something.
    func testDroppedMessagesAreNeverDelivered() throws {
        harness["peer-A"].requestFloor()
        let dropped = harness.dropMessages(from: "peer-A")

        XCTAssertEqual(dropped.count, 1)
        try harness.deliverAll()

        XCTAssertEqual(
            harness["peer-B"].state,
            .idle,
            "peer-B never received the request, so it must still believe nobody is speaking"
        )
        XCTAssertTrue(harness.delivered.isEmpty)
    }

    func testSelectiveDeliveryLeavesOtherSendersQueued() throws {
        harness["peer-A"].requestFloor()
        harness["peer-B"].requestFloor()

        harness.deliverMessages(from: "peer-A")

        XCTAssertEqual(
            harness.delivered.map(\.from),
            ["peer-A"],
            "Only peer-A's traffic should have moved"
        )

        let peerBRequestsStillQueued = harness.inFlight.filter {
            $0.from == "peer-B" && $0.message.isFloorRequest
        }
        XCTAssertEqual(
            peerBRequestsStillQueued.count,
            1,
            "peer-B's own floor request must still be waiting — nothing should deliver it early"
        )
        XCTAssertEqual(
            harness["peer-B"].state,
            .receiving(speakerName: "Alice", speakerID: "peer-A"),
            "peer-B heard peer-A while its own request was still in flight, which is the real-world race"
        )
    }

    func testSenderNeverReceivesItsOwnBroadcast() throws {
        harness["peer-A"].requestFloor()
        try harness.deliverAll()

        XCTAssertEqual(
            harness["peer-A"].state,
            .transmitting,
            "A device that handled its own floor request would talk itself out of the floor"
        )
    }
}

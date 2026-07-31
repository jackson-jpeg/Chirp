import XCTest
@testable import Chirp

/// The two floor-protocol findings queued from the collision work: a device
/// that already has a speaker never re-evaluated who held the floor, and
/// `.denied` swallowed the requests that would have told it.
@MainActor final class FloorHolderTests: XCTestCase {

    private func makeController(id: String = "me", name: String = "Me") -> (FloorController, ControlMessageLog) {
        let log = ControlMessageLog()
        let controller = FloorController(localPeerID: id, localPeerName: name)
        controller.sendToAllPeers = { [log] message in log.record(message) }
        return (controller, log)
    }

    // MARK: - Denied must not leave the device believing the channel is free

    /// The defect, stated as the user would hit it: you are listening to Alice,
    /// you press the button, you are correctly denied — and 600ms later your
    /// device thinks nobody is speaking. The next press then passes the
    /// `state == .idle` guard and transmits straight over her.
    func testPressingWhileSomeoneElseSpeaksDoesNotLeaveTheChannelLookingFree() async throws {
        let (floor, log) = makeController()

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: Date()))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"))

        floor.requestFloor()
        XCTAssertEqual(floor.state, .denied)

        // Outlast the 600ms denial feedback.
        try await Task.sleep(for: .milliseconds(900))

        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"),
                       "must return to receiving Alice, not to idle")
        XCTAssertEqual(floor.currentSpeaker?.id, "alice")

        // And the follow-up press must still be refused.
        log.reset()
        floor.requestFloor()
        XCTAssertEqual(floor.state, .denied)
        XCTAssertTrue(log.floorRequests.isEmpty, "a denied press must put nothing on the wire")
    }

    /// Pressing the button a second time while already transmitting. The
    /// denial used to drop this device to `.idle` with the microphone open —
    /// and `releaseFloor()` is guarded on `.transmitting`, so letting go then
    /// broadcast nothing and every peer went on believing this device held the
    /// floor until the 120-second watchdog. This is the stuck-microphone
    /// symptom, reachable by pressing twice.
    func testPressingTwiceWhileTransmittingStillReleasesOnLetGo() async throws {
        let (floor, log) = makeController()

        floor.requestFloor()
        XCTAssertEqual(floor.state, .transmitting)
        floor.requestFloor()                       // denied: already transmitting
        XCTAssertEqual(floor.state, .denied)

        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(floor.state, .transmitting,
                       "the local speaker is still this device — return to transmitting")

        // The whole point: letting go must still put a release on the wire.
        log.reset()
        floor.releaseFloor()
        XCTAssertEqual(floor.state, .idle)
        XCTAssertNil(floor.currentSpeaker)
        XCTAssertEqual(log.releases.count, 1, "letting go must broadcast a release")
    }

    /// And with no speaker at all, the timer must still land on idle — the fix
    /// must not strand the device in some other state forever.
    func testDenialWithNoSpeakerAtAllReturnsToIdle() async throws {
        let (floor, _) = makeController()
        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: Date()))
        floor.requestFloor()
        XCTAssertEqual(floor.state, .denied)

        // The speaker leaves while this device is showing denial feedback.
        floor.handleMessage(.peerLeave(peerID: "alice"))
        XCTAssertNil(floor.currentSpeaker)

        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(floor.state, .idle)
    }

    // MARK: - A receiving device must evaluate challenges

    /// An earlier claim arriving late must win, because first-come-first-served
    /// is what every other device is applying to the same pair. Before the fix
    /// this branch was `break // Floor occupied, ignore`, so this device kept
    /// showing Bob while the rest of the mesh had moved to Alice.
    func testAnEarlierClaimArrivingLateTakesTheFloor() {
        let (floor, _) = makeController()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 1_005)

        floor.handleMessage(.floorRequest(senderID: "bob", senderName: "Bob", timestamp: late))
        XCTAssertEqual(floor.currentSpeaker?.id, "bob")

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: early))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"))
        XCTAssertEqual(floor.currentSpeaker?.id, "alice")
    }

    /// A later claim must NOT take the floor. Evaluating challenges cannot mean
    /// last-writer-wins, or the speaker changes every time anyone presses.
    func testALaterClaimDoesNotDisturbTheHolder() {
        let (floor, _) = makeController()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 1_005)

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: early))
        floor.handleMessage(.floorRequest(senderID: "bob", senderName: "Bob", timestamp: late))

        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"))
        XCTAssertEqual(floor.currentSpeaker?.id, "alice")
    }

    /// Identical timestamps resolve by peer ID, and every device must reach the
    /// same answer from the same pair — the tiebreak the collision path uses.
    func testIdenticalTimestampsResolveByPeerIDConsistently() {
        let stamp = Date(timeIntervalSince1970: 1_000)

        let (first, _) = makeController()
        first.handleMessage(.floorRequest(senderID: "zoe", senderName: "Zoe", timestamp: stamp))
        first.handleMessage(.floorRequest(senderID: "adam", senderName: "Adam", timestamp: stamp))
        XCTAssertEqual(first.currentSpeaker?.id, "adam", "lower peer ID wins")

        // Same pair, opposite arrival order, same outcome.
        let (second, _) = makeController()
        second.handleMessage(.floorRequest(senderID: "adam", senderName: "Adam", timestamp: stamp))
        second.handleMessage(.floorRequest(senderID: "zoe", senderName: "Zoe", timestamp: stamp))
        XCTAssertEqual(second.currentSpeaker?.id, "adam")
    }

    /// The holder restating its claim — the mechanism added by the collision
    /// fix — must be a no-op here, not a spurious state change.
    func testTheHolderRestatingItsClaimChangesNothing() {
        let (floor, _) = makeController()
        let stamp = Date(timeIntervalSince1970: 1_000)

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: stamp))
        var changes = 0
        floor.onStateChange = { _ in changes += 1 }

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: stamp))
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(floor.currentSpeaker?.id, "alice")
    }

    /// A device in `.denied` must still learn about a floor change. A local
    /// button press should not make it deaf for 600ms.
    func testADeniedDeviceStillLearnsWhoHasTheFloor() async throws {
        let (floor, _) = makeController()
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 1_005)

        floor.handleMessage(.floorRequest(senderID: "bob", senderName: "Bob", timestamp: late))
        floor.requestFloor()
        XCTAssertEqual(floor.state, .denied)

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: early))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"))

        // The pending denial timer must not then stamp on the new speaker.
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Alice", speakerID: "alice"))
    }

    /// Releasing clears the recorded claim time too, so the next speaker is not
    /// judged against a floor nobody holds.
    func testAfterAReleaseAnyClaimIsAccepted() {
        let (floor, _) = makeController()
        let early = Date(timeIntervalSince1970: 1_000)
        let later = Date(timeIntervalSince1970: 2_000)

        floor.handleMessage(.floorRequest(senderID: "alice", senderName: "Alice", timestamp: early))
        floor.handleMessage(.floorRelease(senderID: "alice"))
        XCTAssertEqual(floor.state, .idle)

        floor.handleMessage(.floorRequest(senderID: "bob", senderName: "Bob", timestamp: later))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Bob", speakerID: "bob"),
                       "a later claim must be accepted once the floor is free")
    }

    /// A transmitting device is unaffected by the new branch — the collision
    /// path still owns that case, including the revoke signal.
    func testTransmittingStillGoesThroughTheCollisionPath() {
        let (floor, log) = makeController(id: "zzz", name: "Me")
        var revoked = false
        floor.onFloorRevoked = { revoked = true }

        floor.requestFloor()
        XCTAssertEqual(floor.state, .transmitting)
        log.reset()

        // An earlier claim from a peer: the peer wins, and this device must be
        // told its microphone is now open with no floor behind it.
        floor.handleMessage(.floorRequest(senderID: "aaa", senderName: "Early",
                                          timestamp: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(floor.state, .receiving(speakerName: "Early", speakerID: "aaa"))
        XCTAssertTrue(revoked)
    }
}

import XCTest
@testable import Chirp

/// Tests that `PTTEngine` stops transmitting when the floor is taken from it.
///
/// `FloorMeshTests` proves the floor *protocol* resolves to one holder. That is
/// only half of the fix: the floor session does not own the microphone.
/// `PTTEngine` does, and before this change the only things that closed it were
/// the user letting go of the button, an audio interruption, the input device
/// disappearing, and the 120-second timeout. Losing the floor to a peer was not
/// on that list — the UI would switch to showing another speaker while this
/// device carried on capturing and sending audio frames.
///
/// `AudioEngine` is constructed but never `setup()`, so it holds no
/// `AVAudioEngine` and `startCapture()` is a no-op. That is deliberate: these
/// tests are about the decision to stop, not about the audio hardware, and
/// nothing here should depend on a microphone existing. The assertion is on
/// `PTTEngine.state`, which is the value that gates capture.
@MainActor
final class PTTEngineFloorLossTests: XCTestCase {

    private var engine: PTTEngine!
    private var floorSession: FloorSession!

    private var savedInterruptionBegan: (() -> Void)?
    private var savedInterruptionEnded: (() -> Void)?
    private var savedInputDeviceLost: (() -> Void)?

    override func setUp() async throws {
        try await super.setUp()

        // `setupCallbacks()` writes to AudioSessionManager's static callbacks,
        // which the test host app has already wired to its own live PTTEngine.
        savedInterruptionBegan = AudioSessionManager.onInterruptionBegan
        savedInterruptionEnded = AudioSessionManager.onInterruptionEnded
        savedInputDeviceLost = AudioSessionManager.onInputDeviceLost

        floorSession = FloorSession(localPeerID: "peer-B", localPeerName: "Bob")
        engine = PTTEngine(
            audioEngine: AudioEngine(),
            floorSession: floorSession,
            localPeerID: "peer-B"
        )
        engine.setupCallbacks()
    }

    override func tearDown() async throws {
        engine.stopTransmitting()
        engine = nil
        floorSession = nil

        AudioSessionManager.onInterruptionBegan = savedInterruptionBegan
        AudioSessionManager.onInterruptionEnded = savedInterruptionEnded
        AudioSessionManager.onInputDeviceLost = savedInputDeviceLost

        try await super.tearDown()
    }

    /// A request from a peer that predates ours: that peer holds the floor and
    /// this device has to stop talking.
    private func floorRequestFromAlice(secondsAgo: TimeInterval) -> FloorControlMessage {
        .floorRequest(
            senderID: "peer-A",
            senderName: "Alice",
            timestamp: Date().addingTimeInterval(-secondsAgo)
        )
    }

    func testLosingTheFloorToAnEarlierRequestStopsTransmitting() {
        engine.startTransmitting()
        XCTAssertEqual(engine.state, .transmitting)

        floorSession.handleMessage(floorRequestFromAlice(secondsAgo: 10))

        XCTAssertEqual(
            engine.state,
            .receiving(speakerName: "Alice", speakerID: "peer-A"),
            "PTTEngine still believing it is transmitting means the microphone is still open"
        )
    }

    func testLosingTheFloorLeavesTheFloorSessionAndEngineAgreeing() {
        engine.startTransmitting()

        floorSession.handleMessage(floorRequestFromAlice(secondsAgo: 10))

        XCTAssertEqual(
            engine.state,
            floorSession.state,
            "A disagreement here is the bug: the floor says one thing and the microphone does another"
        )
    }

    /// Giving up the floor is not the same as releasing it. Announcing a
    /// release we never made would tell the peer that just won the floor that
    /// it is now free.
    func testLosingTheFloorDoesNotBroadcastAFalseRelease() {
        // Replaces the transport-sending closure `setupCallbacks()` installed.
        let sent = ControlMessageLog()
        floorSession.sendToAllPeers = { sent.record($0) }

        engine.startTransmitting()
        floorSession.handleMessage(floorRequestFromAlice(secondsAgo: 10))

        XCTAssertTrue(
            sent.releases.isEmpty,
            "Sent an unwarranted release: \(sent.messages)"
        )
    }

    /// A peer asking *after* we started does not take the floor from us, so the
    /// microphone must stay open. Stopping here would cut the user off whenever
    /// somebody else pressed talk.
    func testALaterRequestFromAPeerDoesNotStopTransmitting() {
        engine.startTransmitting()

        floorSession.handleMessage(
            .floorRequest(
                senderID: "peer-A",
                senderName: "Alice",
                timestamp: Date().addingTimeInterval(60)
            )
        )

        XCTAssertEqual(engine.state, .transmitting)
    }

    func testReleasingNormallyStillReturnsToIdle() {
        engine.startTransmitting()
        XCTAssertEqual(engine.state, .transmitting)

        engine.stopTransmitting()

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(floorSession.state, .idle)
    }
}

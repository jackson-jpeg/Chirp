import XCTest
@testable import Chirp

final class FloorMachineTests: XCTestCase {

    private let me = FloorIdentity(peerID: "me", peerName: "Me")
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 1_005)

    private func claim(_ id: String, _ name: String, _ at: Date) -> FloorClaim {
        FloorClaim(peerID: id, peerName: name, claimedAt: at)
    }

    private func reduce(_ s: FloorState, _ e: FloorEvent) -> FloorOutcome {
        FloorMachine.reduce(s, on: e, as: me)
    }

    // MARK: - The property that five separate defects violated

    /// **The test this rewrite exists for.**
    ///
    /// Over every reachable (state × event) pair: if the microphone was open
    /// before the transition and is not open after it, the transition MUST have
    /// returned `.closeMicrophone`. A transition that silently drops the floor
    /// while capture continues is the exact shape of all five stuck-microphone
    /// defects, and this asserts it cannot happen anywhere rather than checking
    /// the handful of places somebody thought of.
    func testNoTransitionEverLeavesTheMicrophoneOpen() {
        let mine = claim("me", "Me", t0)
        let earlier = claim("aaa", "Early", Date(timeIntervalSince1970: 1))
        let later = claim("zzz", "Late", t1)

        let states: [FloorState] = [
            .idle,
            .holding(mine),
            .listening(later),
            .refused(under: .idle),
            .refused(under: .holding(mine)),
            .refused(under: .listening(later)),
        ]

        let events: [FloorEvent] = [
            .localPressed(at: t1),
            .localReleased,
            .refusalExpired,
            .transportLostPeer("zzz"),
            .transportLostPeer("me"),
            .received(.floorRequest(senderID: "aaa", senderName: "Early", timestamp: earlier.claimedAt), from: "aaa"),
            .received(.floorRequest(senderID: "zzz", senderName: "Late", timestamp: later.claimedAt), from: "zzz"),
            .received(.floorRelease(senderID: "zzz"), from: "zzz"),
            .received(.floorRelease(senderID: "me"), from: "zzz"),   // impersonation
            .received(.peerLeave(peerID: "zzz"), from: "zzz"),
            .received(.peerLeave(peerID: "me"), from: "zzz"),        // impersonation
            .received(.floorGranted(speakerID: "zzz"), from: "zzz"),
            .received(.peerJoin(peerID: "zzz", peerName: "Late"), from: "zzz"),
            .received(.heartbeat(peerID: "zzz", timestamp: t1), from: "zzz"),
        ]

        for state in states {
            for event in events {
                let outcome = reduce(state, event)
                let closed = outcome.effects.contains(.closeMicrophone)
                let opened = outcome.effects.contains(.openMicrophone)

                if state.microphoneIsOpen && !outcome.state.microphoneIsOpen {
                    XCTAssertTrue(closed,
                        "MIC LEFT OPEN: \(state) + \(event) -> \(outcome.state) with effects \(outcome.effects)")
                }
                if !state.microphoneIsOpen && outcome.state.microphoneIsOpen {
                    XCTAssertTrue(opened,
                        "MIC OPENED WITHOUT SAYING SO: \(state) + \(event) -> \(outcome.state)")
                }
                if state.microphoneIsOpen && outcome.state.microphoneIsOpen {
                    XCTAssertFalse(closed,
                        "CLOSED A MIC IT KEPT OPEN: \(state) + \(event) -> \(outcome.state)")
                }
            }
        }
    }

    /// `.holding` must be the only state with an open microphone, so that the
    /// property above has exactly one thing to track.
    func testHoldingIsTheOnlyOpenMicrophoneState() {
        let mine = claim("me", "Me", t0)
        XCTAssertTrue(FloorState.holding(mine).microphoneIsOpen)
        XCTAssertTrue(FloorState.refused(under: .holding(mine)).microphoneIsOpen)
        XCTAssertFalse(FloorState.idle.microphoneIsOpen)
        XCTAssertFalse(FloorState.listening(mine).microphoneIsOpen)
        XCTAssertFalse(FloorState.refused(under: .idle).microphoneIsOpen)
        XCTAssertFalse(FloorState.refused(under: .listening(mine)).microphoneIsOpen)
    }

    // MARK: - Impersonation: the two defects found by enumeration

    /// Stuck mic #4. A peer sends `.floorRelease` naming this device. Under the
    /// old design that cleared the floor and dropped to idle with the
    /// microphone open and nothing to close it.
    func testAPeerCannotEndOurTurnByNamingUs() {
        let mine = claim("me", "Me", t0)
        let outcome = reduce(.holding(mine), .received(.floorRelease(senderID: "me"), from: "attacker"))

        XCTAssertEqual(outcome.state, .holding(mine), "we still hold the floor")
        XCTAssertEqual(outcome.effects, [.reportImpersonation(claimed: "me", actual: "attacker")])
        XCTAssertFalse(outcome.effects.contains(.closeMicrophone))
    }

    /// Stuck mic #5. Same shape via `.peerLeave`.
    func testAPeerCannotEvictUsByNamingUsInPeerLeave() {
        let mine = claim("me", "Me", t0)
        let outcome = reduce(.holding(mine), .received(.peerLeave(peerID: "me"), from: "attacker"))

        XCTAssertEqual(outcome.state, .holding(mine))
        XCTAssertEqual(outcome.effects, [.reportImpersonation(claimed: "me", actual: "attacker")])
    }

    /// And a peer cannot end somebody *else's* turn either.
    func testAPeerCannotEndAThirdPartysTurn() {
        let holder = claim("bob", "Bob", t0)
        let outcome = reduce(.listening(holder), .received(.floorRelease(senderID: "bob"), from: "eve"))

        XCTAssertEqual(outcome.state, .listening(holder))
        XCTAssertEqual(outcome.effects, [.reportImpersonation(claimed: "bob", actual: "eve")])
    }

    /// The genuine article still works: a release from the peer that actually
    /// sent it frees the floor.
    func testAGenuineReleaseFreesTheFloor() {
        let holder = claim("bob", "Bob", t0)
        let outcome = reduce(.listening(holder), .received(.floorRelease(senderID: "bob"), from: "bob"))
        XCTAssertEqual(outcome.state, .idle)
        XCTAssertEqual(outcome.effects, [])
    }

    // MARK: - Refusal carries what it interrupted

    /// Pressing while a peer talks is refused, and returning from the refusal
    /// restores *listening to that peer* — not idle. Dropping to idle is what
    /// let the next press transmit straight over them.
    func testRefusalWhileListeningReturnsToListening() {
        let holder = claim("bob", "Bob", t0)
        let pressed = reduce(.listening(holder), .localPressed(at: t1))

        XCTAssertEqual(pressed.state, .refused(under: .listening(holder)))
        XCTAssertEqual(pressed.effects, [.startRefusalTimer(FloorMachine.refusalFeedbackDuration)])
        XCTAssertFalse(pressed.effects.contains(.openMicrophone), "a refused press must not open the mic")

        let expired = reduce(pressed.state, .refusalExpired)
        XCTAssertEqual(expired.state, .listening(holder))
    }

    /// Double-pressing while transmitting keeps holding, and letting go still
    /// releases. Under the old design the second press dropped to idle with the
    /// microphone open, and `releaseFloor` was guarded on `.transmitting`, so
    /// letting go broadcast nothing at all.
    func testDoublePressWhileHoldingStillReleasesOnLetGo() {
        let mine = claim("me", "Me", t0)
        let pressed = reduce(.holding(mine), .localPressed(at: t1))

        XCTAssertEqual(pressed.state, .refused(under: .holding(mine)))
        XCTAssertTrue(pressed.state.microphoneIsOpen, "we are still transmitting")
        XCTAssertFalse(pressed.effects.contains(.closeMicrophone))

        let released = reduce(pressed.state, .localReleased)
        XCTAssertEqual(released.state, .idle)
        XCTAssertEqual(released.effects, [.closeMicrophone, .send(.floorRelease(senderID: "me"))])
    }

    /// Mashing the button must not stack refusal timers. The old design spawned
    /// one Task per press, unbounded.
    func testRepeatedPressesDoNotStackTimers() {
        let holder = claim("bob", "Bob", t0)
        var state = reduce(.listening(holder), .localPressed(at: t1)).state

        for _ in 0..<10 {
            let outcome = reduce(state, .localPressed(at: t1))
            XCTAssertEqual(outcome.effects, [], "a press while already refused must produce no new timer")
            state = outcome.state
        }
        XCTAssertEqual(state, .refused(under: .listening(holder)))
    }

    /// A refusal must not make the device deaf to who is speaking.
    func testARefusedDeviceStillLearnsWhoHasTheFloor() {
        let late = claim("zzz", "Late", t1)
        let early = claim("aaa", "Early", t0)

        let refused = reduce(.listening(late), .localPressed(at: t1)).state
        let outcome = reduce(refused, .received(
            .floorRequest(senderID: "aaa", senderName: "Early", timestamp: t0), from: "aaa"))

        XCTAssertEqual(outcome.state, .listening(early))
        _ = late
    }

    // MARK: - Contention

    func testUncontestedPressTakesTheFloorAndOpensTheMic() {
        let outcome = reduce(.idle, .localPressed(at: t0))
        XCTAssertEqual(outcome.state, .holding(claim("me", "Me", t0)))
        XCTAssertEqual(outcome.effects, [
            .openMicrophone,
            .send(.floorRequest(senderID: "me", senderName: "Me", timestamp: t0)),
        ])
    }

    func testWinningACollisionRestatesTheClaimAndKeepsTheMicOpen() {
        let mine = claim("me", "Me", t0)
        let outcome = reduce(.holding(mine), .received(
            .floorRequest(senderID: "zzz", senderName: "Late", timestamp: t1), from: "zzz"))

        XCTAssertEqual(outcome.state, .holding(mine))
        XCTAssertEqual(outcome.effects, [
            .send(.floorRequest(senderID: "me", senderName: "Me", timestamp: t0)),
        ])
        XCTAssertFalse(outcome.effects.contains(.closeMicrophone))
    }

    func testLosingACollisionClosesTheMicWithoutBeingAskedTwice() {
        let mine = claim("me", "Me", t0)
        let earlier = claim("aaa", "Early", Date(timeIntervalSince1970: 1))
        let outcome = reduce(.holding(mine), .received(
            .floorRequest(senderID: "aaa", senderName: "Early", timestamp: earlier.claimedAt), from: "aaa"))

        XCTAssertEqual(outcome.state, .listening(earlier))
        XCTAssertEqual(outcome.effects, [.closeMicrophone, .send(.floorGranted(speakerID: "aaa"))])
    }

    /// Ties resolve by peer ID, and both devices must reach the same answer.
    func testIdenticalTimestampsResolveTheSameWayFromBothSides() {
        let adam = claim("adam", "Adam", t0)
        let zoe = claim("zoe", "Zoe", t0)
        XCTAssertTrue(adam.beats(zoe))
        XCTAssertFalse(zoe.beats(adam))

        let asZoe = FloorMachine.reduce(
            .holding(zoe),
            on: .received(.floorRequest(senderID: "adam", senderName: "Adam", timestamp: t0), from: "adam"),
            as: FloorIdentity(peerID: "zoe", peerName: "Zoe"))
        XCTAssertEqual(asZoe.state, .listening(adam), "zoe must yield to adam")
        XCTAssertTrue(asZoe.effects.contains(.closeMicrophone))
    }

    func testALaterClaimDoesNotDisturbTheHolder() {
        let holder = claim("aaa", "Early", t0)
        let outcome = reduce(.listening(holder), .received(
            .floorRequest(senderID: "zzz", senderName: "Late", timestamp: t1), from: "zzz"))
        XCTAssertEqual(outcome.state, .listening(holder))
        XCTAssertEqual(outcome.effects, [])
    }

    func testTheHolderRestatingItsClaimIsInert() {
        let holder = claim("bob", "Bob", t0)
        let outcome = reduce(.listening(holder), .received(
            .floorRequest(senderID: "bob", senderName: "Bob", timestamp: t0), from: "bob"))
        XCTAssertEqual(outcome.state, .listening(holder))
        XCTAssertEqual(outcome.effects, [])
    }

    // MARK: - Transport loss vs. claimed loss

    /// The transport observing a peer disappear is trustworthy in a way a
    /// `.peerLeave` message is not — the transport cannot be lied to about
    /// which connection dropped.
    func testTransportLosingTheSpeakerFreesTheFloor() {
        let holder = claim("bob", "Bob", t0)
        let outcome = reduce(.listening(holder), .transportLostPeer("bob"))
        XCTAssertEqual(outcome.state, .idle)
    }

    func testTransportLosingSomeoneElseChangesNothing() {
        let holder = claim("bob", "Bob", t0)
        let outcome = reduce(.listening(holder), .transportLostPeer("carol"))
        XCTAssertEqual(outcome.state, .listening(holder))
        XCTAssertEqual(outcome.effects, [])
    }

    /// Our own device disappearing from our own transport is meaningless and
    /// must never close our microphone.
    func testTransportLosingUsDoesNotCloseOurMicrophone() {
        let mine = claim("me", "Me", t0)
        let outcome = reduce(.holding(mine), .transportLostPeer("me"))
        XCTAssertEqual(outcome.state, .holding(mine))
        XCTAssertEqual(outcome.effects, [])
    }

    // MARK: - floorGranted is inert, on purpose

    func testFloorGrantedIsInertInEveryState() {
        let mine = claim("me", "Me", t0)
        let other = claim("bob", "Bob", t0)
        for state in [FloorState.idle, .holding(mine), .listening(other), .refused(under: .listening(other))] {
            let outcome = reduce(state, .received(.floorGranted(speakerID: "carol"), from: "bob"))
            XCTAssertEqual(outcome.state, state, "floorGranted must not move the floor")
            XCTAssertEqual(outcome.effects, [])
        }
    }

    // MARK: - Releasing when we do not hold

    func testReleasingWhenNotHoldingDoesNothing() {
        let other = claim("bob", "Bob", t0)
        for state in [FloorState.idle, .listening(other), .refused(under: .listening(other))] {
            let outcome = reduce(state, .localReleased)
            XCTAssertEqual(outcome.state, state)
            XCTAssertEqual(outcome.effects, [], "must not broadcast a release we never made")
        }
    }
}

import XCTest
@testable import Chirp

final class FloorControlTests: XCTestCase {

    private var controller: FloorController!
    private var broadcastedMessages: [FloorControlMessage]!

    override func setUp() {
        super.setUp()
        broadcastedMessages = []
        controller = FloorController(localPeerID: "local-1", localPeerName: "LocalUser")
        controller.sendToAllPeers = { [weak self] message in
            self?.broadcastedMessages.append(message)
        }
    }

    override func tearDown() {
        controller = nil
        broadcastedMessages = nil
        super.tearDown()
    }

    // MARK: - requestFloor

    func testRequestFloorWhenIdleTransitionsToTransmitting() {
        XCTAssertEqual(controller.state, .idle)

        controller.requestFloor()

        XCTAssertEqual(controller.state, .transmitting)
    }

    func testRequestFloorWhenIdleBroadcastsFloorRequest() {
        controller.requestFloor()

        XCTAssertEqual(broadcastedMessages.count, 1)
        if case .floorRequest(let senderID, let senderName, _) = broadcastedMessages.first {
            XCTAssertEqual(senderID, "local-1")
            XCTAssertEqual(senderName, "LocalUser")
        } else {
            XCTFail("Expected floorRequest broadcast")
        }
    }

    func testRequestFloorWhenReceivingTransitionsToDenied() {
        // Put controller into receiving state via remote floor request
        let remoteRequest = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "RemoteUser",
            timestamp: 1000
        )
        controller.handleMessage(remoteRequest)
        XCTAssertEqual(controller.state, .receiving(speakerName: "RemoteUser", speakerID: "remote-1"))

        controller.requestFloor()

        XCTAssertEqual(controller.state, .denied)
    }

    func testRequestFloorWhenTransmittingStaysTransmitting() {
        controller.requestFloor()
        XCTAssertEqual(controller.state, .transmitting)

        // Second request while already transmitting should not change state
        controller.requestFloor()
        XCTAssertEqual(controller.state, .transmitting)
    }

    // MARK: - releaseFloor

    func testReleaseFloorWhenTransmittingTransitionsToIdle() {
        controller.requestFloor()
        XCTAssertEqual(controller.state, .transmitting)

        controller.releaseFloor()

        XCTAssertEqual(controller.state, .idle)
    }

    func testReleaseFloorBroadcastsFloorRelease() {
        controller.requestFloor()
        broadcastedMessages.removeAll()

        controller.releaseFloor()

        XCTAssertEqual(broadcastedMessages.count, 1)
        if case .floorRelease(let senderID) = broadcastedMessages.first {
            XCTAssertEqual(senderID, "local-1")
        } else {
            XCTFail("Expected floorRelease broadcast")
        }
    }

    func testReleaseFloorWhenIdleDoesNothing() {
        XCTAssertEqual(controller.state, .idle)

        controller.releaseFloor()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertTrue(broadcastedMessages.isEmpty)
    }

    // MARK: - handleMessage: floorRequest

    func testHandleRemoteFloorRequestWhenIdleTransitionsToReceiving() {
        let message = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )

        controller.handleMessage(message)

        XCTAssertEqual(controller.state, .receiving(speakerName: "Alice", speakerID: "remote-1"))
    }

    func testHandleRemoteFloorRequestWhenIdleSetsCurrentSpeaker() {
        let message = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )

        controller.handleMessage(message)

        XCTAssertEqual(controller.currentSpeaker?.id, "remote-1")
        XCTAssertEqual(controller.currentSpeaker?.name, "Alice")
    }

    func testHandleRemoteFloorRequestWhenTransmittingDoesNotChangeState() {
        controller.requestFloor()
        XCTAssertEqual(controller.state, .transmitting)

        let message = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Bob",
            timestamp: 5000
        )
        controller.handleMessage(message)

        // Local user already has the floor; remote request should not override
        XCTAssertEqual(controller.state, .transmitting)
    }

    // MARK: - handleMessage: floorRelease

    func testHandleFloorReleaseTransitionsToIdle() {
        // First, put into receiving state
        let request = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )
        controller.handleMessage(request)
        XCTAssertEqual(controller.state, .receiving(speakerName: "Alice", speakerID: "remote-1"))

        // Now handle release
        let release = FloorControlMessage.floorRelease(senderID: "remote-1")
        controller.handleMessage(release)

        XCTAssertEqual(controller.state, .idle)
    }

    func testHandleFloorReleaseClearsCurrentSpeaker() {
        let request = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )
        controller.handleMessage(request)
        XCTAssertNotNil(controller.currentSpeaker)

        let release = FloorControlMessage.floorRelease(senderID: "remote-1")
        controller.handleMessage(release)

        XCTAssertNil(controller.currentSpeaker)
    }

    // MARK: - handleMessage: peerLeave

    func testHandlePeerLeaveWhenSpeakerLeavesTransitionsToIdle() {
        let request = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )
        controller.handleMessage(request)
        XCTAssertEqual(controller.state, .receiving(speakerName: "Alice", speakerID: "remote-1"))

        let leave = FloorControlMessage.peerLeave(peerID: "remote-1")
        controller.handleMessage(leave)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(controller.currentSpeaker)
    }

    func testHandlePeerLeaveWhenNonSpeakerLeavesDoesNotChangeState() {
        let request = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 5000
        )
        controller.handleMessage(request)

        // A different peer leaves
        let leave = FloorControlMessage.peerLeave(peerID: "remote-2")
        controller.handleMessage(leave)

        // State should still be receiving from remote-1
        XCTAssertEqual(controller.state, .receiving(speakerName: "Alice", speakerID: "remote-1"))
    }

    // MARK: - Collision: simultaneous floor requests

    func testCollisionFirstRequestWinsSecondDenied() {
        // Remote user grabs floor first
        let firstRequest = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Alice",
            timestamp: 1000
        )
        controller.handleMessage(firstRequest)
        XCTAssertEqual(controller.state, .receiving(speakerName: "Alice", speakerID: "remote-1"))

        // Local user tries to request floor while remote has it
        controller.requestFloor()

        // Should be denied since floor is already taken
        XCTAssertEqual(controller.state, .denied)
    }

    func testCollisionLocalRequestFirstThenRemoteIgnored() {
        // Local grabs floor first
        controller.requestFloor()
        XCTAssertEqual(controller.state, .transmitting)

        // Remote tries to grab floor
        let remoteRequest = FloorControlMessage.floorRequest(
            senderID: "remote-1",
            senderName: "Bob",
            timestamp: 2000
        )
        controller.handleMessage(remoteRequest)

        // Local should still be transmitting (first-come-first-served)
        XCTAssertEqual(controller.state, .transmitting)
    }
}

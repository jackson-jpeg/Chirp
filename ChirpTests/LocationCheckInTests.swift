import CoreLocation
import UIKit
import XCTest
@testable import Chirp

// MARK: - The gate

/// Apple rejected 1.0 under 5.1.2(i) because the app could put a user on a map
/// without a per-session, manual check-in. The fix is a single gate, so these
/// are the tests that must never be loosened: every one of them asserts that
/// *no coordinate leaves the device* under a condition where the user has not
/// actively chosen to share right now.
final class LocationBroadcastGateTests: XCTestCase {

    private let fix = CLLocation(latitude: 37.3349, longitude: -122.0090)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func live(at offset: TimeInterval = 0) -> LocationCheckIn {
        LocationCheckIn(startedAt: now.addingTimeInterval(offset))
    }

    // MARK: No check-in

    func testNoCheckInEmitsNothing() {
        XCTAssertNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse,
                checkIn: nil,
                location: fix,
                at: now
            ),
            "Permission granted and a fix in hand is still not consent to broadcast — "
                + "only a check-in is"
        )
    }

    func testCheckedInEmitsTheCoordinate() {
        let coordinate = LocationBroadcastGate.coordinateForBroadcast(
            authorization: .authorizedWhenInUse,
            checkIn: live(),
            location: fix,
            at: now
        )
        XCTAssertEqual(coordinate?.latitude ?? 0, 37.3349, accuracy: 0.000_001)
        XCTAssertEqual(coordinate?.longitude ?? 0, -122.0090, accuracy: 0.000_001)
    }

    // MARK: Expiry

    func testExpiryStopsEmission() {
        let checkIn = live()
        let justBefore = checkIn.expiresAt.addingTimeInterval(-1)
        let atExpiry = checkIn.expiresAt
        let after = checkIn.expiresAt.addingTimeInterval(1)

        XCTAssertNotNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse, checkIn: checkIn, location: fix, at: justBefore),
            "A check-in must stay live right up to its expiry"
        )
        XCTAssertNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse, checkIn: checkIn, location: fix, at: atExpiry),
            "The instant of expiry is already expired — the window is half-open"
        )
        XCTAssertNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse, checkIn: checkIn, location: fix, at: after),
            "An expired check-in must never emit again without a fresh tap"
        )
    }

    func testCheckInWindowIsFifteenMinutes() {
        XCTAssertEqual(LocationCheckIn.duration, 15 * 60)
        let checkIn = live()
        XCTAssertEqual(checkIn.remaining(at: now), 15 * 60, accuracy: 0.001)
        XCTAssertEqual(checkIn.remaining(at: checkIn.expiresAt.addingTimeInterval(60)), 0,
                       "Remaining time must clamp at zero rather than going negative")
    }

    // MARK: Permission

    func testDeclinedPermissionNeverEmits() {
        for status: CLAuthorizationStatus in [.denied, .restricted, .notDetermined] {
            XCTAssertNil(
                LocationBroadcastGate.coordinateForBroadcast(
                    authorization: status,
                    checkIn: live(),
                    location: fix,
                    at: now
                ),
                "A live check-in must not override a missing grant (\(status.rawValue))"
            )
        }
    }

    func testAuthorizedAlwaysIsAcceptedButStillNeedsACheckIn() {
        XCTAssertNotNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedAlways, checkIn: live(), location: fix, at: now))
        XCTAssertNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedAlways, checkIn: nil, location: fix, at: now),
            "Even the broadest grant does not check the user in")
    }

    // MARK: No fix

    func testNoFixEmitsNothing() {
        XCTAssertNil(
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse,
                checkIn: live(),
                location: nil,
                at: now
            )
        )
    }
}

// MARK: - Controller

@MainActor
final class LocationSharingTests: XCTestCase {

    func testStartsCheckedOut() {
        let sharing = LocationSharing(locationService: LocationService())
        XCTAssertNil(sharing.checkIn)
        XCTAssertFalse(sharing.isSharing)
        XCTAssertNil(sharing.coordinateForBroadcast(),
                     "A freshly constructed app is not sharing anything")
    }

    /// The contract, stated so it holds whatever the simulator host's own
    /// location grant happens to be: a check-in begins if and only if
    /// permission was granted. Without it the attempt is refused outright
    /// rather than recorded and left to fail silently later.
    func testCheckInSucceedsExactlyWhenAuthorized() {
        let sharing = LocationSharing(locationService: LocationService())

        let started = sharing.beginCheckIn()

        XCTAssertEqual(started, sharing.isAuthorized,
                       "beginCheckIn must succeed exactly when permission is granted")
        XCTAssertEqual(sharing.checkIn != nil, sharing.isAuthorized,
                       "A refused check-in must leave no state behind")
        XCTAssertEqual(sharing.isSharing, sharing.isAuthorized)

        if !sharing.isAuthorized {
            XCTAssertNil(sharing.coordinateForBroadcast(),
                         "A declined user must never produce a coordinate")
        }

        sharing.stopSharing(reason: .user)
    }

    /// The full manual cycle, on a host that does have the grant.
    func testCheckInThenStopClearsEverything() throws {
        let sharing = LocationSharing(locationService: LocationService())
        try XCTSkipUnless(sharing.isAuthorized,
                          "Needs a location grant on the test host")

        XCTAssertTrue(sharing.beginCheckIn())
        XCTAssertTrue(sharing.isSharing)
        XCTAssertEqual(sharing.remaining, LocationCheckIn.duration, accuracy: 2,
                       "A fresh check-in starts with the full window")
        XCTAssertNil(sharing.lastStopReason, "Starting clears any previous stop reason")

        sharing.stopSharing(reason: .user)

        XCTAssertNil(sharing.checkIn)
        XCTAssertFalse(sharing.isSharing)
        XCTAssertEqual(sharing.lastStopReason, .user)
        XCTAssertNil(sharing.coordinateForBroadcast(),
                     "Stopping must close the gate immediately, fix or no fix")
    }

    /// Backgrounding ends sharing: there is no background broadcast.
    func testLeavingTheForegroundStopsSharing() throws {
        let sharing = LocationSharing(locationService: LocationService())
        try XCTSkipUnless(sharing.isAuthorized,
                          "Needs a location grant on the test host")

        XCTAssertTrue(sharing.beginCheckIn())

        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertNil(sharing.checkIn,
                     "Leaving the foreground must end the check-in, not suspend it")
        XCTAssertEqual(sharing.lastStopReason, .background)
        XCTAssertNil(sharing.coordinateForBroadcast())
    }

    func testStopIsIdempotent() {
        let sharing = LocationSharing(locationService: LocationService())
        sharing.stopSharing(reason: .user)
        sharing.stopSharing(reason: .expired)
        XCTAssertNil(sharing.checkIn)
        XCTAssertNil(sharing.lastStopReason,
                     "Stopping when not sharing is a no-op, not a state change")
    }

    /// The rejection called out "no option to enable automatic check-ins".
    /// The structural guarantee is that check-in state is never written down:
    /// with nothing persisted there is nothing for a relaunch to restore.
    func testCheckInStateIsNeverPersisted() {
        let before = Set(UserDefaults.standard.dictionaryRepresentation().keys)

        let sharing = LocationSharing(locationService: LocationService())
        _ = sharing.beginCheckIn()
        sharing.stopSharing(reason: .user)

        let added = Set(UserDefaults.standard.dictionaryRepresentation().keys)
            .subtracting(before)
        let suspicious = added.filter {
            let key = $0.lowercased()
            return key.contains("location") || key.contains("checkin")
                || key.contains("check-in") || key.contains("share")
        }
        XCTAssertTrue(
            suspicious.isEmpty,
            "Location sharing must leave nothing on disk; found \(suspicious). A persisted "
                + "check-in is an automatic check-in on the next launch."
        )

        // And a second instance — which is what a relaunch amounts to — is checked out.
        XCTAssertNil(LocationSharing(locationService: LocationService()).checkIn)
    }

    func testRemainingTextFormatsAsCountdown() {
        let sharing = LocationSharing(locationService: LocationService())
        XCTAssertEqual(sharing.remainingText, "0:00", "Not sharing reads as zero, not blank")
    }
}

// MARK: - Emission through the real beacon

/// `MeshBeacon` is the only thing that puts this device's position on the
/// wire. These drive the production broadcast path — `startBroadcasting` →
/// `.meshBeaconBroadcast` → the encoded BCN! payload — and decode what
/// actually would have been transmitted.
@MainActor
final class BeaconLocationEmissionTests: XCTestCase {

    private let peerID = UUID().uuidString

    /// Run the real broadcast loop once and decode the payload it posted.
    private func firstBroadcast(from beacon: MeshBeacon) async throws -> MeshBeacon.BeaconInfo {
        let captured = expectation(description: "beacon broadcast")
        nonisolated(unsafe) var payload: Data?

        let token = NotificationCenter.default.addObserver(
            forName: .meshBeaconBroadcast, object: nil, queue: .main
        ) { note in
            guard payload == nil, let data = note.userInfo?["payload"] as? Data else { return }
            payload = data
            captured.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        beacon.startBroadcasting(localID: peerID, localName: "Tester", channels: ["general"])
        await fulfillment(of: [captured], timeout: 5)
        beacon.stopBroadcasting()

        let data = try XCTUnwrap(payload, "The beacon never broadcast")
        let json = data.dropFirst(MeshBeacon.beaconMagic.count)
        return try JSONDecoder().decode(MeshBeacon.BeaconInfo.self, from: Data(json))
    }

    /// The default. Nothing wired the provider, so nothing can leak.
    func testBeaconCarriesNoLocationByDefault() async throws {
        let info = try await firstBroadcast(from: MeshBeacon())
        XCTAssertNil(info.latitude)
        XCTAssertNil(info.longitude)
    }

    /// The gate said no — because the user has not checked in — so the
    /// transmitted packet must have no coordinate in it at all.
    func testBeaconOmitsLocationWhenNotCheckedIn() async throws {
        let beacon = MeshBeacon()
        beacon.locationProvider = { nil }

        let info = try await firstBroadcast(from: beacon)
        XCTAssertNil(info.latitude, "A beacon must carry no position while checked out")
        XCTAssertNil(info.longitude)
    }

    /// And the positive case, so the test above is proving a gate rather than
    /// a feature that never worked.
    ///
    /// The coordinate no longer travels in the clear: Apple requires that a
    /// blocked peer cannot read this device's position, and on a relaying
    /// mesh their node sees the packet whatever the send list says, so the
    /// payload itself is sealed per recipient. What a live check-in produces
    /// is therefore an entry only the addressed peer can open, which is what
    /// this asserts. See `ChirpTests/PositionPrivacyTests.swift`.
    func testBeaconCarriesLocationWhileCheckedIn() async throws {
        let beacon = MeshBeacon()
        beacon.identity = BeaconIdentity()
        beacon.locationProvider = {
            LocationBroadcastGate.Coordinate(latitude: 37.3349, longitude: -122.0090)
        }

        // Somebody has to be listening: a position is sealed to the peers
        // this device has learned an agreement key for, and to nobody else.
        let nearby = BeaconIdentity()
        let nearbyID = UUID().uuidString
        let nearbyInfo = MeshBeacon.BeaconInfo(
            id: nearbyID,
            name: "Nearby",
            channels: ["general"],
            hopCount: 1,
            batteryLevel: 0.5,
            timestamp: Date(),
            lastSeen: Date(),
            signingPublicKey: nearby.signingPublicKey,
            fingerprint: nearby.fingerprint,
            agreementPublicKey: nearby.agreementPublicKey,
            identitySignature: nearby.attest(routingID: nearbyID)
        )
        beacon.handleBeacon(try XCTUnwrap(beacon.encodeBeacon(nearbyInfo)))

        let info = try await firstBroadcast(from: beacon)
        XCTAssertNil(info.latitude, "The coordinate must never be encoded in the clear")
        XCTAssertNil(info.longitude)

        let sealed = try XCTUnwrap(
            info.sealedPositions?[nearbyID],
            "A checked-in device must seal its position for the peer it knows"
        )
        let opened = try XCTUnwrap(nearby.openCoordinate(
            sealed,
            fromPeerAgreementKey: try XCTUnwrap(info.agreementPublicKey),
            context: MeshBeacon.positionContext(senderID: peerID, recipientID: nearbyID)
        ))
        XCTAssertEqual(opened.latitude, 37.3349, accuracy: 0.000_001)
        XCTAssertEqual(opened.longitude, -122.0090, accuracy: 0.000_001)
    }

    /// End to end through the real gate: an expired check-in stops emission
    /// without anything else changing — same permission, same fix.
    func testExpiredCheckInStopsBeaconEmission() async throws {
        let fix = CLLocation(latitude: 37.3349, longitude: -122.0090)
        let expired = LocationCheckIn(startedAt: Date().addingTimeInterval(-LocationCheckIn.duration - 1))

        let beacon = MeshBeacon()
        beacon.locationProvider = {
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .authorizedWhenInUse,
                checkIn: expired,
                location: fix,
                at: Date()
            )
        }

        let info = try await firstBroadcast(from: beacon)
        XCTAssertNil(info.latitude, "Emission must stop the moment the window closes")
        XCTAssertNil(info.longitude)
    }

    /// The declined path, through the same gate the app uses.
    func testDeclinedPermissionStopsBeaconEmission() async throws {
        let fix = CLLocation(latitude: 37.3349, longitude: -122.0090)
        let live = LocationCheckIn(startedAt: Date())

        let beacon = MeshBeacon()
        beacon.locationProvider = {
            LocationBroadcastGate.coordinateForBroadcast(
                authorization: .denied,
                checkIn: live,
                location: fix,
                at: Date()
            )
        }

        let info = try await firstBroadcast(from: beacon)
        XCTAssertNil(info.latitude, "A declined user must never be broadcast, check-in or not")
        XCTAssertNil(info.longitude)
    }
}

// MARK: - Blocking a peer's position

@MainActor
final class BlockedPeerLocationTests: XCTestCase {

    private func beaconPayload(
        from beacon: MeshBeacon,
        id: String,
        latitude: Double = 37.3349,
        longitude: Double = -122.0090
    ) throws -> Data {
        let info = MeshBeacon.BeaconInfo(
            id: id,
            name: "Nearby",
            channels: ["general"],
            hopCount: 1,
            batteryLevel: 0.8,
            timestamp: Date(),
            lastSeen: Date(),
            latitude: latitude,
            longitude: longitude
        )
        return try XCTUnwrap(beacon.encodeBeacon(info))
    }

    func testBlockedPeerLocationIsDropped() throws {
        let beacon = MeshBeacon()
        let blockedID = UUID().uuidString
        beacon.blockedIDsProvider = { [blockedID] }

        beacon.handleBeacon(try beaconPayload(from: beacon, id: blockedID))

        XCTAssertNil(
            beacon.knownNodes[blockedID],
            "A blocked peer's beacon must be discarded, so their position never becomes a map pin"
        )
        XCTAssertTrue(beacon.knownNodes.isEmpty)
    }

    func testUnblockedPeerLocationIsKept() throws {
        let beacon = MeshBeacon()
        beacon.blockedIDsProvider = { [UUID().uuidString] }

        let peerID = UUID().uuidString
        beacon.handleBeacon(try beaconPayload(from: beacon, id: peerID))

        let node = try XCTUnwrap(beacon.knownNodes[peerID],
                                 "Blocking one peer must not drop everyone else")
        XCTAssertEqual(try XCTUnwrap(node.latitude), 37.3349, accuracy: 0.000_001)
    }

    /// Blocking someone already on the map removes the pin they already
    /// placed, rather than only stopping future ones.
    func testBlockingRemovesAPeerAlreadyOnTheMap() throws {
        let beacon = MeshBeacon()
        let peerID = UUID().uuidString
        nonisolated(unsafe) var blocked: Set<String> = []
        beacon.blockedIDsProvider = { blocked }

        beacon.handleBeacon(try beaconPayload(from: beacon, id: peerID))
        XCTAssertNotNil(beacon.knownNodes[peerID], "Precondition: the peer is on the map")

        blocked.insert(peerID)
        beacon.handleBeacon(try beaconPayload(from: beacon, id: peerID))

        XCTAssertNil(beacon.knownNodes[peerID],
                     "The next beacon after a block must evict the existing pin")
    }
}

// MARK: - Loopback

/// Two real nodes over the in-memory mesh: the same router, the same packet
/// codec, the same beacon. What node B learns about node A is exactly what A
/// transmitted.
@MainActor
final class LocationLoopbackTests: XCTestCase {

    private func waitFor(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// Node A is checked out. B must learn A exists — presence still works —
    /// but must never learn where A is.
    func testCheckedOutNodeIsVisibleButHasNoPosition() async throws {
        let nodeA = try await LoopbackNode.make(name: "A")
        let nodeB = try await LoopbackNode.make(name: "B")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        // The production default: no provider wired means no coordinate.
        let info = MeshBeacon.BeaconInfo(
            id: nodeA.originID.uuidString,
            name: "A",
            channels: ["general"],
            hopCount: 0,
            batteryLevel: 0.9,
            timestamp: Date(),
            lastSeen: Date(),
            latitude: nodeA.meshBeacon.locationProvider?()?.latitude,
            longitude: nodeA.meshBeacon.locationProvider?()?.longitude
        )
        let payload = try XCTUnwrap(nodeA.meshBeacon.encodeBeacon(info))
        try nodeA.transport.sendControlData(payload, channelID: "")

        let learned = await waitFor {
            nodeB.meshBeacon.knownNodes[nodeA.originID.uuidString] != nil
        }
        XCTAssertTrue(learned, "Presence must still cross the mesh while checked out")

        let node = try XCTUnwrap(nodeB.meshBeacon.knownNodes[nodeA.originID.uuidString])
        XCTAssertNil(node.latitude, "B must not learn A's position from a checked-out node")
        XCTAssertNil(node.longitude)
    }

    /// A blocked peer's beacon crosses the wire and is dropped on arrival:
    /// B never records them at all, position included.
    func testBlockedPeerNeverReachesTheMapOverTheMesh() async throws {
        let nodeA = try await LoopbackNode.make(name: "A")
        let nodeB = try await LoopbackNode.make(name: "B")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        nodeB.meshBeacon.blockedIDsProvider = { [nodeA.originID.uuidString] }

        let info = MeshBeacon.BeaconInfo(
            id: nodeA.originID.uuidString,
            name: "A",
            channels: ["general"],
            hopCount: 0,
            batteryLevel: 0.9,
            timestamp: Date(),
            lastSeen: Date(),
            latitude: 37.3349,
            longitude: -122.0090
        )
        let payload = try XCTUnwrap(nodeA.meshBeacon.encodeBeacon(info))
        try nodeA.transport.sendControlData(payload, channelID: "")

        // Give delivery a real chance to happen before asserting it did not.
        let appeared = await waitFor(timeout: 2) {
            nodeB.meshBeacon.knownNodes[nodeA.originID.uuidString] != nil
        }
        XCTAssertFalse(
            appeared,
            "A blocked peer must not appear on the map even though their beacon reached the device"
        )
    }
}

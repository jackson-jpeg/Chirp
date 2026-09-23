import CryptoKit
import Foundation
import XCTest
@testable import Chirp

// MARK: - Shared fixtures

/// One device: a beacon, the identity it broadcasts under, and the routing
/// UUID peers address it by. Built from production API only — nothing here
/// reaches past ``MeshBeacon`` to plant state it could not have learned from
/// a packet.
@MainActor
private final class Node {
    let beacon = MeshBeacon()
    let identity: BeaconIdentity
    let name: String

    /// The routing UUID this node is addressed by. Peers learn it from the
    /// `id` field of the beacons it sends.
    var id: String { beacon.localRoutingID }

    init(name: String, identity: BeaconIdentity = BeaconIdentity()) {
        self.name = name
        self.identity = identity
        beacon.identity = identity
    }

    /// The payload this node would put on the wire, with an optional position.
    func announce(latitude: Double? = nil, longitude: Double? = nil) throws -> Data {
        let info = MeshBeacon.BeaconInfo(
            id: id,
            name: name,
            channels: ["general"],
            hopCount: 0,
            batteryLevel: 0.9,
            timestamp: Date(),
            lastSeen: Date(),
            neighborIDs: [],
            latitude: latitude,
            longitude: longitude
        )
        return try XCTUnwrap(beacon.encodeBeacon(info))
    }
}

private func decodeWire(_ payload: Data) throws -> MeshBeacon.BeaconInfo {
    let json = payload.dropFirst(MeshBeacon.beaconMagic.count)
    return try JSONDecoder().decode(MeshBeacon.BeaconInfo.self, from: Data(json))
}

private func reencode(_ info: MeshBeacon.BeaconInfo) throws -> Data {
    var payload = Data(MeshBeacon.beaconMagic)
    payload.append(try JSONEncoder().encode(info))
    return payload
}

// MARK: - The headline: a blocked peer cannot read the position

/// Apple's requirement is not "do not send your position to a blocked peer".
/// It is that a blocked peer never receives it — and on a mesh that relays
/// packets through intermediate nodes, the blocked peer sees the bytes
/// whatever the send list says. So the bytes themselves must be useless to
/// them. That is what this file exists to prove.
@MainActor
final class BlockedPeerCannotReadPositionTests: XCTestCase {

    private let latitude = 37.334_900
    private let longitude = -122.009_000

    func testBlockedPeerCannotDecryptAnyEntryInTheBeacon() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")          // allowed
        let carol = Node(name: "Carol")      // blocked

        // Both peers announce themselves, so Alice learns their agreement
        // keys the only way she ever does: from their own beacons.
        alice.beacon.handleBeacon(try bob.announce())
        alice.beacon.handleBeacon(try carol.announce())
        XCTAssertEqual(alice.beacon.knownNodes.count, 2, "Precondition: Alice knows both peers")

        // Carol is blocked after Alice already holds her key — the harder
        // case, and the one a user actually creates by tapping Block.
        alice.beacon.blockedIDsProvider = { [carol.id] }

        let payload = try alice.announce(latitude: latitude, longitude: longitude)
        let wire = try decodeWire(payload)
        let senderKey = try XCTUnwrap(wire.agreementPublicKey)
        let sealed = try XCTUnwrap(wire.sealedPositions, "Alice is checked in, so there must be a sealed position")

        // 1. The blocked peer is not addressed at all.
        XCTAssertNil(sealed[carol.id], "A blocked peer must get no entry of their own")
        XCTAssertEqual(Set(sealed.keys), [bob.id], "Only the allowed peer is addressed")

        // 2. The allowed peer reads the real coordinate.
        let forBob = try XCTUnwrap(sealed[bob.id])
        let bobsView = try XCTUnwrap(
            bob.identity.openCoordinate(
                forBob,
                fromPeerAgreementKey: senderKey,
                context: MeshBeacon.positionContext(senderID: alice.id, recipientID: bob.id)
            ),
            "Blocking Carol must not stop Bob from seeing Alice"
        )
        XCTAssertEqual(bobsView.latitude, latitude, accuracy: 0.000_001)
        XCTAssertEqual(bobsView.longitude, longitude, accuracy: 0.000_001)

        // 3. The blocked peer's key opens nothing. Every entry in the beacon,
        //    under every context a relay could plausibly try, including the
        //    one addressed to Bob that Carol can see going past.
        for (recipientID, box) in sealed {
            for context in [
                MeshBeacon.positionContext(senderID: alice.id, recipientID: recipientID),
                MeshBeacon.positionContext(senderID: alice.id, recipientID: carol.id)
            ] {
                XCTAssertNil(
                    carol.identity.openCoordinate(box, fromPeerAgreementKey: senderKey, context: context),
                    "A blocked peer's key opened the entry for \(recipientID) — the block is cosmetic"
                )
            }
        }

        // 4. And the coordinate is nowhere in the payload in the clear.
        let text = String(decoding: payload, as: UTF8.self)
        XCTAssertFalse(text.contains("latitude"), "The plaintext coordinate fields must be gone from the wire")
        XCTAssertFalse(text.contains("longitude"))
        XCTAssertFalse(text.contains("37.3349"), "The coordinate itself must not appear anywhere in the payload")
        XCTAssertFalse(text.contains("122.009"))
    }

    /// The same run, through the receiving side rather than the crypto: what
    /// each device would actually put on its map.
    func testBlockedPeerReceivingTheBeaconLearnsNoPosition() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        let carol = Node(name: "Carol")

        alice.beacon.handleBeacon(try bob.announce())
        alice.beacon.handleBeacon(try carol.announce())
        alice.beacon.blockedIDsProvider = { [carol.id] }

        let payload = try alice.announce(latitude: latitude, longitude: longitude)

        bob.beacon.handleBeacon(payload)
        let bobsNode = try XCTUnwrap(bob.beacon.knownNodes[alice.id])
        XCTAssertEqual(try XCTUnwrap(bobsNode.latitude), latitude, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(bobsNode.longitude), longitude, accuracy: 0.000_001)

        carol.beacon.handleBeacon(payload)
        let carolsNode = try XCTUnwrap(
            carol.beacon.knownNodes[alice.id],
            "Carol still sees that Alice exists — blocking is not invisibility"
        )
        XCTAssertNil(carolsNode.latitude, "The peer who blocked Carol must never appear on Carol's map")
        XCTAssertNil(carolsNode.longitude)
    }

    /// The evasion that per-recipient sealing would otherwise still allow: a
    /// blocked peer stands up a second identity — new signing key, new
    /// routing UUID, both perfectly attested — that advertises the *same*
    /// X25519 key. An entry sealed to the new identity is readable by the
    /// blocked device, because it is the same device. So any agreement key a
    /// blocked node claims is disqualified for every recipient.
    func testAnAgreementKeyClaimedByABlockedPeerIsNeverSealedTo() throws {
        let sharedAgreementKey = Curve25519.KeyAgreement.PrivateKey()

        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        let carol = Node(name: "Carol", identity: BeaconIdentity(
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: sharedAgreementKey
        ))
        let sockPuppet = Node(name: "Dave", identity: BeaconIdentity(
            signingKey: Curve25519.Signing.PrivateKey(),
            agreementKey: sharedAgreementKey
        ))

        alice.beacon.handleBeacon(try bob.announce())
        alice.beacon.handleBeacon(try carol.announce())
        alice.beacon.handleBeacon(try sockPuppet.announce())
        XCTAssertEqual(alice.beacon.knownNodes.count, 3, "Precondition: all three are known and verified")

        alice.beacon.blockedIDsProvider = { [carol.id] }

        let wire = try decodeWire(try alice.announce(latitude: latitude, longitude: longitude))
        let sealed = try XCTUnwrap(wire.sealedPositions)

        XCTAssertNil(sealed[carol.id])
        XCTAssertNil(
            sealed[sockPuppet.id],
            "The sock puppet's entry would be readable by the blocked device that shares its key"
        )
        XCTAssertEqual(Set(sealed.keys), [bob.id])

        // Proof that the exclusion was necessary: the blocked device's key
        // does open anything sealed to the sock puppet.
        let box = try XCTUnwrap(carol.identity.sealCoordinate(
            latitude: latitude,
            longitude: longitude,
            forPeerAgreementKey: sockPuppet.identity.agreementPublicKey,
            context: Data("demo".utf8)
        ))
        XCTAssertNotNil(carol.identity.openCoordinate(
            box,
            fromPeerAgreementKey: carol.identity.agreementPublicKey,
            context: Data("demo".utf8)
        ))
    }
}

// MARK: - Key agreement

final class PositionKeyAgreementTests: XCTestCase {

    /// The property the whole scheme rests on: either side reaches the same
    /// key from the other's public half, with no handshake — which is the
    /// only option on a mesh where there may be no round trip.
    func testDerivationIsCommutative() throws {
        let a = Curve25519.KeyAgreement.PrivateKey()
        let b = Curve25519.KeyAgreement.PrivateKey()

        let aWithB = try XCTUnwrap(BeaconIdentity.derivePositionKey(
            privateKey: a, peerAgreementPublicKey: b.publicKey.rawRepresentation))
        let bWithA = try XCTUnwrap(BeaconIdentity.derivePositionKey(
            privateKey: b, peerAgreementPublicKey: a.publicKey.rawRepresentation))

        XCTAssertEqual(
            aWithB.withUnsafeBytes { Data($0) },
            bWithA.withUnsafeBytes { Data($0) },
            "A deriving with B's key must equal B deriving with A's key"
        )

        // And a third party lands somewhere else entirely.
        let c = Curve25519.KeyAgreement.PrivateKey()
        let cWithA = try XCTUnwrap(BeaconIdentity.derivePositionKey(
            privateKey: c, peerAgreementPublicKey: a.publicKey.rawRepresentation))
        XCTAssertNotEqual(
            aWithB.withUnsafeBytes { Data($0) },
            cWithA.withUnsafeBytes { Data($0) }
        )
    }

    func testGarbagePublicKeyDerivesNothing() {
        let a = Curve25519.KeyAgreement.PrivateKey()
        XCTAssertNil(BeaconIdentity.derivePositionKey(privateKey: a, peerAgreementPublicKey: Data()))
        XCTAssertNil(BeaconIdentity.derivePositionKey(
            privateKey: a, peerAgreementPublicKey: Data(repeating: 0x41, count: 7)))
    }

    /// A sealed coordinate survives the wire with full precision: the map
    /// draws pins from these numbers.
    func testCoordinateBytesRoundTripExactly() throws {
        let bytes = BeaconIdentity.coordinateBytes(latitude: 37.334_912, longitude: -122.009_034)
        XCTAssertEqual(bytes.count, 16, "A coordinate must always seal to the same length")
        let coordinate = try XCTUnwrap(BeaconIdentity.coordinate(fromBytes: bytes))
        XCTAssertEqual(coordinate.latitude, 37.334_912, accuracy: 0.000_000_1)
        XCTAssertEqual(coordinate.longitude, -122.009_034, accuracy: 0.000_000_1)

        XCTAssertNil(BeaconIdentity.coordinate(fromBytes: bytes.prefix(15)), "A short box is not a coordinate")
    }
}

// MARK: - Round trip and degradation

@MainActor
final class SealedPositionRoundTripTests: XCTestCase {

    func testRoundTripToSixDecimalPlaces() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        alice.beacon.handleBeacon(try bob.announce())

        let payload = try alice.announce(latitude: 51.500_729, longitude: -0.124_625)
        bob.beacon.handleBeacon(payload)

        let learned = try XCTUnwrap(bob.beacon.knownNodes[alice.id])
        XCTAssertEqual(try XCTUnwrap(learned.latitude), 51.500_729, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(learned.longitude), -0.124_625, accuracy: 0.000_001)
    }

    /// A checked-out sender is still present on the mesh and still publishes
    /// the key peers seal to it — it just has nothing to say about where it
    /// is. This runs the real broadcast loop, not a hand-built beacon.
    func testCheckedOutSenderEmitsNoPositionEntries() async throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        alice.beacon.handleBeacon(try bob.announce())
        // The production default: no provider wired means no coordinate.
        alice.beacon.locationProvider = { nil }

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

        alice.beacon.startBroadcasting(localID: alice.id, localName: "Alice", channels: ["general"])
        await fulfillment(of: [captured], timeout: 5)
        alice.beacon.stopBroadcasting()

        let wire = try decodeWire(try XCTUnwrap(payload))
        XCTAssertNil(wire.sealedPositions, "A checked-out node must seal nothing for anyone")
        XCTAssertNil(wire.latitude)
        XCTAssertNil(wire.longitude)
        XCTAssertNotNil(
            wire.agreementPublicKey,
            "The sealing key is still published: not sharing a position does not mean refusing to receive one"
        )
    }

    /// Garbage in, no pin out. The mesh hands ``handleBeacon`` whatever
    /// arrives, including half a packet from a link that dropped mid-write.
    func testTruncatedOrCorruptPayloadYieldsNoPosition() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        alice.beacon.handleBeacon(try bob.announce())
        let payload = try alice.announce(latitude: 37.334_900, longitude: -122.009_000)

        // Cut the JSON in half: not decodable at all.
        bob.beacon.handleBeacon(payload.prefix(payload.count / 2))
        XCTAssertNil(bob.beacon.knownNodes[alice.id], "A truncated beacon must produce no node, and must not throw")

        // Decodable, but the sealed box is corrupt: the node appears with no
        // position rather than the app trusting a failed decrypt.
        var wire = try decodeWire(payload)
        var sealed = try XCTUnwrap(wire.sealedPositions)
        var box = try XCTUnwrap(sealed[bob.id])
        box[box.index(box.startIndex, offsetBy: box.count - 1)] ^= 0xFF
        sealed[bob.id] = box
        wire.sealedPositions = sealed
        bob.beacon.handleBeacon(try reencode(wire))

        let node = try XCTUnwrap(bob.beacon.knownNodes[alice.id])
        XCTAssertNil(node.latitude, "A box that fails its tag must leave no position behind")
        XCTAssertNil(node.longitude)

        // And a payload that is not a beacon at all is simply ignored.
        bob.beacon.handleBeacon(Data("not a beacon".utf8))
        bob.beacon.handleBeacon(Data())
    }

    /// The compatibility contract for this release: a beacon in the old shape
    /// decodes, the node appears, and it simply has no position and no
    /// identity. Nothing throws and nothing crashes.
    func testPreEncryptionBeaconStillDecodes() throws {
        let bob = Node(name: "Bob")
        let legacy = """
        {"id":"\(UUID().uuidString)","name":"Old Build","channels":["general"],"hopCount":1,\
        "batteryLevel":0.5,"timestamp":768000000,"lastSeen":768000000,\
        "latitude":37.3349,"longitude":-122.009}
        """
        var payload = Data(MeshBeacon.beaconMagic)
        payload.append(Data(legacy.utf8))
        bob.beacon.handleBeacon(payload)

        let node = try XCTUnwrap(
            bob.beacon.knownNodes.values.first,
            "A peer on the old format must still be visible on the mesh"
        )
        XCTAssertEqual(node.name, "Old Build")
        XCTAssertNil(node.latitude, "A plaintext coordinate from an old build is not read")
        XCTAssertNil(node.fingerprint)
    }
}

// MARK: - Identity attestation

@MainActor
final class BeaconIdentityAttestationTests: XCTestCase {

    func testVerifiedFingerprintIsStoredAndResolvable() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")

        alice.beacon.handleBeacon(try bob.announce())

        let node = try XCTUnwrap(alice.beacon.knownNodes[bob.id])
        XCTAssertEqual(node.fingerprint, bob.identity.fingerprint)

        let byName = try XCTUnwrap(alice.beacon.identity(forPeerNamed: "Bob"))
        XCTAssertEqual(byName.routingID, bob.id)
        XCTAssertEqual(byName.fingerprint, bob.identity.fingerprint)

        let byID = try XCTUnwrap(alice.beacon.identity(forRoutingID: bob.id))
        XCTAssertEqual(byID.fingerprint, bob.identity.fingerprint)

        XCTAssertNil(alice.beacon.identity(forPeerNamed: "Nobody"))
    }

    func testTamperedFingerprintIsRejected() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        let impostor = BeaconIdentity()

        var wire = try decodeWire(try bob.announce())
        wire.fingerprint = impostor.fingerprint
        alice.beacon.handleBeacon(try reencode(wire))

        XCTAssertTrue(
            alice.beacon.knownNodes.isEmpty,
            "A beacon claiming a fingerprint that does not match its signing key must be dropped"
        )
    }

    func testSwappedAgreementKeyIsRejected() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        let relay = BeaconIdentity()

        // A relay substitutes its own sealing key so positions addressed to
        // Bob become readable by the relay. The signature does not cover the
        // substitution, so it does not verify.
        var wire = try decodeWire(try bob.announce())
        wire.agreementPublicKey = relay.agreementPublicKey
        alice.beacon.handleBeacon(try reencode(wire))

        XCTAssertTrue(
            alice.beacon.knownNodes.isEmpty,
            "A swapped agreement key must invalidate the whole beacon"
        )
    }

    func testFingerprintWithNoSigningKeyIsRejected() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")

        var wire = try decodeWire(try bob.announce())
        wire.signingPublicKey = nil
        wire.identitySignature = nil
        alice.beacon.handleBeacon(try reencode(wire))

        XCTAssertTrue(
            alice.beacon.knownNodes.isEmpty,
            "A fingerprint with nothing to check it against is a claim, not an identity"
        )
    }

    func testSignatureOverAnotherRoutingIDIsRejected() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")

        var wire = try decodeWire(try bob.announce())
        wire.identitySignature = bob.identity.attest(routingID: UUID().uuidString)
        alice.beacon.handleBeacon(try reencode(wire))

        XCTAssertTrue(
            alice.beacon.knownNodes.isEmpty,
            "An attestation must bind the routing UUID it actually travels under"
        )
    }
}

// MARK: - A block that survives a rename

@MainActor
final class BlockFollowsIdentityTests: XCTestCase {

    /// Apple's requirement: the block identity is the peer's stable
    /// cryptographic identity, not their display name, so a blocked peer
    /// cannot evade the block by renaming. Here they go further and
    /// reinstall, arriving with a brand new routing UUID and a new callsign
    /// — but the same keypair, which is the thing they cannot change without
    /// becoming someone else.
    func testBlockedIdentitySurvivesRenameAndNewRoutingID() throws {
        let alice = Node(name: "Alice")
        let troll = Node(name: "Troll")

        alice.beacon.handleBeacon(try troll.announce())
        let blockedFingerprint = try XCTUnwrap(alice.beacon.identity(forPeerNamed: "Troll")?.fingerprint)

        nonisolated(unsafe) var blockedIDs: Set<String> = [troll.id]
        let blockedFingerprints: Set<String> = [blockedFingerprint]
        nonisolated(unsafe) var rekeyed: [(String, String, String)] = []

        alice.beacon.blockedIDsProvider = { blockedIDs }
        alice.beacon.blockedFingerprintsProvider = { blockedFingerprints }
        alice.beacon.onBlockedIdentityRekeyed = { id, fingerprint, name in
            rekeyed.append((id, fingerprint, name))
        }

        // The block takes effect on the next beacon under the old UUID.
        alice.beacon.handleBeacon(try troll.announce(latitude: 1, longitude: 2))
        XCTAssertNil(alice.beacon.knownNodes[troll.id])

        // Same person, new install, new name: a fresh MeshBeacon means a
        // fresh routing UUID, and only the identity carries over.
        let reborn = Node(name: "Friendly Newcomer")
        let rebornInfo = MeshBeacon.BeaconInfo(
            id: reborn.id,
            name: "Friendly Newcomer",
            channels: ["general"],
            hopCount: 1,
            batteryLevel: 0.5,
            timestamp: Date(),
            lastSeen: Date(),
            signingPublicKey: troll.identity.signingPublicKey,
            fingerprint: troll.identity.fingerprint,
            agreementPublicKey: troll.identity.agreementPublicKey,
            identitySignature: troll.identity.attest(routingID: reborn.id)
        )
        alice.beacon.handleBeacon(try reencode(rebornInfo))

        XCTAssertNil(
            alice.beacon.knownNodes[reborn.id],
            "A renamed, reinstalled blocked peer must not reappear on the mesh"
        )
        XCTAssertEqual(rekeyed.count, 1, "The new routing UUID must be reported so the block can follow it")
        XCTAssertEqual(rekeyed.first?.0, reborn.id)
        XCTAssertEqual(rekeyed.first?.1, blockedFingerprint)
        XCTAssertEqual(rekeyed.first?.2, "Friendly Newcomer")

        // Persisting the re-key is the caller's job; once done, the routing
        // UUID alone is enough and nothing is reported twice.
        blockedIDs.insert(reborn.id)
        alice.beacon.handleBeacon(try reencode(rebornInfo))
        XCTAssertEqual(rekeyed.count, 1)
        XCTAssertNil(alice.beacon.knownNodes[reborn.id])
    }

    /// And a blocked identity gets no sealed position under any UUID.
    func testRekeyedBlockedIdentityGetsNoPositionEntry() throws {
        let alice = Node(name: "Alice")
        let bob = Node(name: "Bob")
        let troll = Node(name: "Troll")

        alice.beacon.handleBeacon(try bob.announce())
        alice.beacon.handleBeacon(try troll.announce())

        alice.beacon.blockedFingerprintsProvider = { [troll.identity.fingerprint] }

        let wire = try decodeWire(try alice.announce(latitude: 37.3349, longitude: -122.009))
        XCTAssertEqual(
            Set(try XCTUnwrap(wire.sealedPositions).keys), [bob.id],
            "A peer blocked by identity must be excluded from the sealed map exactly as one blocked by UUID"
        )
    }
}

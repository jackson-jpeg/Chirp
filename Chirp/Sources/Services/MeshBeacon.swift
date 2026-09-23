import Foundation
import OSLog
import UIKit

/// Lightweight mesh presence beacon broadcast every 2 seconds.
///
/// Every ChirpChirp device periodically announces its presence so the mesh
/// can build a topology map. Beacons include the peer's channels, hop count,
/// and battery level. Stale nodes (not seen in 10 seconds) are pruned
/// automatically.
@Observable
@MainActor
final class MeshBeacon {

    // MARK: - Types

    /// One node's presence announcement.
    ///
    /// ## Wire format (breaking change, shipped in one release)
    ///
    /// `"BCN!"` followed by JSON. Two things changed at once, and there is no
    /// transitional format for either: Apple's rejection requires both that a
    /// blocked peer cannot read our position and that a block survives a
    /// rename, and a half-migrated mesh satisfies neither.
    ///
    /// 1. **The position is no longer in the JSON.** `latitude`/`longitude`
    ///    are not encoded at all. In their place ``sealedPositions`` maps a
    ///    recipient's routing UUID to an AES-GCM box that only that recipient
    ///    can open. Excluding a blocked peer from the *send* path would not
    ///    have been enough: the mesh relays packets through intermediate
    ///    nodes, so the blocked peer sees the bytes either way. The payload
    ///    itself has to be unreadable to them.
    /// 2. **The sender attests to its identity.** ``signingPublicKey``,
    ///    ``fingerprint``, ``agreementPublicKey`` and ``identitySignature``
    ///    let a receiver bind a routing UUID to a stable cryptographic
    ///    identity, so a block can follow the identity across a rename and a
    ///    new UUID.
    ///
    /// Old builds decode this and simply find no coordinate; new builds
    /// decode an old beacon and find no identity and no sealed position. In
    /// neither direction does anything throw — see ``init(from:)`` — which is
    /// the only compatibility guarantee made.
    struct BeaconInfo: Codable, Sendable, Identifiable {
        let id: String
        let name: String
        let channels: [String]
        let hopCount: UInt8
        let batteryLevel: Float
        let timestamp: Date
        var lastSeen: Date
        /// IDs of this node's direct peers -- used to build topology in MeshIntelligence.
        var neighborIDs: [String]

        /// The position, in the clear, **in memory only**.
        ///
        /// Deliberately absent from ``CodingKeys``, so it can never be
        /// encoded: on the way out it is the coordinate to seal, on the way
        /// in it is what we managed to open from the entry addressed to us.
        /// A peer with no entry for us — blocked, or simply checked out — has
        /// `nil` here, and every existing reader (the map, the node list)
        /// already treats `nil` as "no pin".
        var latitude: Double?
        var longitude: Double?

        /// Pheromone trail summary: top destination->score pairs for cross-node trail sharing.
        var pheromoneTrails: [String: Double]?

        // MARK: Identity (plaintext, and verified on arrival)

        /// Sender's Ed25519 public key, 32 raw bytes.
        var signingPublicKey: Data?

        /// Sender's identity fingerprint. Never believed as sent: the
        /// receiver recomputes it from ``signingPublicKey`` and drops the
        /// beacon on a mismatch.
        var fingerprint: String?

        /// Sender's X25519 public key, 32 raw bytes. Public by definition;
        /// this is how a recipient seals a position back to the sender.
        var agreementPublicKey: Data?

        /// Ed25519 signature over (routing UUID, fingerprint, agreement key).
        /// Without it a relay could swap the agreement key for its own and
        /// read every position addressed through it.
        var identitySignature: Data?

        /// Recipient routing UUID -> AES-GCM sealed coordinate, one entry per
        /// non-blocked peer this node knows a key for. A blocked peer gets no
        /// entry, and cannot open anyone else's.
        var sealedPositions: [String: Data]?

        /// True if this node was heard directly (1 hop away).
        var isDirect: Bool { hopCount <= 1 }

        enum CodingKeys: String, CodingKey {
            case id, name, channels, hopCount, batteryLevel, timestamp, lastSeen, neighborIDs
            case pheromoneTrails
            case signingPublicKey, fingerprint, agreementPublicKey, identitySignature
            case sealedPositions
        }

        init(
            id: String,
            name: String,
            channels: [String],
            hopCount: UInt8,
            batteryLevel: Float,
            timestamp: Date,
            lastSeen: Date,
            neighborIDs: [String] = [],
            latitude: Double? = nil,
            longitude: Double? = nil,
            pheromoneTrails: [String: Double]? = nil,
            signingPublicKey: Data? = nil,
            fingerprint: String? = nil,
            agreementPublicKey: Data? = nil,
            identitySignature: Data? = nil,
            sealedPositions: [String: Data]? = nil
        ) {
            self.id = id
            self.name = name
            self.channels = channels
            self.hopCount = hopCount
            self.batteryLevel = batteryLevel
            self.timestamp = timestamp
            self.lastSeen = lastSeen
            self.neighborIDs = neighborIDs
            self.latitude = latitude
            self.longitude = longitude
            self.pheromoneTrails = pheromoneTrails
            self.signingPublicKey = signingPublicKey
            self.fingerprint = fingerprint
            self.agreementPublicKey = agreementPublicKey
            self.identitySignature = identitySignature
            self.sealedPositions = sealedPositions
        }

        /// Every field added since 1.0 decodes with `decodeIfPresent`, so a
        /// beacon from a peer on any shipped format decodes rather than
        /// throwing. A corrupt or truncated payload still throws, and
        /// ``MeshBeacon/handleBeacon(_:)`` swallows that into "no node".
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            channels = try container.decode([String].self, forKey: .channels)
            hopCount = try container.decode(UInt8.self, forKey: .hopCount)
            batteryLevel = try container.decode(Float.self, forKey: .batteryLevel)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            lastSeen = try container.decode(Date.self, forKey: .lastSeen)
            // Backwards compatible: older beacons may omit neighborIDs
            neighborIDs = try container.decodeIfPresent([String].self, forKey: .neighborIDs) ?? []
            // Never on the wire in either direction; see the property doc.
            latitude = nil
            longitude = nil
            // Backwards compatible: older beacons may omit pheromone trails
            pheromoneTrails = try container.decodeIfPresent([String: Double].self, forKey: .pheromoneTrails)
            // Absent on every pre-encryption beacon.
            signingPublicKey = try container.decodeIfPresent(Data.self, forKey: .signingPublicKey)
            fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
            agreementPublicKey = try container.decodeIfPresent(Data.self, forKey: .agreementPublicKey)
            identitySignature = try container.decodeIfPresent(Data.self, forKey: .identitySignature)
            sealedPositions = try container.decodeIfPresent([String: Data].self, forKey: .sealedPositions)
        }

        /// Written out by hand rather than synthesised, because the one thing
        /// this method must never do — encode `latitude`/`longitude` — would
        /// otherwise be one accidental `CodingKeys` case away.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(channels, forKey: .channels)
            try container.encode(hopCount, forKey: .hopCount)
            try container.encode(batteryLevel, forKey: .batteryLevel)
            try container.encode(timestamp, forKey: .timestamp)
            try container.encode(lastSeen, forKey: .lastSeen)
            try container.encode(neighborIDs, forKey: .neighborIDs)
            try container.encodeIfPresent(pheromoneTrails, forKey: .pheromoneTrails)
            try container.encodeIfPresent(signingPublicKey, forKey: .signingPublicKey)
            try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
            try container.encodeIfPresent(agreementPublicKey, forKey: .agreementPublicKey)
            try container.encodeIfPresent(identitySignature, forKey: .identitySignature)
            try container.encodeIfPresent(sealedPositions, forKey: .sealedPositions)
        }
    }

    // MARK: - Public State

    /// All known nodes in the mesh (direct + relayed), keyed by peer ID.
    private(set) var knownNodes: [String: BeaconInfo] = [:]

    /// How many unique nodes in the mesh (excluding self).
    var meshNodeCount: Int { knownNodes.count }

    /// Maximum hop depth observed from any beacon.
    var maxHopDepth: UInt8 {
        knownNodes.values.map(\.hopCount).max() ?? 0
    }

    /// Estimated mesh range in meters (~80m per hop).
    var estimatedRange: Int { Int(maxHopDepth) * 80 }

    /// Nodes sorted by hop count (nearest first), then name.
    var sortedNodes: [BeaconInfo] {
        knownNodes.values.sorted { a, b in
            if a.hopCount != b.hopCount { return a.hopCount < b.hopCount }
            return a.name < b.name
        }
    }

    /// Direct peers (hop count 1).
    var directPeers: [BeaconInfo] {
        knownNodes.values.filter { $0.hopCount <= 1 }
    }

    /// Relayed peers (hop count > 1).
    var relayedPeers: [BeaconInfo] {
        knownNodes.values.filter { $0.hopCount > 1 }
    }

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshBeacon")
    private var broadcastTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?
    private var localID: String?
    private var localName: String?
    private var cachedBatteryLevel: Float = 0
    private var localChannels: [String] = []

    /// Pheromone router reference for including trail data in beacons.
    var pheromoneRouter: PheromoneRouter?

    /// The only source of coordinates for outgoing beacons.
    ///
    /// AppState wires this to ``LocationSharing/coordinateForBroadcast()``,
    /// which returns a coordinate only while a manual check-in is live. Left
    /// unset — as it is in every test that does not explicitly opt in — a
    /// beacon carries no position at all. Do not read a location manager from
    /// this class; the gate is the whole point.
    var locationProvider: (() -> LocationBroadcastGate.Coordinate?)?

    /// Blocked peer IDs, wired to ``BlockList``. A blocked peer's beacon is
    /// discarded on arrival, so their pin never reaches the map. The router
    /// already drops their packets by origin ID; this is the second lock on
    /// the same door, and the one that is cheap to test.
    ///
    /// These are routing UUID strings. A routing UUID is per-install and can
    /// be abandoned, which is why ``blockedFingerprintsProvider`` exists
    /// alongside it.
    var blockedIDsProvider: (() -> Set<String>)?

    /// Blocked *identities*, as verified Ed25519 fingerprints.
    ///
    /// Apple's first requirement for this resubmission is that the block
    /// identity is the peer's stable cryptographic identity rather than a
    /// display name, so a blocked peer cannot evade the block by renaming.
    /// A fingerprint is the first 8 bytes of SHA-256 over their signing
    /// public key: to change it they must abandon the keypair.
    var blockedFingerprintsProvider: (() -> Set<String>)?

    /// Fired when a blocked identity turns up under a routing UUID that is
    /// not yet blocked — the rename-and-reinstall evasion.
    ///
    /// The beacon does not own the block list, so it reports rather than
    /// writes: `AppState` persists the new routing UUID into ``BlockList``,
    /// which re-arms the router and the text service. Arguments are the new
    /// routing UUID, the verified fingerprint, and the name being used now.
    var onBlockedIdentityRekeyed: ((String, String, String) -> Void)?

    /// This device's wire identity: the Ed25519 key that attests to who we
    /// are and the X25519 key peers seal positions to. Wired by `AppState`
    /// from ``PeerIdentity``; until then beacons carry no attestation.
    var identity: BeaconIdentity?

    /// Keys used for beacons this device manufactures on someone else's
    /// behalf — Demo Mode's simulated peers and the screenshot seeder, which
    /// obviously hold no private key of their own, and the encode/decode
    /// round trips in tests.
    ///
    /// Such a beacon seals a position (so the simulated pins still appear on
    /// this device's own map) but never claims an identity: signing someone
    /// else's routing UUID with this device's key would manufacture a
    /// fingerprint that a user could then block, banning themselves.
    /// Created on first use rather than on every `MeshBeacon`: generating two
    /// keypairs is not free, and most instances never seed a beacon.
    /// `@Observable` rules out `lazy`, hence the explicit backing store.
    @ObservationIgnored private var _seedIdentity: BeaconIdentity?

    private var seedIdentity: BeaconIdentity {
        if let existing = _seedIdentity { return existing }
        let created = BeaconIdentity()
        _seedIdentity = created
        return created
    }

    /// The address peers seal to.
    ///
    /// Normally the routing UUID passed to ``startBroadcasting(localID:localName:channels:)``.
    /// Before that runs there is still a need for a stable self-address, so a
    /// beacon this device encodes and hands straight back to itself (Demo
    /// Mode, screenshot seeding, tests) can round-trip a position.
    var localRoutingID: String { localID ?? fallbackRoutingID }

    private let fallbackRoutingID = UUID().uuidString

    /// Cap on sealed entries per beacon.
    ///
    /// Each entry is a routing UUID plus a 44-byte box, roughly 110 bytes of
    /// JSON. Beacons go out every 2 seconds over a link shared with live
    /// audio, so the position is offered to the nearest peers first rather
    /// than to an unbounded mesh. `neighborIDs` is capped for the same reason.
    private static let maxSealedRecipients = 24

    /// Cached pheromone summary from last async fetch, included in next beacon.
    private var cachedPheromoneTrails: [String: Double]?

    /// Magic bytes prepended to beacon payloads.
    /// `nonisolated` because it is an immutable constant and the wire format
    /// is read from outside the main actor: the transport decides whether a
    /// payload is a beacon before handing it anywhere, and the tests frame
    /// and unframe payloads directly.
    nonisolated static let beaconMagic: [UInt8] = [0x42, 0x43, 0x4E, 0x21] // "BCN!"

    /// Stale threshold: nodes not seen for this duration are pruned.
    private static let staleThreshold: TimeInterval = 10.0

    /// Base broadcast interval in seconds.
    private static let baseBroadcastInterval: TimeInterval = 2.0

    /// Maximum broadcast interval under high mesh density.
    private static let maxBroadcastInterval: TimeInterval = 8.0

    /// Current broadcast interval, adjusted for mesh density.
    /// Set via ``updateBroadcastInterval(forPeerCount:)`` to slow beacons
    /// when many peers are visible, reducing airtime chatter.
    private(set) var currentBroadcastInterval: TimeInterval = baseBroadcastInterval

    // MARK: - Init

    init() {}

    // MARK: - Broadcasting

    /// Start broadcasting presence beacons every 2 seconds.
    ///
    /// - Parameters:
    ///   - localID: This device's stable peer ID.
    ///   - localName: This device's display name / callsign.
    ///   - channels: Channel IDs this device is currently on.
    @MainActor
    func startBroadcasting(localID: String, localName: String, channels: [String]) {
        self.localID = localID
        self.localName = localName
        self.localChannels = channels
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.cachedBatteryLevel = max(0, UIDevice.current.batteryLevel)

        stopBroadcasting()

        logger.info("Mesh beacon broadcasting started as \(localName, privacy: .public)")

        // Broadcast loop.
        broadcastTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.broadcastBeacon()
                try? await Task.sleep(for: .seconds(self.currentBroadcastInterval))
            }
        }

        // Prune loop runs at half the stale threshold.
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.staleThreshold / 2))
                guard let self else { break }
                self.pruneStale()
            }
        }
    }

    /// Stop broadcasting beacons.
    func stopBroadcasting() {
        broadcastTask?.cancel()
        broadcastTask = nil
        pruneTask?.cancel()
        pruneTask = nil
    }

    /// Update the channel list for future beacon broadcasts.
    func updateChannels(_ channels: [String]) {
        localChannels = channels
    }

    /// Adjust the beacon broadcast interval based on mesh density.
    /// In a dense mesh (many peers) we back off to reduce airtime chatter.
    /// In a sparse mesh we beacon at the base rate to aid discovery.
    @MainActor
    func updateBroadcastInterval(forPeerCount peerCount: Int) {
        let newInterval: TimeInterval

        if peerCount > 10 {
            // Scale linearly: 10 peers -> 2s, 20 peers -> 8s, capped at max
            let scale = min(1.0, Double(peerCount - 10) / 10.0)
            newInterval = Self.baseBroadcastInterval
                + scale * (Self.maxBroadcastInterval - Self.baseBroadcastInterval)
        } else {
            newInterval = Self.baseBroadcastInterval
        }

        // Only update if the interval actually changed
        guard abs(newInterval - currentBroadcastInterval) > 0.5 else { return }
        currentBroadcastInterval = newInterval
        logger.info("Beacon interval adjusted to \(newInterval, format: .fixed(precision: 1))s for \(peerCount) peers")

        // The broadcast Task loop reads currentBroadcastInterval each iteration,
        // so the new interval takes effect on the next cycle automatically.
    }

    // MARK: - Receiving

    /// Handle a beacon payload received from the mesh.
    /// Call this from the mesh router's local delivery path.
    func handleBeacon(_ data: Data) {
        // Verify magic header.
        guard data.count > Self.beaconMagic.count else { return }
        let magic = Array(data.prefix(Self.beaconMagic.count))
        guard magic == Self.beaconMagic else { return }

        let jsonData = data.dropFirst(Self.beaconMagic.count)

        do {
            var beacon = try JSONDecoder().decode(BeaconInfo.self, from: Data(jsonData))

            // Ignore our own beacons.
            if beacon.id == localID { return }

            // Identity, if claimed, must hold up before anything else reads
            // it. A fingerprint nobody checks is worth nothing: it would let
            // a peer wear someone else's identity, or a relay swap the
            // agreement key and read every position routed through it.
            if let signingPublicKey = beacon.signingPublicKey {
                guard let claimed = beacon.fingerprint,
                      let signature = beacon.identitySignature,
                      let agreementPublicKey = beacon.agreementPublicKey,
                      let verified = BeaconIdentity.verifyAttestation(
                          routingID: beacon.id,
                          claimedFingerprint: claimed,
                          signingPublicKey: signingPublicKey,
                          agreementPublicKey: agreementPublicKey,
                          signature: signature
                      )
                else {
                    logger.error("Dropped beacon with unverifiable identity from \(beacon.id, privacy: .public)")
                    return
                }
                beacon.fingerprint = verified
            } else if beacon.fingerprint != nil {
                // A fingerprint with no signing key behind it is a claim, not
                // an identity. Drop it rather than store something a block
                // could later be keyed to.
                logger.error("Dropped beacon claiming a fingerprint with no signing key: \(beacon.id, privacy: .public)")
                return
            }

            // Drop blocked peers entirely — presence, topology and position.
            if blockedIDsProvider?().contains(beacon.id) == true {
                knownNodes.removeValue(forKey: beacon.id)
                logger.trace("Dropped beacon from blocked peer \(beacon.id, privacy: .public)")
                return
            }

            // Same person, new install, new callsign. The routing UUID is
            // fresh so the checks above let it through; the identity is the
            // one the user blocked, so it stays blocked and the new UUID is
            // reported for persistence.
            if let fingerprint = beacon.fingerprint,
               blockedFingerprintsProvider?().contains(fingerprint) == true {
                knownNodes.removeValue(forKey: beacon.id)
                logger.info("Blocked identity reappeared under a new routing ID: \(beacon.id, privacy: .public)")
                onBlockedIdentityRekeyed?(beacon.id, fingerprint, beacon.name)
                return
            }

            // The position, if there is one addressed to us. Everything else
            // in the beacon is public; this is the only part that was sealed.
            beacon.latitude = nil
            beacon.longitude = nil
            if let sealed = beacon.sealedPositions?[localRoutingID],
               let senderKey = beacon.agreementPublicKey {
                let context = Self.positionContext(
                    senderID: beacon.id,
                    recipientID: localRoutingID
                )
                // Both keys are tried because a beacon this device seeded for
                // a simulated peer may predate `identity` being wired in.
                for opener in [identity, seedIdentity].compactMap({ $0 }) {
                    if let coordinate = opener.openCoordinate(
                        sealed,
                        fromPeerAgreementKey: senderKey,
                        context: context
                    ) {
                        beacon.latitude = coordinate.latitude
                        beacon.longitude = coordinate.longitude
                        break
                    }
                }
            }

            // Update lastSeen to local time.
            beacon.lastSeen = Date()

            // If we already know this node, only update if the incoming beacon
            // has equal or fewer hops (shorter path) or is newer.
            if let existing = knownNodes[beacon.id] {
                if beacon.hopCount <= existing.hopCount || beacon.timestamp > existing.timestamp {
                    knownNodes[beacon.id] = beacon
                }
            } else {
                knownNodes[beacon.id] = beacon
                logger.info("Discovered mesh node: \(beacon.name, privacy: .public) hops=\(beacon.hopCount) channels=\(beacon.channels.count) neighbors=\(beacon.neighborIDs.count)")
            }

            // Publish neighbor topology for MeshIntelligence to consume
            if !beacon.neighborIDs.isEmpty {
                NotificationCenter.default.post(
                    name: .meshTopologyUpdate,
                    object: nil,
                    userInfo: [
                        "peerID": beacon.id,
                        "neighborIDs": beacon.neighborIDs
                    ]
                )
            }

            // Publish pheromone trail data for MeshIntelligence to merge
            if let trails = beacon.pheromoneTrails, !trails.isEmpty {
                NotificationCenter.default.post(
                    name: .meshPheromoneUpdate,
                    object: nil,
                    userInfo: [
                        "neighborID": beacon.id,
                        "trails": trails
                    ]
                )
            }
        } catch {
            logger.debug("Failed to decode beacon: \(error.localizedDescription)")
        }
    }

    // MARK: - Pruning

    /// Remove nodes that haven't been seen within the stale threshold.
    /// Drop these nodes now rather than waiting for them to go stale.
    /// Used when Demo Mode's simulated peers leave.
    func forget(ids: Set<String>) {
        for id in ids { knownNodes.removeValue(forKey: id) }
    }

    func pruneStale() {
        let cutoff = Date().addingTimeInterval(-Self.staleThreshold)
        let staleIDs = knownNodes.filter { $0.value.lastSeen < cutoff }.map(\.key)

        for id in staleIDs {
            if let node = knownNodes.removeValue(forKey: id) {
                logger.info("Pruned stale node: \(node.name, privacy: .public) (\(id, privacy: .public))")
            }
        }
    }

    // MARK: - Encoding

    /// Encode a beacon into a payload suitable for mesh broadcast.
    ///
    /// This is where the position stops being a coordinate and becomes a set
    /// of sealed boxes. `beacon.latitude`/`longitude` are consumed here and
    /// never encoded; what goes out is one AES-GCM box per known, non-blocked
    /// peer whose agreement key we have learned from their own beacon.
    func encodeBeacon(_ beacon: BeaconInfo) -> Data? {
        var wire = beacon
        let isOurs = beacon.id == localRoutingID

        // Only our own beacon may claim our identity.
        if isOurs, let identity {
            wire.signingPublicKey = identity.signingPublicKey
            wire.fingerprint = identity.fingerprint
            wire.agreementPublicKey = identity.agreementPublicKey
            wire.identitySignature = identity.attest(routingID: beacon.id)
        }

        if let latitude = beacon.latitude, let longitude = beacon.longitude,
           beacon.sealedPositions == nil {
            let sealer = isOurs ? (identity ?? seedIdentity) : seedIdentity
            wire.agreementPublicKey = sealer.agreementPublicKey
            let sealed = sealPosition(
                latitude: latitude,
                longitude: longitude,
                senderID: beacon.id,
                using: sealer
            )
            wire.sealedPositions = sealed.isEmpty ? nil : sealed
        }

        wire.latitude = nil
        wire.longitude = nil

        guard let json = try? JSONEncoder().encode(wire) else { return nil }
        var payload = Data(Self.beaconMagic)
        payload.append(json)
        return payload
    }

    /// The recipients of a position and the box each one gets.
    ///
    /// A blocked peer is excluded twice over: they get no entry, and the
    /// entries they can see are sealed to keys they do not hold. The second
    /// exclusion is the one that matters, because a relayed packet passes
    /// through nodes that were never on the send list.
    private func sealPosition(
        latitude: Double,
        longitude: Double,
        senderID: String,
        using sealer: BeaconIdentity
    ) -> [String: Data] {
        let blockedIDs = blockedIDsProvider?() ?? []
        let blockedFingerprints = blockedFingerprintsProvider?() ?? []

        // A blocked peer that advertises someone else's agreement key would
        // otherwise be handed a box sealed to a key it holds. Any key a
        // blocked node claims is disqualified outright, for everyone.
        var poisonedKeys: Set<Data> = []
        for node in knownNodes.values {
            guard let key = node.agreementPublicKey else { continue }
            let isBlocked = blockedIDs.contains(node.id)
                || (node.fingerprint.map { blockedFingerprints.contains($0) } ?? false)
            if isBlocked { poisonedKeys.insert(key) }
        }

        var recipients: [(id: String, key: Data)] = []

        // Ourselves, but only for a beacon attributed to someone else: that
        // is the Demo Mode / seeding / test round trip, where this device
        // both writes and reads the packet. Our own broadcast has no reason
        // to carry an entry addressed to us.
        if senderID != localRoutingID {
            recipients.append((localRoutingID, (identity ?? seedIdentity).agreementPublicKey))
        }

        let candidates = knownNodes.values
            .filter { node in
                node.id != senderID
                    && node.id != localRoutingID
                    && !blockedIDs.contains(node.id)
                    && !(node.fingerprint.map { blockedFingerprints.contains($0) } ?? false)
            }
            .sorted { a, b in
                if a.hopCount != b.hopCount { return a.hopCount < b.hopCount }
                return a.id < b.id
            }
            .prefix(Self.maxSealedRecipients)

        for node in candidates {
            guard let key = node.agreementPublicKey, !poisonedKeys.contains(key) else { continue }
            recipients.append((node.id, key))
        }

        var sealed: [String: Data] = [:]
        for recipient in recipients {
            guard let box = sealer.sealCoordinate(
                latitude: latitude,
                longitude: longitude,
                forPeerAgreementKey: recipient.key,
                context: Self.positionContext(senderID: senderID, recipientID: recipient.id)
            ) else { continue }
            sealed[recipient.id] = box
        }
        return sealed
    }

    /// Additional authenticated data for a sealed position: who sealed it and
    /// who it is for. Binding both means an entry cannot be lifted out of one
    /// beacon and replayed as another node's position.
    static func positionContext(senderID: String, recipientID: String) -> Data {
        Data("chirp.beacon.position.v1|\(senderID)|\(recipientID)".utf8)
    }

    // MARK: - Identity resolution

    /// Canonical identity of a peer known by display name.
    ///
    /// The UI knows peers by callsign; blocking must key on the routing UUID
    /// (what the router enforces) and on the fingerprint (what survives a
    /// rename). `fingerprint` is nil when that peer's beacons carried no
    /// attestation, which is every peer still on the pre-encryption build.
    ///
    /// On a duplicate name the most recently heard node wins: two people can
    /// pick the same callsign, and refusing to resolve would mean the block
    /// button silently does nothing.
    func identity(forPeerNamed name: String) -> (routingID: String, fingerprint: String?)? {
        let matches = knownNodes.values.filter { $0.name == name }
        guard let node = matches.max(by: { $0.lastSeen < $1.lastSeen }) else { return nil }
        return (node.id, node.fingerprint)
    }

    /// Canonical identity of a peer known by routing UUID.
    func identity(forRoutingID id: String) -> (routingID: String, fingerprint: String?)? {
        guard let node = knownNodes[id] else { return nil }
        return (node.id, node.fingerprint)
    }

    /// Verified fingerprints currently on the mesh, keyed by routing UUID.
    /// Only verified identities are ever stored, so every value here has had
    /// its signature checked.
    var knownFingerprints: [String: String] {
        knownNodes.compactMapValues { $0.fingerprint }
    }

    // MARK: - Private

    private func broadcastBeacon() {
        guard let localID, let localName else { return }

        // Battery level cached from main actor context
        let batteryLevel: Float = cachedBatteryLevel

        // Include IDs of our direct peers so remote nodes can build topology
        let neighborIDs = Array(directPeers.map(\.id).prefix(20)) // cap to keep payload small

        // Gather pheromone trail summary (async, but we fire-and-forget with cached data)
        // The pheromone data is fetched asynchronously; if unavailable this cycle, it will
        // be included in the next beacon.
        let router = pheromoneRouter
        Task { @MainActor [weak self] in
            guard let self else { return }
            let trails = await router?.pheromoneSummaryForBeacon()
            self.cachedPheromoneTrails = trails?.isEmpty == false ? trails : nil
        }

        // The one place this device's position can enter a packet. `nil`
        // unless the user is inside a live manual check-in, and nil is the
        // default: no check-in, no coordinate, nothing to strip later.
        // It leaves this object only through `encodeBeacon`, which seals it
        // per recipient — it is never encoded as a coordinate.
        let shared = locationProvider?()

        let beacon = BeaconInfo(
            id: localID,
            name: localName,
            channels: localChannels,
            hopCount: 0,
            batteryLevel: batteryLevel,
            timestamp: Date(),
            lastSeen: Date(),
            neighborIDs: neighborIDs,
            latitude: shared?.latitude,
            longitude: shared?.longitude,
            pheromoneTrails: cachedPheromoneTrails
        )

        guard let payload = encodeBeacon(beacon) else {
            logger.error("Failed to encode beacon")
            return
        }

        // Post the payload for AppState to wrap via MeshRouter.createPacket.
        // The packet must be created by the router — it stamps the monotonic
        // sequence number and pre-registers the packetID. A beacon built here
        // with a constant sequence once poisoned the origin's replay
        // high-water mark and got every later packet from this device dropped.
        NotificationCenter.default.post(
            name: .meshBeaconBroadcast,
            object: nil,
            userInfo: ["payload": payload]
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when a mesh beacon payload is ready for mesh broadcast.
    /// The `userInfo` dictionary contains key `"payload"` with the encoded
    /// BeaconInfo `Data`; the subscriber wraps it in a MeshPacket via
    /// `MeshRouter.createPacket` (which stamps the sequence number).
    static let meshBeaconBroadcast = Notification.Name("com.chirpchirp.meshBeaconBroadcast")

    /// Posted when a beacon carries neighbor topology information.
    /// `userInfo` contains `"peerID"` (String) and `"neighborIDs"` ([String]).
    static let meshTopologyUpdate = Notification.Name("com.chirpchirp.meshTopologyUpdate")

    /// Posted when a beacon carries pheromone trail data.
    /// `userInfo` contains `"neighborID"` (String) and `"trails"` ([String: Double]).
    static let meshPheromoneUpdate = Notification.Name("com.chirpchirp.meshPheromoneUpdate")
}

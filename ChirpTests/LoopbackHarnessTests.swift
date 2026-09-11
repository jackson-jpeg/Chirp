import XCTest
import AVFoundation
@testable import Chirp

// MARK: - In-memory transport

/// The wire between loopback nodes: mirrors what `MultipeerTransport` does —
/// `router.createPacket` → serialize → (peer deserializes → `handleIncoming`)
/// — with an in-memory delivery in place of `MCSession.send`. Serialization
/// round-trips on every hop, so the packet codec is under test too, and every
/// routing decision (dedup, replay, TTL, forward) is made by the production
/// `MeshRouter`, not simulated here.
final class InMemoryTransport: @unchecked Sendable {
    let nodeName: String
    private let router: MeshRouter
    /// Set once by `connect(_:)` before any traffic flows; never mutated after.
    private(set) var links: [InMemoryTransport] = []

    init(nodeName: String, router: MeshRouter) {
        self.nodeName = nodeName
        self.router = router
    }

    /// Full mesh: every transport is linked to every other.
    static func connect(_ transports: [InMemoryTransport]) {
        for transport in transports {
            transport.links = transports.filter { $0 !== transport }
        }
    }

    /// Mirror of the MCSessionDelegate receive path: deserialize, hand to the
    /// router, and let the router decide local delivery vs. forwarding.
    func receive(_ serialized: Data, fromPeer: String) {
        guard let packet = MeshPacket.deserialize(serialized) else { return }
        let router = self.router
        Task { await router.handleIncoming(packet: packet, fromPeer: fromPeer) }
    }

    private func broadcast(type: MeshPacket.PacketType, payload: Data, channelID: String?) {
        let targets = links
        guard !targets.isEmpty else { return }
        let router = self.router
        let name = self.nodeName
        Task {
            let packet = await router.createPacket(
                type: type,
                payload: payload,
                channelID: channelID ?? ""
            )
            let serialized = packet.serialize()
            for peer in targets {
                peer.receive(serialized, fromPeer: name)
            }
        }
    }

    /// Mirror of `MultipeerTransport.sendControlData` — pre-encoded control
    /// payloads (TXT!/ACK!/…) wrapped into a mesh packet.
    func sendControlData(_ data: Data, channelID: String? = nil) throws {
        broadcast(type: .control, payload: data, channelID: channelID)
    }

    /// Mirror of `MultipeerTransport.forwardPacket` — relay to everyone except
    /// the peer the packet arrived from.
    func forwardPacket(_ serialized: Data, excludePeer: String) {
        for peer in links where peer.nodeName != excludePeer {
            peer.receive(serialized, fromPeer: nodeName)
        }
    }
}

extension InMemoryTransport: PTTTransport {
    func sendAudio(_ data: Data, channelID: String?) throws {
        broadcast(type: .audio, payload: data, channelID: channelID)
    }

    func sendControl(_ message: FloorControlMessage, channelID: String?) throws {
        let payload = try MeshCodable.encoder.encode(message)
        broadcast(type: .control, payload: payload, channelID: channelID)
    }
}

// MARK: - Loopback node

/// One "device": the same service graph AppState builds, wired the same way,
/// minus the pieces that need hardware (AVAudioEngine capture/playback,
/// MCSession) — each replaced at its narrowest seam, never re-implemented.
///
/// Not a literal second AppState: AppState resolves its peer identity from
/// `UserDefaults.standard`, so two in-process instances would share one peer ID
/// and each router would drop the other's packets as its own echoes. Every
/// node here gets its own identity; delivery dispatch is the production
/// `MeshDelivery.makeLocalDeliveryHandler`, extracted from AppState verbatim.
@MainActor
final class LoopbackNode {
    let name: String
    let originID: UUID
    let router: MeshRouter
    let audioEngine: AudioEngine
    let floorSession: FloorSession
    let pttEngine: PTTEngine
    let channelManager: ChannelManager
    let textMessageService: TextMessageService
    let fileTransferService: FileTransferService
    let meshBeacon: MeshBeacon
    let pheromoneRouter: PheromoneRouter
    let peerTracker: PeerTracker
    let meshIntelligence: MeshIntelligence
    let transport: InMemoryTransport

    private init(name: String) throws {
        self.name = name
        let originID = UUID()
        self.originID = originID
        self.router = MeshRouter(localPeerID: originID)

        self.audioEngine = AudioEngine()
        // Codec + jitter buffer only — no AVAudioEngine, no audio session.
        try audioEngine.setupForLoopbackTesting()

        self.floorSession = FloorSession(localPeerID: originID.uuidString, localPeerName: name)
        self.pttEngine = PTTEngine(
            audioEngine: audioEngine,
            floorSession: floorSession,
            localPeerID: originID.uuidString
        )
        self.channelManager = ChannelManager()
        self.textMessageService = TextMessageService()
        self.fileTransferService = FileTransferService()
        self.meshBeacon = MeshBeacon()
        self.pheromoneRouter = PheromoneRouter()
        self.peerTracker = PeerTracker()
        self.meshIntelligence = MeshIntelligence()
        self.transport = InMemoryTransport(nodeName: name, router: router)

        // The same wiring AppState performs, against the in-memory transport.
        pttEngine.multipeerTransport = transport
        // setupCallbacks() rather than start(): start() also configures the
        // hardware audio engine, which a test process doesn't have.
        pttEngine.setupCallbacks()

        pheromoneRouter.configure(
            meshIntelligence: meshIntelligence,
            localPeerID: originID.uuidString,
            localPeerName: name
        )

        let transport = self.transport
        textMessageService.onSendPacket = { payload, channelID in
            try? transport.sendControlData(payload, channelID: channelID)
        }
        pheromoneRouter.onSendPacket = { payload, channelID in
            try? transport.sendControlData(payload, channelID: channelID)
        }
        fileTransferService.onSendPacket = { payload, channelID in
            try? transport.sendControlData(payload, channelID: channelID)
        }

        let channelManager = self.channelManager
        textMessageService.channelCryptoProvider = { channelID in
            channelManager.getChannelCrypto(for: channelID)
        }
        fileTransferService.channelCryptoProvider = { channelID in
            channelManager.getChannelCrypto(for: channelID)
        }
        textMessageService.epochProvider = { channelID in
            channelManager.recordMessageAndGetEpoch(for: channelID)
        }
        textMessageService.currentEpochProvider = { channelID in
            channelManager.currentEpoch(for: channelID)
        }
    }

    static func make(name: String) async throws -> LoopbackNode {
        let node = try LoopbackNode(name: name)
        let transport = node.transport
        let handler = MeshDelivery.makeLocalDeliveryHandler(
            audioEngine: node.audioEngine,
            floorSession: node.floorSession,
            channelManager: node.channelManager,
            peerTracker: node.peerTracker,
            textMessageService: node.textMessageService,
            fileTransferService: node.fileTransferService,
            meshBeacon: node.meshBeacon,
            pheromoneRouter: node.pheromoneRouter,
            notifyMessage: { _, _, _ in }
        )
        await node.router.setCallbacks(
            onLocalDelivery: handler,
            onForward: { packet, excludePeer in
                transport.forwardPacket(packet.serialize(), excludePeer: excludePeer)
            }
        )
        return node
    }
}

// MARK: - Sample collection

/// Thread-safe accumulator for far-end PCM: `onDecodedPCM` fires on the audio
/// engine's playback queue while the test reads from the main actor.
final class SampleSink: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        lock.lock()
        storage.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: frames))
        lock.unlock()
    }

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

// MARK: - Tests

/// The permanent, hardware-free proof that the app's peer-to-peer paths work:
/// audio from the capture seam of one node emerges from the playback seam of
/// another, and text crosses the mesh with delivery acknowledged — all through
/// the production codec, router, dispatcher, and services.
final class LoopbackHarnessTests: XCTestCase {

    /// Poll a main-actor condition, yielding so delivery tasks can run.
    @MainActor
    private func waitFor(
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// Fraction of the signal's energy at `frequency` — 1.0 for a pure tone,
    /// near 0 for noise or silence. Quadrature projection, so it is invariant
    /// to phase and to where in the stream playout started; a lag search
    /// would measure the same thing less directly.
    private func toneCorrelation(
        _ samples: [Float],
        frequency: Double,
        sampleRate: Double
    ) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sinAcc = 0.0, cosAcc = 0.0, energy = 0.0
        for (index, sample) in samples.enumerated() {
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            let value = Double(sample)
            sinAcc += value * sin(phase)
            cosAcc += value * cos(phase)
            energy += value * value
        }
        let count = Double(samples.count)
        let toneAmplitude = sqrt(sinAcc * sinAcc + cosAcc * cosAcc) / (count / 2)
        let rms = sqrt(energy / count)
        guard rms > 0 else { return 0 }
        return toneAmplitude / (rms * sqrt(2))
    }

    // MARK: Audio

    /// A 440 Hz sine injected at node A's capture seam (48 kHz float, the
    /// phone-mic shape, so the real sample-rate converter runs) must emerge
    /// from node B's playback seam still recognizably a 440 Hz sine, having
    /// crossed: capture → converter → Opus encode → AudioPacket → mesh packet
    /// → serialize → wire → deserialize → router → delivery dispatch → Opus
    /// decode → jitter buffer → playout.
    @MainActor
    func testSineToneCrossesTheMeshToTheFarEnd() async throws {
        let nodeA = try await LoopbackNode.make(name: "LoopA")
        let nodeB = try await LoopbackNode.make(name: "LoopB")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        let sink = SampleSink()
        nodeB.audioEngine.onDecodedPCM = { buffer in
            sink.append(buffer)
        }

        // 1.5 s of 440 Hz at 48 kHz, injected in tap-sized chunks.
        let sampleRate = 48_000.0
        let chunkFrames = 4_800
        let chunkCount = 15
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            XCTFail("Could not build 48 kHz capture format")
            return
        }

        for chunk in 0..<chunkCount {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(chunkFrames)
            ), let data = buffer.floatChannelData else {
                XCTFail("Could not allocate capture buffer")
                return
            }
            buffer.frameLength = AVAudioFrameCount(chunkFrames)
            for frame in 0..<chunkFrames {
                let t = Double(chunk * chunkFrames + frame) / sampleRate
                data[0][frame] = Float(sin(2 * .pi * 440 * t)) * 0.5
            }
            let time = AVAudioTime(
                sampleTime: AVAudioFramePosition(chunk * chunkFrames),
                atRate: sampleRate
            )
            guard let captured = AudioEngine.CapturedFrames(copying: buffer, at: time) else {
                XCTFail("CapturedFrames rejected the injected buffer")
                return
            }
            nodeA.audioEngine.injectCapturedFramesForTesting(captured)
            // Real capture delivers a tap callback every 100 ms, and the far
            // end drains at the same real-time rate. Injecting the whole
            // signal in one instant would overflow the 200 ms jitter buffer
            // by design (it drops the oldest frames), which tests the buffer's
            // cap rather than the chain. Pace like a microphone.
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // 1.5 s in = 24 000 samples out at 16 kHz; the playout timer drains
        // 320 samples per 20 ms tick, so real time must pass. Require at
        // least 1 s of far-end audio.
        let gotAudio = await waitFor(timeout: 20) { sink.count >= 16_000 }
        XCTAssertTrue(
            gotAudio,
            "Far end produced \(sink.count) samples — the audio chain went silent before B's playout seam"
        )

        // Skip the first 100 ms: codec warm-up and any concealment at start.
        let all = sink.samples
        guard all.count > 1_600 else { return }
        let samples = Array(all.dropFirst(1_600))

        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
        XCTAssertGreaterThan(rms, 0.05, "Far-end audio is near-silent (rms \(rms))")

        let correlation = toneCorrelation(samples, frequency: 440, sampleRate: 16_000)
        XCTAssertGreaterThan(
            correlation,
            0.75,
            "Far-end signal does not correlate with the injected 440 Hz tone (correlation \(correlation))"
        )
    }

    // MARK: Messaging

    /// A direct text on an open channel must arrive at B, and the delivery ACK
    /// must make it back to A and flip the message's status to `.delivered`.
    @MainActor
    func testDirectTextArrivesAndACKFlipsDeliveryStatus() async throws {
        let nodeA = try await LoopbackNode.make(name: "TextA")
        let nodeB = try await LoopbackNode.make(name: "TextB")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        let channelID = "loopback-open-\(UUID().uuidString)"
        let body = "direct text \(UUID().uuidString.prefix(8))"

        nodeA.textMessageService.send(
            text: body,
            channelID: channelID,
            senderID: nodeA.originID.uuidString,
            senderName: "Alpha"
        )

        let arrived = await waitFor {
            nodeB.textMessageService.messagesByChannel[channelID]?.contains { $0.text == body } ?? false
        }
        XCTAssertTrue(arrived, "B never received the direct text")

        let acked = await waitFor {
            nodeA.textMessageService.messagesByChannel[channelID]?
                .first { $0.text == body }?.deliveryStatus == .delivered
        }
        XCTAssertTrue(
            acked,
            "A's message never reached .delivered — the text-level ACK did not make it back"
        )
    }

    /// A message on a locked channel must reach both other members of a
    /// three-node mesh, with B and C joined via A's invite code — encryption,
    /// invite-code key derivation, and encrypted-payload dispatch all live.
    ///
    /// Note: ChannelKeyStore is the process-wide Keychain, shared by all three
    /// in-process nodes. That weakens the key-isolation aspect (a node could
    /// in principle read a seed it was never invited to), but each node's
    /// crypto is still resolved through its own ChannelManager cache, which is
    /// populated only by createChannel/joinWithInviteCode — the paths under test.
    @MainActor
    func testLockedChannelMessageReachesInvitedPeers() async throws {
        let nodeA = try await LoopbackNode.make(name: "LockA")
        let nodeB = try await LoopbackNode.make(name: "LockB")
        let nodeC = try await LoopbackNode.make(name: "LockC")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport, nodeC.transport])

        let channel = nodeA.channelManager.createChannel(
            name: "Locked Loopback",
            accessMode: .locked,
            ownerID: nodeA.originID.uuidString
        )
        guard let inviteCode = channel.inviteCode else {
            XCTFail("Locked channel was created without an invite code")
            return
        }

        XCTAssertTrue(
            nodeB.channelManager.joinWithInviteCode(inviteCode),
            "B could not join with A's invite code"
        )
        XCTAssertTrue(
            nodeC.channelManager.joinWithInviteCode(inviteCode),
            "C could not join with A's invite code"
        )

        let body = "locked text \(UUID().uuidString.prefix(8))"
        nodeA.textMessageService.send(
            text: body,
            channelID: channel.id,
            senderID: nodeA.originID.uuidString,
            senderName: "Alpha"
        )

        let bGotIt = await waitFor {
            nodeB.textMessageService.messagesByChannel[channel.id]?.contains { $0.text == body } ?? false
        }
        XCTAssertTrue(bGotIt, "B never received the locked-channel message")

        let cGotIt = await waitFor {
            nodeC.textMessageService.messagesByChannel[channel.id]?.contains { $0.text == body } ?? false
        }
        XCTAssertTrue(cGotIt, "C never received the locked-channel message")
    }

    /// A file sent on a LOCKED channel must reach the invited peer. Encrypted
    /// file traffic (FIL!/FLC!/FNK!) has no plaintext magic, so it rides
    /// MeshDelivery's encrypted fallback — which for a long time handed such
    /// payloads only to the text service, silently dropping every locked-
    /// channel file transfer. This drives send -> encrypt -> mesh -> fallback
    /// dispatch -> decrypt -> reassemble -> SHA verify end to end.
    @MainActor
    func testLockedChannelFileTransferReachesInvitedPeer() async throws {
        let nodeA = try await LoopbackNode.make(name: "FileA")
        let nodeB = try await LoopbackNode.make(name: "FileB")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        let channel = nodeA.channelManager.createChannel(
            name: "Locked File Loopback",
            accessMode: .locked,
            ownerID: nodeA.originID.uuidString
        )
        guard let inviteCode = channel.inviteCode else {
            XCTFail("Locked channel was created without an invite code")
            return
        }
        XCTAssertTrue(
            nodeB.channelManager.joinWithInviteCode(inviteCode),
            "B could not join with A's invite code"
        )

        // Multi-chunk on purpose: metadata (FIL!) and chunks (FLC!) take the
        // same encrypted fallback path, and completion requires all of them.
        let fileName = "loopback-\(UUID().uuidString.prefix(8)).bin"
        let fileData = Data((0..<40_000).map { UInt8(truncatingIfNeeded: $0) })
        nodeA.fileTransferService.sendFile(
            fileData,
            fileName: fileName,
            mimeType: "application/octet-stream",
            channelID: channel.id,
            senderID: nodeA.originID.uuidString,
            senderName: "FileA"
        )

        let bCompleted = await waitFor {
            nodeB.fileTransferService.activeTransfers.values.contains {
                !$0.isOutbound && $0.fileName == fileName && $0.isComplete
            }
        }
        XCTAssertTrue(
            bCompleted,
            "B never completed the locked-channel file transfer — encrypted FIL!/FLC! payloads are not reaching the file service"
        )
    }

    /// A presence beacon from one node must land in the other node's
    /// `knownNodes` — the source of the HomeView mesh-node list and the
    /// MeshIntelligence topology feed. The broadcaster shipped live while
    /// nothing dispatched received "BCN!" payloads to handleBeacon, so every
    /// device announced itself into the void. This pins the dispatch case.
    @MainActor
    func testBeaconPopulatesPeerNodeList() async throws {
        let nodeA = try await LoopbackNode.make(name: "BeaconA")
        let nodeB = try await LoopbackNode.make(name: "BeaconB")
        InMemoryTransport.connect([nodeA.transport, nodeB.transport])

        let beacon = MeshBeacon.BeaconInfo(
            id: nodeA.originID.uuidString,
            name: "BeaconA",
            channels: [],
            hopCount: 0,
            batteryLevel: 1.0,
            timestamp: Date(),
            lastSeen: Date(),
            neighborIDs: []
        )
        guard let payload = nodeA.meshBeacon.encodeBeacon(beacon) else {
            XCTFail("encodeBeacon returned nil")
            return
        }
        // Broadcast beacons ride control packets with an empty channelID,
        // exactly as AppState's .meshBeaconBroadcast observer sends them.
        try nodeA.transport.sendControlData(payload, channelID: "")

        let discovered = await waitFor {
            nodeB.meshBeacon.knownNodes[nodeA.originID.uuidString] != nil
        }
        XCTAssertTrue(
            discovered,
            "B never learned of A from its beacon — BCN! payloads are not reaching MeshBeacon.handleBeacon"
        )
    }
}

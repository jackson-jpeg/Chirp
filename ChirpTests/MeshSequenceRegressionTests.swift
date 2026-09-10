import XCTest
@testable import Chirp

/// Regression tests for the bug that silenced all mesh traffic between real
/// devices: every sender stamped mesh `sequenceNumber: 0`, and the router's
/// replay check rejected any packet whose sequence was <= the origin's
/// high-water mark. The first packet from an origin set the mark to 0; every
/// subsequent packet from that origin (audio, floor control, text, beacons)
/// was then dropped as a "replay" for 300 seconds.
///
/// The fix has two halves, and these tests pin both:
///   1. `MeshRouter.createPacket` stamps a monotonic per-type sequence
///      centrally — callers can no longer send an eternal 0.
///   2. `handleIncoming` uses a per-(origin, type) anti-replay *window*:
///      only packets far behind the high-water mark are rejected. Exact
///      duplicates are already caught by packetID dedup, and mesh paths /
///      unreliable delivery legitimately reorder distinct packets.
final class MeshSequenceRegressionTests: XCTestCase {

    private func makePacket(
        type: MeshPacket.PacketType = .audio,
        originID: UUID,
        sequenceNumber: UInt32,
        payload: Data = Data([0x01])
    ) -> MeshPacket {
        MeshPacket(
            type: type,
            ttl: 4,
            originID: originID,
            packetID: UUID(),
            sequenceNumber: sequenceNumber,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )
    }

    // MARK: - The field bug, distilled

    /// Two distinct audio packets from the same origin, both sequence 0 —
    /// exactly what every sender produced at HEAD. Both must be delivered.
    /// At HEAD the second was rejected as a replay, which is why PTT audio
    /// died after the first packet from each phone.
    func testDistinctSeqZeroPacketsFromSameOriginAllDelivered() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        let first = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 0), fromPeer: "peer-1")
        let second = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 0), fromPeer: "peer-1")
        let third = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 0), fromPeer: "peer-1")

        XCTAssertTrue(first, "First packet from origin must be delivered")
        XCTAssertTrue(second, "Second distinct packet must be delivered — at HEAD it was dropped as a replay")
        XCTAssertTrue(third, "Every subsequent distinct packet must be delivered")
    }

    /// The end-to-end shape of the bug: a sender router creates a stream of
    /// packets the way MultipeerTransport actually does, a receiver router
    /// processes them. Every one must come out the other side.
    func testCreatedPacketStreamSurvivesReceivingRouter() async {
        let sender = MeshRouter(localPeerID: UUID())
        let receiver = MeshRouter(localPeerID: UUID())
        await receiver.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        var deliveredCount = 0
        for i in 0..<20 {
            let packet = await sender.createPacket(
                type: .audio,
                payload: Data([UInt8(i)]),
                channelID: ""
            )
            if await receiver.handleIncoming(packet: packet, fromPeer: "peer-1") {
                deliveredCount += 1
            }
        }
        XCTAssertEqual(deliveredCount, 20,
                       "All 20 packets of a PTT stream must be delivered; at HEAD only the first survived")
    }

    // MARK: - Central sequence stamping

    /// createPacket must stamp strictly increasing sequences per packet type.
    func testCreatePacketStampsMonotonicSequencePerType() async {
        let router = MeshRouter(localPeerID: UUID())

        let a1 = await router.createPacket(type: .audio, payload: Data([1]), channelID: "")
        let a2 = await router.createPacket(type: .audio, payload: Data([2]), channelID: "")
        let c1 = await router.createPacket(type: .control, payload: Data([3]), channelID: "")
        let c2 = await router.createPacket(type: .control, payload: Data([4]), channelID: "")
        let a3 = await router.createPacket(type: .audio, payload: Data([5]), channelID: "")

        XCTAssertGreaterThan(a2.sequenceNumber, a1.sequenceNumber)
        XCTAssertGreaterThan(a3.sequenceNumber, a2.sequenceNumber)
        XCTAssertGreaterThan(c2.sequenceNumber, c1.sequenceNumber)
        // Per-type counters are dense: interleaved control traffic must not
        // open gaps in the audio sequence space (gaps wider than the replay
        // window would get legitimate reordered packets dropped).
        XCTAssertEqual(a3.sequenceNumber, a2.sequenceNumber &+ 1)
        XCTAssertEqual(c2.sequenceNumber, c1.sequenceNumber &+ 1)
    }

    // MARK: - Windowed acceptance

    /// Distinct packets reordered within the window (unreliable delivery,
    /// divergent mesh paths) must still be delivered.
    func testReorderedPacketWithinWindowAccepted() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        let atTen = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 10), fromPeer: "peer-1")
        let atEight = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 8), fromPeer: "peer-1")

        XCTAssertTrue(atTen)
        XCTAssertTrue(atEight, "A distinct packet reordered a few sequences back is not a replay")
    }

    /// A packet far behind the origin's high-water mark is a stale replay
    /// and must still be rejected.
    func testStaleSequenceBeyondWindowRejected() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        let fresh = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 500), fromPeer: "peer-1")
        let stale = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 10), fromPeer: "peer-1")

        XCTAssertTrue(fresh)
        XCTAssertFalse(stale, "A sequence hundreds behind the high-water mark is a replay")
    }

    /// The high-water mark must not move backward when an older-but-in-window
    /// packet is accepted, otherwise a reordered packet would re-open the
    /// window for genuinely stale traffic.
    func testHighWaterMarkDoesNotRegress() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        _ = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 200), fromPeer: "peer-1")
        // In-window reordered packet — accepted, but must not lower the mark.
        _ = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 190), fromPeer: "peer-1")
        // Far behind 200: must still be judged against 200, not 190.
        let stale = await router.handleIncoming(
            packet: makePacket(originID: origin, sequenceNumber: 130), fromPeer: "peer-1")

        XCTAssertFalse(stale, "Accepting an in-window packet must not regress the high-water mark")
    }

    /// Audio and control track independent sequence spaces: a reliable
    /// control message must never be dropped because the unreliable audio
    /// stream from the same origin has raced far ahead.
    func testAudioAndControlSequenceSpacesAreIndependent() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        let audio = await router.handleIncoming(
            packet: makePacket(type: .audio, originID: origin, sequenceNumber: 5_000),
            fromPeer: "peer-1")
        let control = await router.handleIncoming(
            packet: makePacket(type: .control, originID: origin, sequenceNumber: 3),
            fromPeer: "peer-1")

        XCTAssertTrue(audio)
        XCTAssertTrue(control,
                      "Control sequence space must not be poisoned by the audio high-water mark")
    }

    /// An exact byte-for-byte replay (same packetID) is still rejected — the
    /// windowed sequence check does not weaken duplicate suppression.
    func testExactDuplicateStillRejectedUnderWindowedCheck() async {
        let origin = UUID()
        let router = MeshRouter(localPeerID: UUID())
        await router.setCallbacks(onLocalDelivery: { _ in }, onForward: { _, _ in })

        let packet = makePacket(originID: origin, sequenceNumber: 7)
        let first = await router.handleIncoming(packet: packet, fromPeer: "peer-1")
        let replay = await router.handleIncoming(packet: packet, fromPeer: "peer-2")

        XCTAssertTrue(first)
        XCTAssertFalse(replay, "Identical packetID must be deduplicated regardless of sequence")
    }
}

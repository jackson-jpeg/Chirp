import XCTest
@testable import Chirp

/// The text-service send policy (`MeshDelivery.makeTextSendHandler`) and the
/// channel-roster reconciliation that feeds it.
///
/// Two production bugs anchor these tests, both found on the two-simulator
/// harness: the live send used to be gated on the per-channel peer roster,
/// which is only ever populated for the *active* channel — so a message or
/// delivery ACK sent from any other channel was silently dropped with a live
/// transport sitting right there. And the roster used to remove disconnected
/// peers outright, so "known member, currently offline" — the store-and-forward
/// trigger — could never be true.
@MainActor
final class TextSendPolicyTests: XCTestCase {

    private final class Recorder {
        var liveSends: [(Data, String)] = []
        var queued: [StoreAndForwardRelay.PendingMessage] = []
    }

    private func makeHandler(
        recorder: Recorder,
        transportPeers: [ChirpPeer],
        channel: ChirpChannel?
    ) -> (Data, String) -> Void {
        MeshDelivery.makeTextSendHandler(
            sendControl: { payload, channelID in recorder.liveSends.append((payload, channelID)) },
            transportPeers: { transportPeers },
            channelLookup: { _ in channel },
            localPeerName: { "Raven-45" },
            enqueue: { recorder.queued.append($0) }
        )
    }

    /// Regression: a send on a channel with an EMPTY roster must still go out
    /// live when the transport has a connected peer. This is the exact shape
    /// of the two-sim failure — the receiver was active on another channel, so
    /// its ACK's channel had no roster entries, and the old roster gate ate it.
    func testSendsLiveWithConnectedTransportEvenWhenChannelRosterIsEmpty() {
        let recorder = Recorder()
        let channel = ChirpChannel(
            id: "CHAN-1", name: "Private Channel", peers: [],
            createdAt: Date(), accessMode: .locked, inviteCode: nil
        )
        let handler = makeHandler(
            recorder: recorder,
            transportPeers: [ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: true)],
            channel: channel
        )

        handler(Data("hello".utf8), "CHAN-1")

        XCTAssertEqual(recorder.liveSends.count, 1, "live send must not be gated on the channel roster")
        XCTAssertEqual(recorder.liveSends.first?.1, "CHAN-1")
        XCTAssertTrue(recorder.queued.isEmpty, "nothing known-offline, nothing to queue")
    }

    /// A completely unknown channel (lookup returns nil) must also send live.
    func testSendsLiveWhenChannelIsUnknown() {
        let recorder = Recorder()
        let handler = makeHandler(
            recorder: recorder,
            transportPeers: [ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: true)],
            channel: nil
        )

        handler(Data("hello".utf8), "CHAN-MYSTERY")

        XCTAssertEqual(recorder.liveSends.count, 1)
    }

    /// With no transport peers at all there is no live send, and every known
    /// channel member currently offline gets a store-and-forward copy.
    func testQueuesForOfflineMembersWhenTransportIsEmpty() {
        let recorder = Recorder()
        let channel = ChirpChannel(
            id: "CHAN-1", name: "Private Channel",
            peers: [
                ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: false),
                ChirpPeer(id: "peer-c", name: "Heron-12", isConnected: false),
            ],
            createdAt: Date(), accessMode: .locked, inviteCode: nil
        )
        let handler = makeHandler(recorder: recorder, transportPeers: [], channel: channel)

        handler(Data("later".utf8), "CHAN-1")

        XCTAssertTrue(recorder.liveSends.isEmpty, "no transport peers — nothing to live-send to")
        XCTAssertEqual(recorder.queued.count, 2)
        XCTAssertEqual(Set(recorder.queued.map(\.recipientPeerID)), ["peer-b", "peer-c"])
        XCTAssertEqual(recorder.queued.first?.channelID, "CHAN-1")
        XCTAssertEqual(recorder.queued.first?.senderName, "Raven-45")
    }

    /// Connected members do NOT get a queued copy — they got the live one.
    func testDoesNotQueueForConnectedMembers() {
        let recorder = Recorder()
        let channel = ChirpChannel(
            id: "CHAN-1", name: "Private Channel",
            peers: [
                ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: true),
                ChirpPeer(id: "peer-c", name: "Heron-12", isConnected: false),
            ],
            createdAt: Date(), accessMode: .locked, inviteCode: nil
        )
        let handler = makeHandler(
            recorder: recorder,
            transportPeers: [ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: true)],
            channel: channel
        )

        handler(Data("mixed".utf8), "CHAN-1")

        XCTAssertEqual(recorder.liveSends.count, 1)
        XCTAssertEqual(recorder.queued.map(\.recipientPeerID), ["peer-c"])
    }

    // MARK: - Roster reconciliation

    /// A member who drops off the mesh stays on the roster, marked offline —
    /// removing them (the old behavior) made store-and-forward unreachable,
    /// because nobody could ever be a known-but-offline member.
    func testReconcileKeepsDisconnectedMembersAsOffline() {
        let manager = ChannelManager()
        let channel = manager.createChannel(name: "Reconcile-\(UUID().uuidString)")
        defer { manager.deleteChannel(id: channel.id) }

        let falcon = ChirpPeer(id: "peer-b", name: "Falcon-58", isConnected: true)
        manager.reconcilePeers(channelID: channel.id, connected: [falcon])
        XCTAssertEqual(
            manager.channel(withID: channel.id)?.peers.filter(\.isConnected).map(\.id),
            ["peer-b"]
        )

        // Falcon drops off the mesh entirely.
        manager.reconcilePeers(channelID: channel.id, connected: [])
        let roster = manager.channel(withID: channel.id)?.peers ?? []
        XCTAssertEqual(roster.map(\.id), ["peer-b"], "known member must survive disconnection")
        XCTAssertEqual(roster.first?.isConnected, false)

        // And coming back marks them connected again without duplicating.
        manager.reconcilePeers(channelID: channel.id, connected: [falcon])
        let restored = manager.channel(withID: channel.id)?.peers ?? []
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.isConnected, true)
    }
}

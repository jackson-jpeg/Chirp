import Foundation
import Testing
@testable import ChirpCore

@Suite struct CatchUpTests {
    let camp = ChannelID.random(), other = ChannelID.random()

    final class Store {
        var s: CatchUpStore
        init(_ s: CatchUpStore = CatchUpStore()) { self.s = s }
        func hold(_ p: Packet, _ now: Date) -> Bool { s.hold(p, now: now) }
        func get(_ r: CatchUpRequest, by: PeerID, blocked: Set<PeerID> = [], _ now: Date) -> [Packet] {
            s.packets(for: r, requester: by, blocked: blocked, now: now)
        }
    }

    @Test func holdsOnlyTextLikeKindsOnceEach() {
        let st = Store()
        #expect(st.hold(packet(.text, seq: 1, channel: camp), t0))
        #expect(!st.hold(packet(.text, seq: 1, channel: camp), t0))           // same packet again
        #expect(!st.hold(packet(.audio, seq: 2, channel: camp), t0))
        #expect(!st.hold(packet(.ping, seq: 3, channel: camp), t0))
        #expect(!st.hold(packet(.text, seq: 4, channel: SendGate.demoChannel(1)), t0))
        #expect(st.hold(packet(.help, seq: 5, channel: camp), t0))
        #expect(st.s.count == 2)
    }

    /// Delivered in order, only for the channels asked, only after `since`,
    /// never the requester's own and never a blocked person's.
    @Test func handsBackWhatWasMissedInOrder() {
        let st = Store()
        let back = peer(9)
        _ = st.hold(packet(.text, from: peer(1), seq: 1, channel: camp), at(1))
        _ = st.hold(packet(.text, from: peer(2), seq: 1, channel: camp), at(2))
        _ = st.hold(packet(.text, from: back, seq: 1, channel: camp), at(3))
        _ = st.hold(packet(.text, from: peer(3), seq: 1, channel: other), at(4))
        _ = st.hold(packet(.text, from: peer(4), seq: 1, channel: camp), at(5))
        let req = CatchUpRequest(channels: [(camp, at(1.5))])
        let got = st.get(req, by: back, blocked: [peer(4)], at(6))
        #expect(got.map(\.origin) == [peer(2)])
        let all = st.get(CatchUpRequest(channels: [(camp, t0)]), by: back, at(6))
        #expect(all.map(\.origin) == [peer(1), peer(2), peer(4)])
    }

    @Test func capsPerOriginTotalAndAge() {
        let st = Store(CatchUpStore(maxTotal: 5, maxPerOrigin: 3))
        for s in 1...4 { _ = st.hold(packet(.text, from: peer(1), seq: UInt32(s), channel: camp), at(Double(s))) }
        #expect(st.s.count == 3)
        for s in 1...4 { _ = st.hold(packet(.text, from: peer(2), seq: UInt32(s), channel: camp), at(10 + Double(s))) }
        #expect(st.s.count == 5)
        let got = st.get(CatchUpRequest(channels: [(camp, t0)]), by: peer(9), at(20))
        #expect(got.first?.origin == peer(1) && got.first?.sequence == 3)   // oldest dropped first
        #expect(st.get(CatchUpRequest(channels: [(camp, t0)]), by: peer(9), at(20 + CatchUpStore.maxAge)).isEmpty)
    }

    @Test func requestsRoundTripAndAreBounded() {
        let req = CatchUpRequest(channels: [(camp, Date(timeIntervalSince1970: 1_800_000_000)), (other, t0)])
        #expect(CatchUpRequest.decode(req.encode()) == req)
        let big = CatchUpRequest(channels: (0..<40).map { _ in (ChannelID.random(), t0) })
        #expect(big.channels.count == CatchUpRequest.maxChannels)
        #expect(CatchUpRequest.decode(Data([1, 200])) == nil)
        #expect(CatchUpRequest.decode(req.encode() + Data([0])) == nil)
    }

    @Test func bundlesPackInOrderAndSplitAtTheLimit() throws {
        let packets = (1...10).map { packet(.text, seq: UInt32($0), channel: camp, payload: Data(count: 100)) }
        let bundles = CatchUpBundle.pack(packets, limit: 500)
        #expect(bundles.count > 1 && bundles.allSatisfy { $0.count <= 500 })
        let back = try bundles.flatMap { try #require(CatchUpBundle.unpack($0)) }
        #expect(back == packets)
        #expect(CatchUpBundle.unpack(Data([2, 0, 50, 1])) == nil)   // length runs past the end
        // A non-held kind smuggled into a bundle is skipped.
        let smuggled = CatchUpBundle.pack([packet(.ping, seq: 1)])
        #expect(CatchUpBundle.unpack(smuggled[0]) == [])
    }

    /// The point of bundling: a held packet is old, and the router's replay
    /// window would reject it once newer traffic from that sender was seen.
    /// Bundled packets are deduped by message ID in the ledger instead.
    @Test func heldTextsReachTheLedgerOnceEvenAfterNewerTraffic() throws {
        let alice = newIdentity()
        var ledger = TextLedger()
        let old = TextBody(sentAt: at(1), text: "where are you")
        let h = packet(.text, from: alice.peerID, seq: 1, channel: camp).sealedHeader
        let held = Packet(kind: .text, origin: alice.peerID, epoch: 1, sequence: 1, channel: camp,
                          payload: try old.signedPayload(by: alice, header: h))
        let router = RouterBox(local: peer(9))
        _ = router.accept(packet(.text, from: alice.peerID, seq: 200, channel: camp), now: at(100))
        #expect(router.accept(held, now: at(101)).dropped == .replay)
        let inner = try #require(CatchUpBundle.unpack(CatchUpBundle.pack([held])[0])?.first)
        let body = try #require(TextBody.verify(inner.payload, header: inner.sealedHeader, signingKey: alice.signingPublicKey))
        let first = ledger.receive(body, channel: camp, from: alice.peerID, senderName: "A", joined: [camp])
        let again = ledger.receive(body, channel: camp, from: alice.peerID, senderName: "A", joined: [camp])
        #expect(first == .stored && again == .duplicate)
    }
}

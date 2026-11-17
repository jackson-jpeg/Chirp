import Foundation
import Testing
@testable import ChirpCore

@Suite struct RouterTests {
    @Test func deliversNewPacketsAndRelaysThemWithOneMoreHop() {
        let r = RouterBox(local: peer(0))
        let d = r.accept(packet(.text, seq: 1), now: t0)
        #expect(d.deliver && d.dropped == nil)
        #expect(d.relay?.hops == 1 && d.relay?.ttl == 3)
    }

    @Test func dropsOwnEchoesDuplicatesAndBlockedOrigins() {
        let r = RouterBox(local: peer(0))
        #expect(r.accept(packet(from: peer(0), seq: 1), now: t0).dropped == .ownEcho)
        _ = r.accept(packet(seq: 5), now: t0)
        #expect(r.accept(packet(seq: 5), now: t0).dropped == .duplicate)
        // The same packet arriving relayed (different TTL and hops) is still a duplicate.
        #expect(r.accept(packet(seq: 5).relayed()!, now: t0).dropped == .duplicate)
        r.blocked = [peer(9)]
        let blocked = r.accept(packet(from: peer(9), seq: 1), now: t0)
        #expect(blocked.dropped == .blocked && !blocked.deliver && blocked.relay == nil)
    }

    @Test func acceptsReorderingInsideTheWindowAndRejectsReplaysBeyondIt() {
        let r = RouterBox(local: peer(0))
        _ = r.accept(packet(seq: 100), now: t0)
        #expect(r.accept(packet(seq: 99), now: t0).deliver)
        #expect(r.accept(packet(seq: UInt32(100 - Router.replayWindow + 1)), now: t0).deliver)
        #expect(r.accept(packet(seq: UInt32(100 - Router.replayWindow)), now: t0).dropped == .replay)
    }

    /// Audit claim H5 at the router: a sender that relaunched restarts its
    /// counter at 0. Under a new epoch that is a new stream, not a replay.
    @Test func aRelaunchedSenderIsANewStreamNotAReplay() {
        let r = RouterBox(local: peer(0))
        for s in 0..<500 { _ = r.accept(packet(epoch: 1, seq: UInt32(s)), now: t0) }
        #expect(r.accept(packet(epoch: 1, seq: 3), now: t0).dropped != nil)
        #expect(r.accept(packet(epoch: 2, seq: 0), now: t0).deliver)
        #expect(r.accept(packet(epoch: 2, seq: 1), now: t0).deliver)
    }

    @Test func sequenceWrapAroundIsForward() {
        let r = RouterBox(local: peer(0))
        _ = r.accept(packet(seq: UInt32.max - 1), now: t0)
        #expect(r.accept(packet(seq: UInt32.max), now: t0).deliver)
        #expect(r.accept(packet(seq: 0), now: t0).deliver)
        #expect(r.accept(packet(seq: 1), now: t0).deliver)
    }

    @Test func lastHopIsDeliveredButNotRelayed() {
        let r = RouterBox(local: peer(0))
        let last = Packet(kind: .audio, ttl: 1, hops: 1, origin: peer(1), epoch: 1, sequence: 1,
                          channel: .nearby, payload: Data())
        let d = r.accept(last, now: t0)
        #expect(d.deliver && d.relay == nil)
    }

    @Test func dedupMemoryIsBoundedAndForgetsOldPackets() {
        let r = RouterBox(local: peer(0))
        _ = r.accept(packet(.text, seq: 1), now: t0)
        // After the dedup lifetime the key is forgotten; the replay window
        // still holds it back if the stream moved on, so move it on.
        for s in 2..<200 { _ = r.accept(packet(.text, seq: UInt32(s)), now: at(Router.dedupLifetime + 1)) }
        #expect(r.accept(packet(.text, seq: 1), now: at(Router.dedupLifetime + 2)).dropped == .replay)
    }

    /// A line A - B - C: C hears A only through B. The relay copy B produces
    /// is what C accepts, with one hop counted.
    @Test func aLineTopologyRelaysThroughTheMiddle() {
        let b = RouterBox(local: peer(2)), c = RouterBox(local: peer(3))
        let fromA = packet(.text, from: peer(1), seq: 1)
        let atB = b.accept(fromA, now: t0)
        let relay = try! #require(atB.relay)
        let atC = c.accept(relay, now: t0)
        #expect(atC.deliver)
        #expect(relay.hops == 1)
        // C's own relay of it goes back toward B, which drops it as a duplicate.
        #expect(b.accept(atC.relay!, now: t0).dropped == .duplicate)
    }
}

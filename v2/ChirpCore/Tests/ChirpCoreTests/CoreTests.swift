import Foundation
import Testing
@testable import ChirpCore

@Suite struct JitterBufferTests {
    let a = JitterBuffer.Speaker(peer: peer(1), epoch: 1)
    let b = JitterBuffer.Speaker(peer: peer(2), epoch: 1)
    func frame(_ n: UInt32) -> Data { Data([UInt8(n & 0xFF)]) }

    @Test func waitsForInitialDepthThenPlaysInOrder() {
        let j = JitterBox(initialDepth: 3, maxDepth: 10)
        j.push(frame(2), sequence: 2, from: a)
        j.push(frame(1), sequence: 1, from: a)
        #expect(j.pull() == nil)
        j.push(frame(3), sequence: 3, from: a)
        #expect(j.pull() == frame(1))
        #expect(j.pull() == frame(2))
        #expect(j.pull() == frame(3))
        #expect(j.pull() == nil)
    }

    @Test func dropsLateAndDuplicateFramesAndCountsLoss() {
        let j = JitterBox(initialDepth: 1, maxDepth: 10)
        j.push(frame(5), sequence: 5, from: a)
        #expect(j.pull() == frame(5))
        j.push(frame(4), sequence: 4, from: a)
        #expect(j.stats.late == 1)
        j.push(frame(8), sequence: 8, from: a)
        j.push(frame(8), sequence: 8, from: a)
        #expect(j.count == 1)
        #expect(j.pull() == frame(8))
        #expect(j.stats.lost == 2)
    }

    /// Audit defect 2, claim H5. In 1.0, after playing speaker A up to frame
    /// 500, every frame below 500 from the next speaker was dropped as late.
    @Test func aNewSpeakerWithALowerCounterIsHeard() {
        let j = JitterBox(initialDepth: 1, maxDepth: 10)
        for n in 498...500 { j.push(frame(UInt32(n)), sequence: UInt32(n), from: a); _ = j.pull() }
        j.push(frame(0), sequence: 0, from: b)
        #expect(j.pull() == frame(0))
        #expect(j.stats.late == 0 && j.stats.resets == 1)
    }

    @Test func theSamePersonAfterARelaunchIsANewStream() {
        let j = JitterBox(initialDepth: 1, maxDepth: 10)
        for n in 0...300 { j.push(frame(UInt32(n)), sequence: UInt32(n), from: a); _ = j.pull() }
        let relaunched = JitterBuffer.Speaker(peer: peer(1), epoch: 2)
        j.push(frame(0), sequence: 0, from: relaunched)
        #expect(j.pull() == frame(0))
    }

    @Test func trimsToMaxDepthKeepingTheNewest() {
        let j = JitterBox(initialDepth: 1, maxDepth: 4)
        for n in 1...10 { j.push(frame(UInt32(n)), sequence: UInt32(n), from: a) }
        #expect(j.count == 4)
        #expect(j.pull() == frame(7))
    }

    @Test func orderingSurvivesSequenceWrap() {
        let j = JitterBox(initialDepth: 3, maxDepth: 10)
        j.push(frame(0), sequence: 0, from: a)
        j.push(frame(255), sequence: UInt32.max, from: a)
        j.push(frame(1), sequence: 1, from: a)
        #expect(j.pull() == frame(255))
        #expect(j.pull() == frame(0))
        #expect(j.pull() == frame(1))
    }
}

@Suite struct BlockListTests {
    @Test func blockUnblockAndPersist() throws {
        var list = BlockList()
        let first = list.block(peer(4), name: "Pat", at: t0)
        let again = list.block(peer(4), name: "Pat", at: t0)
        #expect(first && !again)
        #expect(list.isBlocked(peer(4)) && !list.isBlocked(peer(5)))
        let back = try BlockList.decode(try list.encoded())
        #expect(back == list && back.peers == [peer(4)])
        let lifted = list.unblock(peer(4))
        #expect(lifted && !list.isBlocked(peer(4)))
        #expect(throws: (any Error).self) { try BlockList.decode(Data("junk".utf8)) }
    }

    /// Claim H18: in 1.0 a blocked person stayed in the nearby list. One key
    /// for both means the roster cannot show them.
    @Test func aBlockedPersonIsNotInTheNearbyList() {
        let pat = newIdentity(), sam = newIdentity()
        var roster = Roster()
        roster.update(with: Presence(identity: pat, name: "Pat", at: t0), hops: 0, now: t0)
        roster.update(with: Presence(identity: sam, name: "Sam", at: t0), hops: 0, now: t0)
        var list = BlockList()
        list.block(pat.peerID, name: "Pat", at: t0)
        #expect(roster.visible(excluding: list.peers).map(\.name) == ["Sam"])
        let router = RouterBox(local: sam.peerID)
        router.blocked = list.peers
        #expect(router.accept(packet(from: pat.peerID, seq: 1), now: t0).dropped == .blocked)
    }
}

@Suite struct CheckInTests {
    @Test func offByDefaultAndConsentIsAskedEveryTime() {
        var s = CheckInState.off
        #expect(!CheckIn.maySend(s, at: t0))
        for round in 0..<3 {
            let start = at(Double(round) * 2000)
            var (next, fx) = CheckIn.reduce(s, .tappedCheckIn(authorization: .granted))
            #expect(next == .askingConsent && fx == [.showConsentSheet], "round \(round)")
            (next, fx) = CheckIn.reduce(next, .consentAnswered(yes: true, authorization: .granted, at: start))
            #expect(fx == [.startLocationUpdates])
            #expect(CheckIn.maySend(next, at: start.addingTimeInterval(CheckIn.duration - 1)))
            (s, fx) = CheckIn.reduce(next, .tick(start.addingTimeInterval(CheckIn.duration)))
            #expect(s == .off && fx == [.stopLocationUpdates])
        }
    }

    @Test func decliningSharesNothing() {
        let (s, fx) = CheckIn.reduce(.askingConsent, .consentAnswered(yes: false, authorization: .granted, at: t0))
        #expect(s == .off && fx.isEmpty)
    }

    @Test func theSystemPromptComesOnlyAfterOurConsentYes() {
        var (s, fx) = CheckIn.reduce(.off, .tappedCheckIn(authorization: .notDetermined))
        #expect(!fx.contains(.requestSystemPermission))
        (s, fx) = CheckIn.reduce(s, .consentAnswered(yes: true, authorization: .notDetermined, at: t0))
        #expect(s == .awaitingSystemPermission && fx == [.requestSystemPermission])
        (s, fx) = CheckIn.reduce(s, .systemPermissionAnswered(granted: false, at: t0))
        #expect(s == .off)
        let denied = CheckIn.reduce(.off, .tappedCheckIn(authorization: .denied))
        #expect(denied.0 == .off && denied.1 == [.explainDenied])
    }

    @Test func backgroundAndStopEndSharingAndNothingStartsIt() {
        let sharing = CheckInState.sharing(until: at(900))
        #expect(CheckIn.reduce(sharing, .enteredBackground) == (.off, [.stopLocationUpdates]))
        #expect(CheckIn.reduce(sharing, .tappedStop) == (.off, [.stopLocationUpdates]))
        for e: CheckInEvent in [.tick(t0), .enteredBackground, .tappedStop,
                                .systemPermissionAnswered(granted: true, at: t0),
                                .consentAnswered(yes: true, authorization: .granted, at: t0)] {
            #expect(CheckIn.reduce(.off, e).0 == .off, "\(e)")
        }
    }
}

@Suite struct SendGateTests {
    @Test func demoTrafficNeverReachesTheRadio() {
        let demo = packet(seq: 1, channel: SendGate.demoChannel(1))
        let real = packet(seq: 1)
        #expect(SendGate.isDemo(demo.channel) && !SendGate.isDemo(.nearby))
        #expect(!SendGate.allowsSend(demo, sandboxed: false))
        #expect(!SendGate.allowsSend(real, sandboxed: true))
        #expect(SendGate.allowsSend(real, sandboxed: false))
        #expect(!SendGate.allowsReceive(real, sandboxed: true))
        #expect(!SendGate.allowsReceive(demo, sandboxed: false))
    }
}

@Suite struct ChannelTests {
    @Test func inviteCodesRoundTrip() {
        let locked = Channel.newLocked(name: "Ski trip")
        #expect(locked.inviteCode.count == 43)
        #expect(Channel.join(inviteCode: locked.inviteCode, name: "x") == Channel(id: locked.id, name: "x", seed: locked.seed))
        let open = Channel.newOpen(name: "Camp")
        #expect(open.inviteCode.count == 22)
        #expect(Channel.join(inviteCode: " \(open.inviteCode)\n", name: "Camp") == open)
        #expect(Channel.join(inviteCode: "nope", name: "") == nil)
    }

    /// Claim H7: a locked channel's voice must be unreadable without the code.
    @Test func lockedPayloadsOpenOnlyWithTheKeyAndTheirOwnHeader() throws {
        let ch = Channel.newLocked(name: "L")
        let p = packet(.audio, seq: 7, channel: ch.id)
        let sealed = try ch.seal(Data("opus".utf8), header: p.sealedHeader)
        #expect(sealed != Data("opus".utf8))
        #expect(ch.open(sealed, header: p.sealedHeader) == Data("opus".utf8))
        let outsider = Channel(id: ch.id, name: "L", seed: Data(repeating: 0, count: 16))
        #expect(outsider.open(sealed, header: p.sealedHeader) == nil)
        let moved = packet(.audio, seq: 8, channel: ch.id)
        #expect(ch.open(sealed, header: moved.sealedHeader) == nil)
        // Relaying changes TTL and hops but not the sealed header.
        #expect(ch.open(sealed, header: p.relayed()!.sealedHeader) == Data("opus".utf8))
    }

    @Test func openChannelsPassPayloadsThrough() throws {
        let p = packet(seq: 1)
        #expect(try Channel.nearby.seal(Data([1]), header: p.sealedHeader) == Data([1]))
        #expect(Channel.nearby.open(Data([1]), header: p.sealedHeader) == Data([1]))
    }
}

@Suite struct PresenceTests {
    @Test func aSignedPresenceVerifiesForItsOwnOrigin() throws {
        let id = newIdentity()
        let payload = try Presence(identity: id, name: "Robin", at: t0).signedPayload(by: id)
        let p = try #require(Presence.verify(payload, origin: id.peerID, now: at(5)))
        #expect(p.name == "Robin" && p.peer == id.peerID && p.agreementKey == id.agreementPublicKey)
    }

    @Test func rejectsAnotherOriginATamperedBodyAndAStaleClock() throws {
        let id = newIdentity()
        let payload = try Presence(identity: id, name: "Robin", at: t0).signedPayload(by: id)
        #expect(Presence.verify(payload, origin: newIdentity().peerID, now: t0) == nil)
        var tampered = payload; tampered[70] ^= 1
        #expect(Presence.verify(tampered, origin: id.peerID, now: t0) == nil)
        #expect(Presence.verify(payload, origin: id.peerID, now: at(Presence.clockTolerance + 1)) == nil)
        #expect(Presence.verify(payload + Data([0]), origin: id.peerID, now: t0) == nil)
    }

    @Test func rosterHasOneEntryPerPersonAndForgetsTheSilent() {
        let a = newIdentity(), b = newIdentity()
        var r = Roster()
        let isNew = r.update(with: Presence(identity: a, name: "A", at: t0), hops: 1, now: t0)
        let isNewAgain = r.update(with: Presence(identity: a, name: "A renamed", at: t0), hops: 0, now: at(1))
        #expect(isNew && !isNewAgain)
        r.update(with: Presence(identity: b, name: "B", at: t0), hops: 0, now: t0)
        #expect(r.visible(excluding: []).count == 2)
        #expect(r.person(a.peerID)?.name == "A renamed")
        r.heard(a.peerID, now: at(10))
        let gone = r.prune(now: at(Roster.staleAfter + 2))
        #expect(gone == [b.peerID])
        #expect(r.visible(excluding: []).map(\.name) == ["A renamed"])
    }
}

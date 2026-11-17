import Foundation
import Testing
@testable import ChirpCore

@Suite struct FindTests {
    @Test func messagesRoundTripAndRejectJunk() {
        let token = Data((0..<300).map { UInt8($0 % 256) })
        for m in [Find.Message.offer(token: token), .answer(token: token), .stop] {
            #expect(Find.Message.decode(m.encode()) == m)
        }
        #expect(Find.Message.decode(Data([1, 0, 0])) == nil)
        #expect(Find.Message.decode(Find.Message.offer(token: Data(count: Find.maxTokenBytes + 1)).encode()) == nil)
        #expect(Find.Message.decode(Data([3, 0])) == nil)
    }

    @Test func tokensAreFriendsOnlyOnTheWire() {
        let me = peer(1), friend = peer(2), stranger = peer(3)
        let ok = packet(.find, from: friend, seq: 1, channel: Whisper.channelID(me, friend))
        #expect(Admission.accepts(ok, me: me, friends: [friend], blocked: []))
        #expect(!Admission.accepts(packet(.find, from: stranger, seq: 1, channel: Whisper.channelID(me, stranger)),
                                   me: me, friends: [friend], blocked: []))
        #expect(!Admission.accepts(packet(.find, from: friend, seq: 1), me: me, friends: [friend], blocked: []))
    }

    @Test func theFallbackClaimsOnlyWhatTheMeshKnows() {
        let id = newIdentity()
        var r = Roster()
        r.update(with: Presence(identity: id, name: "F", at: t0), hops: 0, now: t0)
        #expect(Find.fallback(for: r.person(id.peerID), lastSeen: nil, now: at(5)) == .inRange)
        r.update(with: Presence(identity: id, name: "F", at: t0), hops: 1, now: at(6))
        #expect(Find.fallback(for: r.person(id.peerID), lastSeen: nil, now: at(7)) == .throughOthers)
        #expect(Find.fallback(for: r.person(id.peerID), lastSeen: nil, now: at(30)) == .outOfRange(lastSeen: at(6)))
        #expect(Find.fallback(for: nil, lastSeen: at(2), now: at(30)) == .outOfRange(lastSeen: at(2)))
    }
}

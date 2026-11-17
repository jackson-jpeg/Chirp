import Foundation
import Testing
@testable import ChirpCore

@Suite struct WhisperTests {
    let a = newIdentity(), b = newIdentity(), c = newIdentity()

    @Test func bothSidesDeriveTheSameChannelAndKey() throws {
        #expect(Whisper.channelID(a.peerID, b.peerID) == Whisper.channelID(b.peerID, a.peerID))
        #expect(Whisper.channelID(a.peerID, b.peerID) != Whisper.channelID(a.peerID, c.peerID))
        let ab = try #require(Whisper.channel(me: a, them: b.peerID, theirAgreementKey: b.agreementPublicKey, name: "B"))
        let ba = try #require(Whisper.channel(me: b, them: a.peerID, theirAgreementKey: a.agreementPublicKey, name: "A"))
        #expect(ab.id == ba.id && ab.seed == ba.seed && ab.isLocked)
        #expect(!SendGate.isDemo(ab.id) && !ab.id.isNearby)
    }

    @Test func onlyTheRecipientCanOpenAWhisper() throws {
        let ab = try #require(Whisper.channel(me: a, them: b.peerID, theirAgreementKey: b.agreementPublicKey, name: "B"))
        let ba = try #require(Whisper.channel(me: b, them: a.peerID, theirAgreementKey: a.agreementPublicKey, name: "A"))
        let p = packet(.audio, from: a.peerID, seq: 1, channel: ab.id)
        let sealed = try ab.seal(Data("psst".utf8), header: p.sealedHeader)
        #expect(ba.open(sealed, header: p.sealedHeader) == Data("psst".utf8))
        // C relays it but cannot read it, even knowing the channel ID and A's public keys.
        let cGuess = try #require(Whisper.channel(me: c, them: a.peerID, theirAgreementKey: a.agreementPublicKey, name: "A"))
        let cAsIfB = Channel(id: ab.id, name: "", seed: cGuess.seed)
        #expect(cAsIfB.open(sealed, header: p.sealedHeader) == nil)
        #expect(Whisper.isFor(p, me: b.peerID))
        #expect(!Whisper.isFor(p, me: c.peerID))
        #expect(!Whisper.isFor(p, me: a.peerID))
    }

    /// A whisper has its own floor: it neither takes nor is blocked by the group's.
    @Test func aWhisperDoesNotTakeTheGroupFloor() {
        let whisper = Whisper.channelID(a.peerID, b.peerID)
        let group = ChannelID.random()
        let e = FloorEvent.received(.request(sender: a.peerID, name: "A", claimedAt: t0), from: a.peerID, channel: whisper, at: t0)
        #expect(FloorMachine.reduce(.idle, on: e, me: c.peerID, myName: "C", channel: group).state == .idle)
        #expect(FloorMachine.reduce(.idle, on: e, me: b.peerID, myName: "B", channel: whisper).state.speaker?.peer == a.peerID)
    }
}

@Suite struct MessageTests {
    let a = newIdentity(), b = newIdentity()

    @Test func signedBodiesOpenOnlyForTheirKeyAndHeader() throws {
        let h = packet(.rollCall, from: a.peerID, seq: 1).sealedHeader
        let wire = try Signed.payload(Data([1, 2, 3]), by: a, header: h)
        #expect(Signed.open(wire, header: h, signingKey: a.signingPublicKey) == Data([1, 2, 3]))
        #expect(Signed.open(wire, header: h, signingKey: b.signingPublicKey) == nil)
        #expect(Signed.open(wire, header: packet(.rollCall, from: a.peerID, seq: 2).sealedHeader, signingKey: a.signingPublicKey) == nil)
        #expect(Signed.open(Data(count: 10), header: h, signingKey: a.signingPublicKey) == nil)
    }

    @Test func rollCallRoundTripsAndTallies() {
        let id = UUID()
        for m in [RollCall.ask(id: id, at: Date(timeIntervalSince1970: 1_800_000_000)), .answer(id: id, ok: true), .answer(id: id, ok: false)] {
            #expect(RollCall.decode(m.encode()) == m)
        }
        #expect(RollCall.decode(Data([3]) + Data(count: 16)) == nil)
        #expect(RollCall.decode(RollCall.answer(id: id, ok: true).encode() + Data([0])) == nil)
        var tally = RollCallTally(id: id)
        tally.record(.answer(id: id, ok: true), from: peer(1))
        tally.record(.answer(id: id, ok: false), from: peer(2))
        tally.record(.answer(id: UUID(), ok: false), from: peer(3))   // another roll call
        #expect(tally.okCount == 1 && tally.needHelp == [peer(2)])
        #expect(tally.missing(from: [peer(1), peer(2), peer(4)]) == [peer(4)])
    }

    @Test func helpRoundTripsGoesFirstAndCarriesFar() {
        let h = HelpCall(at: Date(timeIntervalSince1970: 1_800_000_000), note: "twisted ankle by the lift")
        #expect(HelpCall.decode(h.encode()) == h)
        #expect(PacketKind.help.sendPriority < PacketKind.audio.sendPriority)
        #expect(PacketKind.help.initialTTL == Packet.maxTTL)
    }

    @Test func meetupRoundTripsWithAndWithoutAPosition() {
        let id = UUID(), at = Date(timeIntervalSince1970: 1_800_000_000)
        let plain = Meetup.spot(id: id, place: "Big tent, left side", latitude: nil, longitude: nil, at: at)
        let pinned = Meetup.spot(id: id, place: "Lodge", latitude: 39.6, longitude: -106.35, at: at)
        #expect(Meetup.decode(plain.encode()) == plain)
        #expect(Meetup.decode(pinned.encode()) == pinned)
        #expect(Meetup.decode(Meetup.reply(id: id, coming: true).encode()) == .reply(id: id, coming: true))
        var bad = pinned.encode(); bad.replaceSubrange(bad.count - 16..<bad.count - 8, with: withUnsafeBytes(of: (200.0).bitPattern.bigEndian) { Data($0) })
        #expect(Meetup.decode(bad) == nil)
        var rsvp = MeetupRSVP(id: id, organiser: peer(1))
        rsvp.record(.reply(id: id, coming: true), from: peer(2))
        rsvp.record(.reply(id: id, coming: false), from: peer(3))
        rsvp.record(.reply(id: id, coming: false), from: peer(2))   // changed their mind
        #expect(rsvp.coming == [peer(1)] && rsvp.notComing == [peer(2), peer(3)])
    }

    @Test func batteryIsCoarse() {
        #expect(BatteryLevel(fraction: 0.47, charging: false).percent == 50)
        #expect(BatteryLevel(fraction: 0.04, charging: true).percent == 0)
        #expect(BatteryLevel(fraction: 1.3, charging: false).percent == 100)
        let level = BatteryLevel(fraction: 0.8, charging: true)
        #expect(BatteryLevel.decode(level.encode()) == level)
        #expect(BatteryLevel.decode(Data([101, 0])) == nil)
    }

    /// Ping and battery: only from a friend, only on the whisper channel to me.
    @Test func pingAndBatteryAreFriendsOnlyOnTheWire() {
        let me = b.peerID, friend = a.peerID, stranger = newIdentity().peerID
        let toMe = Whisper.channelID(me, friend)
        let ok = packet(.ping, from: friend, seq: 1, channel: toMe)
        #expect(Admission.accepts(ok, me: me, friends: [friend], blocked: []))
        #expect(!Admission.accepts(ok, me: me, friends: [], blocked: []))
        #expect(!Admission.accepts(ok, me: me, friends: [friend], blocked: [friend]))
        #expect(!Admission.accepts(packet(.battery, from: friend, seq: 1, channel: .nearby), me: me, friends: [friend], blocked: []))
        #expect(!Admission.accepts(packet(.ping, from: stranger, seq: 1, channel: Whisper.channelID(me, stranger)),
                                   me: me, friends: [friend], blocked: []))
        #expect(Admission.accepts(packet(.text, from: stranger, seq: 1), me: me, friends: [], blocked: []))
    }

    @Test func pingIsRateLimitedPerPerson() {
        var limit = RateLimiter(interval: 10)
        let first = limit.allow(peer(1), now: t0)
        let again = limit.allow(peer(1), now: at(5))
        let other = limit.allow(peer(2), now: at(5))
        let later = limit.allow(peer(1), now: at(10))
        #expect(first && !again && other && later)
    }

    @Test func theSendQueuePutsHelpFirstAndDropsTheLeastImportant() {
        var q = SendQueue(capacity: 3)
        q.push(packet(.presence, seq: 1))
        q.push(packet(.text, seq: 2))
        q.push(packet(.audio, seq: 3))
        let dropped = q.push(packet(.help, seq: 4))
        #expect(dropped?.kind == .presence)
        let order = [q.pop(), q.pop(), q.pop(), q.pop()].map { $0?.kind }
        #expect(order == [.help, .audio, .text, nil])
    }
}

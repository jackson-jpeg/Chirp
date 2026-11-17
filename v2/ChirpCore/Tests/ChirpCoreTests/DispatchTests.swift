import Foundation
import Testing
@testable import ChirpCore

/// Two (or three) phones exchanging real packets through `Dispatch`.
final class Phone {
    var d: Dispatch
    init(_ name: String, epoch: UInt32 = 1) { d = Dispatch(identity: newIdentity(), name: name, epoch: epoch) }
    var id: PeerID { d.me }
    func receive(_ p: Packet, from link: PeerID? = nil, at s: TimeInterval = 0) -> Dispatch.Output {
        d.receive(p, from: link ?? p.origin, now: at(s))
    }
    func presence(at s: TimeInterval = 0) -> Packet { try! d.presence(now: at(s)) }
    /// Both phones learn each other's keys.
    func meet(_ other: Phone, at s: TimeInterval = 0) {
        _ = receive(other.presence(at: s), at: s)
        _ = other.receive(presence(at: s), at: s)
    }
    /// Both phones join one locked channel and say so: they are friends.
    func befriend(_ other: Phone, on channel: Channel = .newLocked(name: "Ski trip"), at s: TimeInterval = 0) {
        meet(other, at: s)
        d.join(channel); other.d.join(channel)
        for p in d.memberships(now: at(s)) { _ = other.receive(p, at: s) }
        for p in other.d.memberships(now: at(s)) { _ = receive(p, at: s) }
    }
}

@Suite struct DispatchTests {
    @Test func presenceAddsAPersonOnceAndAgainOnlyWhenTheyChange() {
        let a = Phone("Maya"), b = Phone("Jon")
        let first = b.receive(a.presence())
        #expect(first.events.count == 1)
        guard case .presence(let p) = first.events.first else { Issue.record("no presence"); return }
        #expect(p.name == "Maya" && p.id == a.id)
        #expect(b.receive(a.presence(at: 3), at: 3).events.isEmpty)
        a.d.name = "Maya R"
        #expect(b.receive(a.presence(at: 6), at: 6).events.count == 1)
    }

    @Test func aPresenceWithAnotherOriginIsRefused() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        let real = a.presence()
        let forged = Packet(kind: .presence, origin: m.id, epoch: 9, sequence: 0, channel: .nearby, payload: real.payload)
        #expect(b.receive(forged).events.isEmpty)
        #expect(b.d.roster.person(m.id) == nil)
    }

    @Test func aTextIsStoredAckedAndTicked() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let text = try a.d.text("meet at the lift", on: .nearby, now: t0)
        let got = b.receive(text, at: 1)
        guard case .text(let stored) = got.events.first else { Issue.record("no text"); return }
        #expect(stored.text == "meet at the lift" && stored.senderName == "Maya" && !stored.outgoing)
        let ack = try #require(got.broadcast.first)
        #expect(ack.kind == .ack && ack.channel == .nearby)

        let back = a.receive(ack, at: 2)
        #expect(back.events == [.delivered(stored.id, from: b.id)])
        #expect(a.d.ledger.texts.first?.deliveredTo == [b.id.hex])
    }

    @Test func noPresenceNoText() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        _ = a.receive(b.presence())   // A knows B, B does not know A
        let text = try a.d.text("hi", on: .nearby, now: t0)
        let got = b.receive(text)
        #expect(got.events.isEmpty && got.broadcast.isEmpty)
        #expect(got.relay != nil)     // still relayed for others
    }

    @Test func aForgedTextFromSomeoneElsesOriginFailsTheSignature() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        a.meet(b); m.meet(b)
        let real = try m.d.text("give me your location", on: .nearby, now: t0)
        let forged = Packet(kind: .text, origin: a.id, epoch: real.epoch, sequence: real.sequence, channel: .nearby, payload: real.payload)
        #expect(b.receive(forged).events.isEmpty)
    }

    @Test func aLockedChannelIsUnreadableToPhonesNotOnItButStillRelayed() throws {
        let a = Phone("Maya"), b = Phone("Jon"), c = Phone("Sam")
        a.meet(b); a.meet(c)
        let camp = Channel.newLocked(name: "Camp")
        a.d.join(camp); b.d.join(camp)
        let text = try a.d.text("secret", on: camp.id, now: t0)

        let atC = c.receive(text)
        #expect(atC.events.isEmpty && atC.broadcast.isEmpty)
        let relay = try #require(atC.relay)
        #expect(relay.hops == 1)

        let atB = b.receive(relay, from: c.id)
        guard case .text(let s) = atB.events.first else { Issue.record("B could not read"); return }
        #expect(s.text == "secret")
        #expect(atB.broadcast.first?.channel == camp.id)   // the ack stays on the channel
    }

    @Test func blockedPeopleAreNeitherDeliveredNorRelayed() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        b.d.setBlocked([a.id])
        let got = b.receive(try a.d.text("hi", on: .nearby, now: t0))
        #expect(got.events.isEmpty && got.relay == nil)
    }

    @Test func floorMustComeFromItsSender() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        a.meet(b); m.meet(b)
        let ok = try a.d.floor(.request(sender: a.id, name: "Maya", claimedAt: t0), on: .nearby, now: t0)
        #expect(b.receive(ok).events == [.floor(.request(sender: a.id, name: "Maya", claimedAt: t0), channel: .nearby)])
        let lie = try m.d.floor(.request(sender: a.id, name: "Maya", claimedAt: t0), on: .nearby, now: t0)
        #expect(b.receive(lie).events.isEmpty)
    }

    @Test func audioArrivesWithItsStreamAndChannel() throws {
        let a = Phone("Maya", epoch: 7), b = Phone("Jon")
        let p = try a.d.audio(Data([9, 9]), on: .nearby, now: t0)
        #expect(b.receive(p).events == [.audio(Data([9, 9]), from: a.id, epoch: 7, sequence: 0, channel: .nearby)])
    }

    @Test func pingOnlyFromAFriendOnTheWhisperChannelAndRateLimited() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        a.meet(b); m.meet(b)
        #expect(throws: Dispatch.MakeError.notFriend) { try a.d.toFriend(.ping, Data(), peer: b.id, now: t0) }
        a.befriend(b)
        #expect(b.receive(try a.d.toFriend(.ping, Data(), peer: b.id, now: t0)).events == [.ping(from: a.id)])
        #expect(b.receive(try a.d.toFriend(.ping, Data(), peer: b.id, now: at(1)), at: 1).events.isEmpty)
        #expect(b.receive(try a.d.toFriend(.ping, Data(), peer: b.id, now: at(11)), at: 11).events == [.ping(from: a.id)])

        // Mallory is not B's friend: even a whisper-channel ping is dropped.
        #expect(b.receive(try m.d.make(.ping, on: m.d.whisperChannel(to: b.id), body: Data(), now: t0)).events.isEmpty)
    }

    @Test func aWhisperIsOpenOnlyToItsOnePerson() throws {
        let a = Phone("Maya"), b = Phone("Jon"), c = Phone("Sam")
        a.meet(b); a.meet(c); b.meet(c)
        let whisper = try a.d.audio(Data([1]), on: a.d.whisperChannel(to: b.id), now: t0)
        let atC = c.receive(whisper)
        #expect(atC.events.isEmpty && atC.relay != nil)
        #expect(b.receive(whisper).events.count == 1)
    }

    @Test func batteryAndFindReachAFriend() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.befriend(b)
        let level = BatteryLevel(fraction: 0.47, charging: false)
        #expect(b.receive(try a.d.toFriend(.battery, level.encode(), peer: b.id, now: t0)).events == [.battery(level, from: a.id)])
        let offer = Find.Message.offer(token: Data([1, 2, 3]))
        #expect(b.receive(try a.d.toFriend(.find, offer.encode(), peer: b.id, now: t0)).events == [.find(offer, from: a.id)])
    }

    @Test func helpRollCallAndMeetupDecode() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let help = HelpCall(at: t0, note: "twisted ankle")
        #expect(b.receive(try a.d.make(.help, on: .nearby, body: help.encode(), now: t0)).events
                == [.help(help, from: a.id, channel: .nearby)])
        let ask = RollCall.ask(id: UUID(), at: t0)
        #expect(b.receive(try a.d.make(.rollCall, on: .nearby, body: ask.encode(), now: t0)).events
                == [.rollCall(ask, from: a.id, channel: .nearby)])
    }

    @Test func aPhotoArrivesWhenItsLastChunkDoes() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let bytes = Data((0..<20_000).map { UInt8($0 % 251) })
        let chunks = try #require(PhotoChunk.split(bytes))
        var events: [Dispatch.Event] = []
        for c in chunks { events += b.receive(try a.d.make(.photo, on: .nearby, body: c.encode(), now: t0)).events }
        #expect(events == [.photo(bytes, id: chunks[0].photoID, from: a.id, channel: .nearby)])
    }

    @Test func catchUpHandsOverWhatWasMissedOnceAndInOrder() throws {
        let a = Phone("Maya"), holder = Phone("Jon"), late = Phone("Sam")
        a.meet(holder); a.meet(late); holder.meet(late)
        let t1 = try a.d.text("first", on: .nearby, now: at(1))
        let t2 = try a.d.text("second", on: .nearby, now: at(2))
        _ = holder.receive(t1, at: 1)
        _ = holder.receive(t2, at: 2)

        let ask = try late.d.catchUpRequest(since: [.nearby: t0], now: at(5))
        let answer = holder.receive(ask, at: 5)
        #expect(answer.relay == nil && !answer.reply.isEmpty)

        var texts: [String] = []
        for bundle in answer.reply {
            for e in late.receive(bundle, from: holder.id, at: 6).events { if case .text(let s) = e { texts.append(s.text) } }
        }
        #expect(texts == ["first", "second"])

        // The same text live afterwards is a duplicate: acked, not shown.
        let again = late.receive(t1, at: 7)
        #expect(again.events.isEmpty && again.broadcast.count == 1)
    }

    @Test func aCatchUpBundleMustComeStraightFromItsSender() throws {
        let a = Phone("Maya"), holder = Phone("Jon"), late = Phone("Sam")
        a.meet(holder); a.meet(late); holder.meet(late)
        _ = holder.receive(try a.d.text("x", on: .nearby, now: at(1)), at: 1)
        let answer = holder.receive(try late.d.catchUpRequest(since: [.nearby: t0], now: at(5)), at: 5)
        let bundle = try #require(answer.reply.first)
        #expect(late.receive(bundle, from: a.id, at: 6).events.isEmpty)
    }

    @Test func makingOnAChannelIAmNotOnFails() {
        let a = Phone("Maya")
        #expect(throws: Dispatch.MakeError.notOnChannel) { try a.d.text("x", on: .random(), now: t0) }
    }
}

import Foundation
import Testing
@testable import ChirpCore

/// Who counts as a friend: someone who proved they hold the key of a locked
/// channel I am on. Never everyone heard on Nearby.
@Suite struct FriendsTests {
    @Test func strangersOnNearbyAreNotFriendsEvenAfterTalking() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        _ = b.receive(try a.d.text("hi", on: .nearby, now: t0))
        _ = b.receive(try a.d.floor(.request(sender: a.id, name: "Maya", claimedAt: t0), on: .nearby, now: t0))
        #expect(b.d.friends.isEmpty)
        #expect(throws: Dispatch.MakeError.notFriend) { try b.d.toFriend(.battery, Data([50, 0]), peer: a.id, now: t0) }
    }

    @Test func anOpenChannelMakesNoFriends() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let open = Channel.newOpen(name: "Festival")
        a.d.join(open); b.d.join(open)
        #expect(a.d.memberships(now: t0).isEmpty)
        _ = b.receive(try a.d.text("over here", on: open.id, now: t0))
        #expect(b.d.friends.isEmpty)
    }

    @Test func aMembershipOnALockedChannelMakesAFriendOnce() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let camp = Channel.newLocked(name: "Camp")
        a.d.join(camp); b.d.join(camp)
        let hello = try #require(a.d.memberships(now: t0).first)
        #expect(hello.kind == .member && hello.channel == camp.id)
        #expect(b.receive(hello).events == [.friend(a.id, channel: camp.id)])
        #expect(b.d.friends == [a.id])
        #expect(b.receive(try a.d.text("tent 4", on: camp.id, now: at(1)), at: 1).events.count == 1)   // the text, no second .friend
    }

    @Test func anyTextOnTheLockedChannelAlsoProvesIt() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let camp = Channel.newLocked(name: "Camp")
        a.d.join(camp); b.d.join(camp)
        let events = b.receive(try a.d.text("tent 4", on: camp.id, now: t0)).events
        #expect(events.contains(.friend(a.id, channel: camp.id)))
        #expect(b.d.friends == [a.id])
    }

    @Test func someoneWithoutTheKeyCannotClaimTheChannel() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        m.meet(b)
        let camp = Channel.newLocked(name: "Camp")
        b.d.join(camp)
        // Mallory knows the channel ID (it is in every header) but not the key.
        let guess = Channel(id: camp.id, name: "Camp", seed: Data(repeating: 7, count: Channel.seedLength))
        m.d.join(guess)
        for p in m.d.memberships(now: t0) { _ = b.receive(p) }
        #expect(b.d.friends.isEmpty)
        // A relay of a real member's packet makes the member a friend, not the relay.
        a.meet(b); a.d.join(camp)
        let hello = try #require(a.d.memberships(now: t0).first)
        _ = b.receive(try #require(hello.relayed()), from: m.id)
        #expect(b.d.friends == [a.id])
    }

    @Test func leavingTheChannelEndsTheFriendshipUnlessAnotherIsShared() {
        let a = Phone("Maya"), b = Phone("Jon")
        let ski = Channel.newLocked(name: "Ski trip"), camp = Channel.newLocked(name: "Camp")
        a.befriend(b, on: ski)
        a.befriend(b, on: camp)
        b.d.leave(ski.id)
        #expect(b.d.friends == [a.id])
        b.d.leave(camp.id)
        #expect(b.d.friends.isEmpty)
    }

    @Test func blockingRemovesAFriendAndUnblockingBringsThemBack() {
        let a = Phone("Maya"), b = Phone("Jon")
        a.befriend(b)
        b.d.setBlocked([a.id])
        #expect(b.d.friends.isEmpty)
        b.d.setBlocked([])
        #expect(b.d.friends == [a.id])
    }

    @Test func membershipsGoOutOncePerIntervalOnEachLockedChannel() {
        let a = Phone("Maya")
        a.d.join(.newLocked(name: "Ski trip")); a.d.join(.newLocked(name: "Camp")); a.d.join(.newOpen(name: "Open"))
        #expect(a.d.memberships(now: t0).count == 2)
        #expect(a.d.memberships(now: at(Dispatch.memberInterval - 1)).isEmpty)
        #expect(a.d.memberships(now: at(Dispatch.memberInterval)).count == 2)
        let late = Channel.newLocked(name: "Late")
        a.d.join(late)
        #expect(a.d.memberships(now: at(Dispatch.memberInterval + 1)).map(\.channel) == [late.id])
    }

    @Test func memberPacketsAreSentLikeTextsButLast() {
        #expect(PacketKind.member.initialTTL == PacketKind.text.initialTTL)
        #expect(PacketKind.member.sendPriority == PacketKind.presence.sendPriority)
        #expect(PacketKind.member.reliable)
    }
}

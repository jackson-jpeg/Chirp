import Foundation
import Testing
@testable import ChirpCore

/// Check-in on the wire: only the birdhouse sees it, only while sharing, never
/// longer than one check-in (site/privacy "Location sharing").
@Suite struct CheckInShareTests {
    let sharing = CheckInState.sharing(until: at(CheckIn.duration))

    @Test func theMessageRoundTripsAndRejectsJunk() {
        let m = CheckInMessage.at(latitude: 39.6, longitude: -106.35, accuracy: 12, until: at(900))
        #expect(CheckInMessage.decode(m.encode()) == m)
        #expect(CheckInMessage.decode(CheckInMessage.stopped.encode()) == .stopped)
        #expect(CheckInMessage.decode(Data([2, 0])) == nil)
        #expect(CheckInMessage.decode(Data([9])) == nil)
        var bad = Data([1]); bad.appendBigEndian((123.0).bitPattern); bad.appendBigEndian((0.0).bitPattern)
        bad.appendBigEndian(UInt16(5)); bad.appendBigEndian(UInt64(0))
        #expect(CheckInMessage.decode(bad) == nil)   // latitude out of range
        #expect(CheckInMessage.accuracy(4.2) == 5)
        #expect(CheckInMessage.accuracy(-1) == UInt16.max)   // Core Location's "invalid"
    }

    @Test func aPositionReachesTheBirdhouseWithTheCheckInsEnd() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        let camp = Channel.newLocked(name: "Camp")
        a.befriend(b, on: camp)
        let p = try a.d.checkInPosition(latitude: 39.6, longitude: -106.35, accuracyMetres: 8,
                                        on: camp.id, state: sharing, now: at(60))
        #expect(p.kind == .checkIn && p.channel == camp.id)
        let events = b.receive(p, at: 60).events
        #expect(events == [.checkIn(.at(latitude: 39.6, longitude: -106.35, accuracy: 8, until: at(CheckIn.duration)),
                                    from: a.id, channel: camp.id)])
    }

    @Test func nothingLeavesWithoutASharingState() {
        let a = Phone("Maya")
        let camp = Channel.newLocked(name: "Camp")
        a.d.join(camp)
        for state in [CheckInState.off, .askingConsent, .awaitingSystemPermission] {
            #expect(throws: Dispatch.MakeError.notSharing) {
                try a.d.checkInPosition(latitude: 1, longitude: 1, accuracyMetres: 5, on: camp.id, state: state, now: t0)
            }
        }
        // A sharing state that has run out is not sharing.
        #expect(throws: Dispatch.MakeError.notSharing) {
            try a.d.checkInPosition(latitude: 1, longitude: 1, accuracyMetres: 5, on: camp.id,
                                    state: sharing, now: at(CheckIn.duration))
        }
    }

    @Test func neverToNearbyAnOpenChannelOrAWhisper() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.befriend(b)
        let open = Channel.newOpen(name: "Festival")
        a.d.join(open)
        for id in [ChannelID.nearby, open.id, a.d.whisperChannel(to: b.id)] {
            #expect(throws: Dispatch.MakeError.notLockedChannel) {
                try a.d.checkInPosition(latitude: 1, longitude: 1, accuracyMetres: 5, on: id, state: sharing, now: t0)
            }
            #expect(throws: Dispatch.MakeError.notLockedChannel) { try a.d.checkInStopped(on: id, now: t0) }
        }
        #expect(a.d.birdhouseChannels.count == 1)
    }

    @Test func aHandMadeCheckInOnAnOpenChannelOrNearbyIsDropped() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        a.meet(b)
        let open = Channel.newOpen(name: "Festival")
        a.d.join(open); b.d.join(open)
        let body = CheckInMessage.at(latitude: 1, longitude: 1, accuracy: 5, until: at(60)).encode()
        #expect(b.receive(try a.d.make(.checkIn, on: open.id, body: body, now: t0)).events.isEmpty)
        #expect(b.receive(try a.d.make(.checkIn, on: .nearby, body: body, now: t0)).events.isEmpty)
    }

    @Test func someoneOutsideTheBirdhouseCannotReadOrSendOne() throws {
        let a = Phone("Maya"), b = Phone("Jon"), m = Phone("Mallory")
        let camp = Channel.newLocked(name: "Camp")
        a.befriend(b, on: camp)
        m.meet(a); m.meet(b)
        let p = try a.d.checkInPosition(latitude: 1, longitude: 1, accuracyMetres: 5, on: camp.id, state: sharing, now: t0)
        let out = m.receive(p)
        #expect(out.events.isEmpty)        // cannot open it
        #expect(out.relay != nil)           // but still carries it on, sealed
    }

    @Test func blockedPeopleAreNotHeard() throws {
        let a = Phone("Maya"), b = Phone("Jon")
        let camp = Channel.newLocked(name: "Camp")
        a.befriend(b, on: camp)
        b.d.setBlocked([a.id])
        let p = try a.d.checkInPosition(latitude: 1, longitude: 1, accuracyMetres: 5, on: camp.id, state: sharing, now: t0)
        #expect(b.receive(p).events.isEmpty)
    }

    @Test func checkInsAreNotHeldForCatchUp() {
        #expect(!CatchUpStore.heldKinds.contains(.checkIn))
        #expect(!Bluetooth.carried.contains(.checkIn))
    }

    @Test func theBoardKeepsTheLatestAndCutsALongClaim() {
        var board = CheckInBoard()
        let camp = ChannelID(UUID()), maya = peer(1), jon = peer(2)
        board.apply(.at(latitude: 1, longitude: 2, accuracy: 5, until: at(600)), from: maya, channel: camp, now: t0)
        board.apply(.at(latitude: 3, longitude: 4, accuracy: 5, until: at(600)), from: maya, channel: camp, now: at(30))
        #expect(board.position(of: maya, now: at(31))?.latitude == 3)
        // A sender claiming a day gets one check-in's worth from when it came.
        board.apply(.at(latitude: 5, longitude: 6, accuracy: 5, until: at(86_400)), from: jon, channel: camp, now: t0)
        #expect(board.position(of: jon, now: t0)?.until == at(CheckIn.duration))
        #expect(board.live(now: at(601)).map(\.peer) == [jon])
        #expect(board.expire(now: at(CheckIn.duration)) == [maya, jon])
        #expect(board.entries.isEmpty)
    }

    @Test func stoppingOrAnEndInThePastClearsIt() {
        var board = CheckInBoard()
        let camp = ChannelID(UUID()), maya = peer(1)
        board.apply(.at(latitude: 1, longitude: 2, accuracy: 5, until: at(600)), from: maya, channel: camp, now: t0)
        board.apply(.stopped, from: maya, channel: camp, now: at(1))
        #expect(board.position(of: maya, now: at(1)) == nil)
        board.apply(.at(latitude: 1, longitude: 2, accuracy: 5, until: at(600)), from: maya, channel: camp, now: t0)
        board.apply(.at(latitude: 1, longitude: 2, accuracy: 5, until: at(5)), from: maya, channel: camp, now: at(10))
        #expect(board.entries.isEmpty)
        board.apply(.at(latitude: 1, longitude: 2, accuracy: 5, until: at(600)), from: maya, channel: camp, now: t0)
        board.forget(maya)
        #expect(board.entries.isEmpty)
    }

    @Test func turningLocationOffEndsACheckIn() {
        let (s, fx) = CheckIn.reduce(sharing, .authorizationChanged(.denied))
        #expect(s == .off && fx == [.stopLocationUpdates])
        let (w, wfx) = CheckIn.reduce(.awaitingSystemPermission, .authorizationChanged(.denied))
        #expect(w == .off && wfx.isEmpty)
        // Turning it on again shares nothing by itself.
        let (o, ofx) = CheckIn.reduce(.off, .authorizationChanged(.granted))
        #expect(o == .off && ofx.isEmpty)
    }
}

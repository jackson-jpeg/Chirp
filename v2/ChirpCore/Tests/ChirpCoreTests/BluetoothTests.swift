import Foundation
import Testing
@testable import ChirpCore

/// Reference wrappers: `#expect` cannot call a mutating method on a local
/// value inside its expression.
private final class Assembler {
    var r = Reassembler()
    var inFlight: Int { r.inFlight }
    func add(_ f: Data, now: Date) -> Data? { r.add(f, now: now) }
}
private final class Alerts {
    var a = LockedAlerts()
    func alert(for e: Dispatch.Event, now: Date, name: (PeerID) -> String?) -> LockedAlert? { a.alert(for: e, now: now, name: name) }
}

@Suite struct BluetoothTests {
    private func bytes(_ n: Int) -> Data { Data((0..<n).map { UInt8($0 % 251) }) }
    private let peer = newIdentity().peerID

    // MARK: What goes over Bluetooth

    @Test func onlySmallTextLikeKindsGoOverBluetooth() {
        for kind in PacketKind.allCases {
            let p = Packet(kind: kind, origin: peer, epoch: 1, sequence: 0, channel: .nearby, payload: Data([1]))
            let expected: Bool
            switch kind {
            // A check-in (a position) never goes over Bluetooth (CheckInShare).
            case .audio, .photo, .catchUp, .battery, .find, .checkIn: expected = false
            default: expected = true
            }
            #expect(Bluetooth.carries(p) == expected, "\(kind)")
        }
        let big = Packet(kind: .text, origin: peer, epoch: 1, sequence: 0, channel: .nearby,
                         payload: bytes(Bluetooth.maxPacket - Packet.headerSize + 1))
        #expect(!Bluetooth.carries(big))
    }

    // MARK: Fragments

    @Test func aPacketSurvivesSplittingAtEveryWriteSize() throws {
        let packet = Packet(kind: .text, origin: peer, epoch: 3, sequence: 9, channel: .random(), payload: bytes(700))
        let wire = packet.encode()
        for mtu in [20, 23, 100, 182, 185, 512, 2048] {
            let parts = Fragments.split(wire, id: 7, maxWrite: mtu)
            #expect(!parts.isEmpty && parts.allSatisfy { $0.count <= mtu })
            let r = Assembler()
            var out: Data?
            for p in parts.reversed() { out = r.add(p, now: t0) ?? out }   // any order
            #expect(Packet.decode(try #require(out)) == packet)
            #expect(r.inFlight == 0)
        }
    }

    @Test func splittingRefusesWhatCannotGo() {
        #expect(Fragments.split(bytes(10), id: 1, maxWrite: 19).isEmpty)
        #expect(Fragments.split(Data(), id: 1, maxWrite: 100).isEmpty)
        #expect(Fragments.split(bytes(Bluetooth.maxPacket + 1), id: 1, maxWrite: 100).isEmpty)
    }

    @Test func aDuplicateFragmentIsCountedOnce() throws {
        let parts = Fragments.split(bytes(300), id: 2, maxWrite: 100)
        let r = Assembler()
        #expect(r.add(parts[0], now: t0) == nil)
        #expect(r.add(parts[0], now: t0) == nil)
        #expect(r.add(parts[1], now: t0) == nil)
        #expect(r.add(parts[2], now: t0) ==  nil)
        #expect(try #require(r.add(parts[3], now: t0)) == bytes(300))
    }

    @Test func anUnfinishedPacketExpires() {
        let parts = Fragments.split(bytes(300), id: 4, maxWrite: 100)
        let r = Assembler()
        for p in parts.dropLast() { _ = r.add(p, now: t0) }
        #expect(r.add(parts.last!, now: at(Reassembler.timeout + 1)) == nil)
    }

    @Test func malformedFragmentsAreIgnored() {
        let r = Assembler()
        #expect(r.add(Data([0, 1, 0]), now: t0) == nil)            // short header
        #expect(r.add(Data([0, 1, 2, 2, 9]), now: t0) == nil)      // index past count
        #expect(r.add(Data([0, 1, 0, 0, 9]), now: t0) == nil)      // count 0
        #expect(r.add(Data([0, 1, 0, 1]), now: t0) == nil)         // no body
        #expect(r.inFlight == 0)
    }

    @Test func aPeerCannotMakeUsAssembleMoreThanTheCap() {
        let r = Assembler()
        // 255 fragments claimed, each 100 bytes: over the cap long before the end.
        var got: Data?
        for i in 0..<20 {
            var f = Data([0, 5, UInt8(i), 255]); f.append(bytes(96))
            got = r.add(f, now: t0) ?? got
        }
        #expect(got == nil)   // dropped at the cap; what follows starts over and is dropped again
    }

    @Test func atMostMaxPendingPacketsAreInFlight() {
        let r = Assembler()
        for id in 0..<UInt16(Reassembler.maxPending + 5) {
            _ = r.add(Fragments.split(bytes(200), id: id, maxWrite: 100)[0], now: at(Double(id)))
        }
        #expect(r.inFlight == Reassembler.maxPending)
    }

    // MARK: Locked alerts

    private let maya = newIdentity().peerID
    private func name(_ p: PeerID) -> String? { p == maya ? "Maya" : nil }

    @Test func aTextShowsWhoAndWhat() {
        let a = Alerts()
        let t = StoredText(id: UUID(), channel: UUID(), sender: maya.hex, senderName: "Maya", sentAt: t0,
                           text: "At the lodge", outgoing: false, deliveredTo: [])
        #expect(a.alert(for: .text(t), now: t0, name: name)?.title == "Maya")
        #expect(a.alert(for: .text(t), now: t0, name: name)?.body == "At the lodge")
        let mine = StoredText(id: UUID(), channel: UUID(), sender: maya.hex, senderName: "Maya", sentAt: t0,
                              text: "x", outgoing: true, deliveredTo: [])
        #expect(a.alert(for: .text(mine), now: t0, name: name) == nil)
    }

    @Test func helpAndRollCallAreTimeSensitive() {
        let a = Alerts()
        let help = a.alert(for: .help(HelpCall(at: t0, note: "twisted ankle"), from: maya, channel: .nearby), now: t0, name: name)
        #expect(help?.title == "Maya needs help" && help?.body == "twisted ankle" && help?.urgency == .timeSensitive)
        let ask = a.alert(for: .rollCall(.ask(id: UUID(), at: t0), from: maya, channel: .nearby), now: t0, name: name)
        #expect(ask?.urgency == .timeSensitive)
        #expect(a.alert(for: .rollCall(.answer(id: UUID(), ok: true), from: maya, channel: .nearby), now: t0, name: name) == nil)
    }

    @Test func aMeetupReplyIsNotANewSpot() {
        let a = Alerts()
        let spot = Meetup.spot(id: UUID(), place: "Blue gondola", latitude: nil, longitude: nil, at: t0)
        #expect(a.alert(for: .meetup(spot, from: maya, channel: .nearby), now: t0, name: name)?.body.hasPrefix("Blue gondola") == true)
        #expect(a.alert(for: .meetup(.reply(id: UUID(), coming: true), from: maya, channel: .nearby), now: t0, name: name) == nil)
    }

    @Test func isTalkingAtMostOnceAMinutePerPerson() {
        let a = Alerts()
        let press = Dispatch.Event.floor(.request(sender: maya, name: "Maya", claimedAt: t0), channel: .nearby)
        #expect(a.alert(for: press, now: t0, name: name)?.title == "Maya is talking")
        #expect(a.alert(for: press, now: at(30), name: name) == nil)
        #expect(a.alert(for: press, now: at(LockedAlerts.talkingInterval), name: name) != nil)
        #expect(a.alert(for: .floor(.release(sender: maya), channel: .nearby), now: at(200), name: name) == nil)
    }

    @Test func anUnknownPersonIsAFriendNeverAnID() {
        let a = Alerts()
        let stranger = newIdentity().peerID
        #expect(a.alert(for: .ping(from: stranger), now: t0, name: name)?.title == "A friend is looking for you")
    }

    @Test func noAlertCopyHasAnEmDash() {
        let a = Alerts()
        let events: [Dispatch.Event] = [
            .help(HelpCall(at: t0, note: ""), from: maya, channel: .nearby),
            .rollCall(.ask(id: UUID(), at: t0), from: maya, channel: .nearby),
            .ping(from: maya),
            .meetup(.spot(id: UUID(), place: "Lodge", latitude: nil, longitude: nil, at: t0), from: maya, channel: .nearby),
            .floor(.request(sender: maya, name: "Maya", claimedAt: t0), channel: .nearby),
        ]
        for e in events {
            let alert = a.alert(for: e, now: t0, name: name)
            #expect(alert != nil)
            #expect(!(alert?.title ?? "").contains("\u{2014}") && !(alert?.body ?? "").contains("\u{2014}"))
        }
    }
}

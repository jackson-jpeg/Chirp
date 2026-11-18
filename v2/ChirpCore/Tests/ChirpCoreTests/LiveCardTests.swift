import Foundation
import Testing
@testable import ChirpCore

/// `#expect` cannot call a mutating method on a local value.
private final class Pacer {
    var p = LiveCardPacer()
    func shouldPush(_ c: LiveCard, now: Date) -> Bool { p.shouldPush(c, now: now) }
}

@Suite struct LiveCardTests {
    private let maya = newIdentity().peerID
    private let stranger = newIdentity().peerID
    private func person(_ p: PeerID) -> (name: String, palette: UInt8)? { p == maya ? ("Maya", 2) : nil }
    private let start = LiveCard(birdhouse: "Ski trip", onLine: 3)

    @Test func beforeAnyoneSpeaksItShowsTheBirdhouse() {
        #expect(start.headline == "Ski trip" && start.count == "3 on the line")
        #expect(LiveCard(birdhouse: "Camp", onLine: 0).count == "Just you")
    }

    @Test func aFloorRequestShowsWhoIsTalkingAndAReleaseKeepsThemAsLast() throws {
        let talking = try #require(start.applying(.floor(.request(sender: maya, name: "Maya", claimedAt: t0), channel: .nearby), person: person))
        #expect(talking.headline == "Maya is talking" && talking.palette == 2 && talking.talking)
        let done = try #require(talking.applying(.floor(.release(sender: maya), channel: .nearby), person: person))
        #expect(done.headline == "Maya" && !done.talking)
        #expect(done.applying(.floor(.release(sender: maya), channel: .nearby), person: person) == nil)
    }

    @Test func aTextBecomesTheLineClippedAtAWord() throws {
        let long = String(repeating: "powder day ", count: 20)
        let t = StoredText(id: UUID(), channel: UUID(), sender: maya.hex, senderName: "Maya", sentAt: t0,
                           text: long, outgoing: false, deliveredTo: [])
        let card = try #require(start.applying(.text(t), person: person))
        let line = try #require(card.line)
        #expect(line.count <= LiveCard.maxLine && line.hasSuffix("\u{2026}") && line.hasPrefix("powder day"))
        #expect(!line.contains("\u{2014}"))
    }

    @Test func strangersAndMyOwnTextsNeverReachTheCard() {
        #expect(start.applying(.floor(.request(sender: stranger, name: "Mallory", claimedAt: t0), channel: .nearby), person: person) == nil)
        let mine = StoredText(id: UUID(), channel: UUID(), sender: maya.hex, senderName: "Maya", sentAt: t0,
                              text: "hi", outgoing: true, deliveredTo: [])
        #expect(start.applying(.text(mine), person: person) == nil)
        #expect(start.applying(.ping(from: maya), person: person) == nil)
    }

    @Test func helpShowsOnTheCard() throws {
        let card = try #require(start.applying(.help(HelpCall(at: t0, note: "ankle"), from: maya, channel: .nearby), person: person))
        #expect(card.line == "Needs help: ankle")
    }

    @Test func theCardRoundTripsAsActivityState() throws {
        let card = LiveCard(birdhouse: "Ski trip", onLine: 2, speaker: "Maya", palette: 2, line: "Lodge", talking: true)
        #expect(try JSONDecoder().decode(LiveCard.self, from: JSONEncoder().encode(card)) == card)
    }

    @Test func pushesAreSpacedButWhoIsTalkingGoesAtOnce() {
        let pacer = Pacer()
        let a = LiveCard(birdhouse: "Ski trip", onLine: 3, speaker: "Maya", line: "one")
        var b = a; b.line = "two"
        var c = b; c.talking = true
        #expect(pacer.shouldPush(a, now: t0))
        #expect(!pacer.shouldPush(a, now: at(10)))                 // unchanged
        #expect(pacer.shouldPush(b, now: at(10)))
        var d = b; d.line = "three"
        #expect(!pacer.shouldPush(d, now: at(11)))                 // too soon
        #expect(pacer.shouldPush(c, now: at(11)))                  // talking changed
        var e = c; e.onLine = 4
        #expect(pacer.shouldPush(e, now: at(11 + LiveCardPacer.interval)))
    }
}

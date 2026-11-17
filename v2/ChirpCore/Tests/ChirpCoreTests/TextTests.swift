import Foundation
import Testing
@testable import ChirpCore

@Suite struct TextTests {
    let alice = newIdentity(), bob = newIdentity(), mallory = newIdentity()
    let camp = ChannelID.random()

    func header(from origin: PeerID, channel: ChannelID, seq: UInt32 = 1) -> Data {
        packet(.text, from: origin, seq: seq, channel: channel).sealedHeader
    }

    @Test func signedTextsVerifyOnlyWithTheSendersKeyAndHeader() throws {
        let body = TextBody(sentAt: t0, text: "meet at the lift 🎿")
        let h = header(from: alice.peerID, channel: camp)
        let wire = try body.signedPayload(by: alice, header: h)
        let back = try #require(TextBody.verify(wire, header: h, signingKey: alice.signingPublicKey))
        #expect(back.id == body.id && back.text == body.text)
        #expect(TextBody.verify(wire, header: h, signingKey: mallory.signingPublicKey) == nil)
        #expect(TextBody.verify(wire, header: header(from: alice.peerID, channel: .nearby), signingKey: alice.signingPublicKey) == nil)
        #expect(TextBody.verify(wire.dropLast(), header: h, signingKey: alice.signingPublicKey) == nil)
    }

    @Test func longTextsAreCutOnACharacterBoundary() throws {
        let long = String(repeating: "é", count: 900)       // 1800 bytes
        let h = header(from: alice.peerID, channel: camp)
        let wire = try TextBody(sentAt: t0, text: long).signedPayload(by: alice, header: h)
        let back = try #require(TextBody.verify(wire, header: h, signingKey: alice.signingPublicKey))
        #expect(back.text.utf8.count <= TextBody.maxBytes && back.text.allSatisfy { $0 == "é" })
    }

    /// Claim H9: a device that has not joined the channel must not store or ack.
    @Test func onlyJoinedChannelsStoreAndAck() {
        var bobs = TextLedger()
        let body = TextBody(sentAt: t0, text: "hi")
        let r1 = bobs.receive(body, channel: camp, from: alice.peerID, senderName: "A", joined: [.nearby])
        #expect(r1 == .notJoined)
        #expect(bobs.texts.isEmpty)
        let r2 = bobs.receive(body, channel: camp, from: alice.peerID, senderName: "A", joined: [.nearby, camp])
        let r3 = bobs.receive(body, channel: camp, from: alice.peerID, senderName: "A", joined: [camp])
        #expect(r2 == .stored && r3 == .duplicate)
        #expect(bobs.texts.count == 1)
    }

    /// Claim H8: ticks are stored with the message and survive a relaunch.
    @Test func ticksSurviveEncodeAndDecode() throws {
        var mine = TextLedger()
        let body = TextBody(sentAt: t0, text: "hi")
        mine.recordOutgoing(body, channel: camp, me: alice.peerID, myName: "A")
        #expect(mine.texts[0].isDelivered == false)
        let ticked = mine.ack(body.id, from: bob.peerID, channel: camp, me: alice.peerID)
        #expect(ticked)
        let relaunched = try JSONDecoder().decode(TextLedger.self, from: JSONEncoder().encode(mine))
        #expect(relaunched.texts[0].isDelivered)
        #expect(relaunched == mine)
    }

    @Test func acksCountOnlyForOurTextOnItsChannelAndNotFromUs() {
        var mine = TextLedger()
        let body = TextBody(sentAt: t0, text: "hi")
        mine.recordOutgoing(body, channel: camp, me: alice.peerID, myName: "A")
        let results = [
            mine.ack(body.id, from: alice.peerID, channel: camp, me: alice.peerID),   // from us
            mine.ack(body.id, from: bob.peerID, channel: .nearby, me: alice.peerID),  // wrong channel
            mine.ack(UUID(), from: bob.peerID, channel: camp, me: alice.peerID),      // unknown text
            mine.ack(body.id, from: bob.peerID, channel: camp, me: alice.peerID),     // counts
            mine.ack(body.id, from: bob.peerID, channel: camp, me: alice.peerID),     // already counted
            mine.ack(body.id, from: mallory.peerID, channel: camp, me: alice.peerID), // a second person
        ]
        #expect(results == [false, false, false, true, false, true])
        #expect(mine.texts[0].deliveredTo.count == 2)
    }

    @Test func threadsHideBlockedPeopleAndSortByTime() {
        var l = TextLedger()
        _ = l.receive(TextBody(sentAt: at(2), text: "second"), channel: camp, from: bob.peerID, senderName: "B", joined: [camp])
        _ = l.receive(TextBody(sentAt: at(1), text: "first"), channel: camp, from: bob.peerID, senderName: "B", joined: [camp])
        _ = l.receive(TextBody(sentAt: at(3), text: "spam"), channel: camp, from: mallory.peerID, senderName: "M", joined: [camp])
        #expect(l.thread(camp, hiding: [mallory.peerID]).map(\.text) == ["first", "second"])
        #expect(l.thread(.nearby, hiding: []).isEmpty)
    }

    @Test func ackPayloadRoundTrips() {
        let id = UUID()
        #expect(Ack.messageID(in: Ack.payload(for: id)) == id)
        #expect(Ack.messageID(in: Data([1, 2])) == nil)
    }
}

import Foundation
import Testing
@testable import ChirpCore

@Suite struct FloorTests {
    let me = peer(1), them = peer(2), third = peer(3)
    let ch = ChannelID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    let other = ChannelID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

    func reduce(_ s: FloorState, _ e: FloorEvent) -> FloorOutcome {
        FloorMachine.reduce(s, on: e, me: me, myName: "Me", channel: ch)
    }
    func request(_ p: PeerID, _ t: TimeInterval, name: String = "Them") -> FloorEvent {
        .received(.request(sender: p, name: name, claimedAt: at(t)), from: p, channel: ch, at: at(t))
    }

    @Test func pressOpensTheMicAndAnnouncesReleaseClosesIt() {
        let pressed = reduce(.idle, .localPressed(at: t0))
        #expect(pressed.state.microphoneIsOpen)
        #expect(pressed.effects == [.openMicrophone, .send(.request(sender: me, name: "Me", claimedAt: t0))])
        let released = reduce(pressed.state, .localReleased)
        #expect(released.state == .idle)
        #expect(released.effects == [.closeMicrophone, .send(.release(sender: me))])
    }

    /// Audit defect 1, claim H6: a floor request on another channel must not
    /// take this channel's floor or refuse this device's button.
    @Test func anotherChannelsFloorChangesNothing() {
        let e = FloorEvent.received(.request(sender: them, name: "T", claimedAt: t0), from: them, channel: other, at: t0)
        #expect(reduce(.idle, e).state == .idle)
        let holding = reduce(.idle, .localPressed(at: t0)).state
        #expect(reduce(holding, e).state == holding)
        #expect(reduce(.idle, .heardAudio(from: them, channel: other, at: t0)).state == .idle)
    }

    @Test func aRemoteRequestOnThisChannelMeansListening() {
        let s = reduce(.idle, request(them, 0)).state
        #expect(s.speaker?.peer == them)
        let refused = reduce(s, .localPressed(at: at(1)))
        #expect(refused.state == .refused(under: s))
        #expect(refused.effects == [.startRefusalTimer(FloorMachine.refusalFeedback)])
        #expect(reduce(refused.state, .refusalExpired).state == s)
    }

    @Test func collisionTheEarlierClaimWinsAndTheLoserClosesItsMic() {
        let holding = reduce(.idle, .localPressed(at: at(1))).state
        let lost = reduce(holding, request(them, 0.5))
        #expect(lost.state.speaker?.peer == them)
        #expect(lost.effects == [.closeMicrophone])
        let won = reduce(holding, request(them, 2))
        #expect(won.state == holding)
        #expect(won.effects == [.send(.request(sender: me, name: "Me", claimedAt: at(1)))])
    }

    @Test func equalTimesBreakOnPeerIDTheSameWayOnBothSides() {
        let mine = FloorClaim(peer: me, name: "", claimedAt: t0)
        let theirs = FloorClaim(peer: them, name: "", claimedAt: t0)
        #expect(mine.beats(theirs) != theirs.beats(mine))
    }

    @Test func aMessageWhoseSenderIsNotItsVerifiedOriginIsReported() {
        let holding = reduce(.idle, .localPressed(at: t0)).state
        let forged = FloorEvent.received(.release(sender: me), from: them, channel: ch, at: t0)
        let out = reduce(holding, forged)
        #expect(out.state == holding)
        #expect(out.effects == [.reportImpersonation(claimed: me, actual: them)])
    }

    @Test func onlyTheHolderCanReleaseTheFloor() {
        let s = reduce(.idle, request(them, 0)).state
        let wrong = FloorEvent.received(.release(sender: third), from: third, channel: ch, at: at(1))
        #expect(reduce(s, wrong).state == s)
        let right = FloorEvent.received(.release(sender: them), from: them, channel: ch, at: at(1))
        #expect(reduce(s, right).state == .idle)
    }

    /// Claim H15: a lost release used to leave listeners stuck. Silence now ends it.
    @Test func aSilentSpeakerLosesTheFloorAfterTheTimeout() {
        var s = reduce(.idle, request(them, 0)).state
        s = reduce(s, .heardAudio(from: them, channel: ch, at: at(2))).state
        #expect(reduce(s, .tick(at(2 + FloorMachine.silenceTimeout - 0.1))).state == s)
        #expect(reduce(s, .tick(at(2 + FloorMachine.silenceTimeout))).state == .idle)
    }

    @Test func audioFromSomeoneElseDoesNotKeepTheSpeakerAlive() {
        let s = reduce(.idle, request(them, 0)).state
        let s2 = reduce(s, .heardAudio(from: third, channel: ch, at: at(2))).state
        #expect(reduce(s2, .tick(at(FloorMachine.silenceTimeout))).state == .idle)
    }

    @Test func theTalkCapReleasesAStuckButton() {
        let holding = reduce(.idle, .localPressed(at: t0)).state
        #expect(reduce(holding, .tick(at(FloorMachine.talkCap - 1))).state == holding)
        let capped = reduce(holding, .tick(at(FloorMachine.talkCap)))
        #expect(capped.state == .idle)
        #expect(capped.effects == [.closeMicrophone, .send(.release(sender: me))])
    }

    @Test func releasingWhileRefusedOverMyOwnTurnStillReleases() {
        let holding = reduce(.idle, .localPressed(at: t0)).state
        let refused = reduce(holding, .localPressed(at: at(0.1))).state
        #expect(refused.microphoneIsOpen)
        let out = reduce(refused, .localReleased)
        #expect(out.state == .idle && out.effects.contains(.closeMicrophone))
    }

    @Test func aGonePeerReleasesTheFloor() {
        let s = reduce(.idle, request(them, 0)).state
        #expect(reduce(s, .peerGone(third)).state == s)
        #expect(reduce(s, .peerGone(them)).state == .idle)
    }

    /// The property five 1.0 bugs broke: every transition out of an open-mic
    /// state either stays open or says closeMicrophone, and none opens the mic
    /// without saying openMicrophone.
    @Test func theMicrophoneNeverChangesWithoutAnEffect() {
        let states: [FloorState] = [
            .idle,
            reduce(.idle, .localPressed(at: t0)).state,
            reduce(.idle, request(them, 0)).state,
            .refused(under: reduce(.idle, .localPressed(at: t0)).state),
            .refused(under: reduce(.idle, request(them, 0)).state),
        ]
        let events: [FloorEvent] = [
            .localPressed(at: at(1)), .localReleased, .refusalExpired,
            request(them, -1), request(them, 5), request(third, -1),
            .received(.release(sender: them), from: them, channel: ch, at: at(1)),
            .received(.release(sender: me), from: them, channel: ch, at: at(1)),
            .received(.request(sender: them, name: "", claimedAt: t0), from: them, channel: other, at: t0),
            .heardAudio(from: them, channel: ch, at: at(1)),
            .peerGone(them), .peerGone(me), .tick(at(1)), .tick(at(10)), .tick(at(100)),
        ]
        for s in states {
            for e in events {
                let out = reduce(s, e)
                let before = s.microphoneIsOpen, after = out.state.microphoneIsOpen
                if before && !after { #expect(out.effects.contains(.closeMicrophone), "\(s) on \(e)") }
                if !before && after { #expect(out.effects.contains(.openMicrophone), "\(s) on \(e)") }
                if before == after {
                    #expect(!out.effects.contains(.openMicrophone) && !out.effects.contains(.closeMicrophone), "\(s) on \(e)")
                }
            }
        }
    }

    @Test func floorMessagesRoundTripAndRejectJunk() {
        let r = FloorMessage.request(sender: them, name: "Sam 🐦", claimedAt: Date(timeIntervalSince1970: 1_800_000_000.123))
        let back = FloorMessage.decode(r.encode())
        if case .request(let s, let n, let c) = back {
            #expect(s == them && n == "Sam 🐦" && abs(c.timeIntervalSince1970 - 1_800_000_000.123) < 0.002)
        } else { Issue.record("did not decode") }
        #expect(FloorMessage.decode(FloorMessage.release(sender: me).encode()) == .release(sender: me))
        #expect(FloorMessage.decode(Data([9]) + me.bytes) == nil)
        #expect(FloorMessage.decode(FloorMessage.release(sender: me).encode() + Data([0])) == nil)
    }
}

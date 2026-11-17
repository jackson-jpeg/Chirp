import Foundation
import Testing
@testable import ChirpCore

@Suite struct AudioSessionPolicyTests {
    let holding = FloorState.holding(FloorClaim(peer: peer(1), name: "Me", claimedAt: t0))
    let listening = FloorState.listening(FloorClaim(peer: peer(2), name: "Them", claimedAt: t0))

    /// 2.5.4: at launch, with nobody talking, nothing is open.
    @Test func nothingIsOpenAtLaunch() {
        #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true), now: t0) == .off)
    }

    @Test func theMicrophoneIsLiveOnlyWhileHoldingTheFloor() {
        #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true, floor: holding), now: t0) == .record)
        #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true, floor: listening), now: t0) == .playback)
        #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true, floor: .refused(under: listening)), now: t0) == .playback)
        #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true, floor: .refused(under: holding)), now: t0) == .record)
    }

    /// 2.5.4: in the background nothing is open, whatever the floor says.
    @Test func backgroundAndInterruptionsCloseEverything() {
        for floor in [FloorState.idle, holding, listening] {
            #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: false, floor: floor), now: t0) == .off)
            #expect(AudioSessionPolicy.need(AudioSessionInputs(foreground: true, interrupted: true, floor: floor), now: t0) == .off)
        }
    }

    @Test func playbackDrainsForAShortTailThenCloses() {
        let i = AudioSessionInputs(foreground: true, floor: .idle, lastSpeechEnded: t0)
        #expect(AudioSessionPolicy.need(i, now: at(AudioSessionPolicy.playbackTail - 0.1)) == .playback)
        #expect(AudioSessionPolicy.need(i, now: at(AudioSessionPolicy.playbackTail)) == .off)
    }

    /// The adapter is told to look again exactly when the tail runs out.
    @Test func recheckIsWhenTheTailRunsOut() {
        let i = AudioSessionInputs(foreground: true, floor: .idle, lastSpeechEnded: t0)
        #expect(AudioSessionPolicy.recheck(i, now: at(0.5)) == at(AudioSessionPolicy.playbackTail))
        #expect(AudioSessionPolicy.recheck(i, now: at(AudioSessionPolicy.playbackTail)) == nil)
    }

    /// While someone talks, or the mic is open, or nothing is open, only a new input changes the need.
    @Test func noRecheckWhileTheNeedHangsOnTheFloor() {
        for floor in [holding, listening, .refused(under: listening)] {
            let i = AudioSessionInputs(foreground: true, floor: floor, lastSpeechEnded: t0)
            #expect(AudioSessionPolicy.recheck(i, now: at(0.5)) == nil)
        }
        #expect(AudioSessionPolicy.recheck(AudioSessionInputs(foreground: true), now: t0) == nil)
        let background = AudioSessionInputs(foreground: false, lastSpeechEnded: t0)
        #expect(AudioSessionPolicy.recheck(background, now: at(0.5)) == nil)
    }
}

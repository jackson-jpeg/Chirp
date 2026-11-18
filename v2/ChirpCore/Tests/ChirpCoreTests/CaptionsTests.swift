import Foundation
import Testing
@testable import ChirpCore

@Suite struct CaptionsTests {
    /// 5.1.1(iv): reading the status at launch never asks.
    @Test func checkingTheStatusNeverAsks() {
        for p in [SpeechPermission.notAsked, .granted, .denied, .unavailable] {
            let (s, fx) = Captions.reduce(CaptionSettings(), .permissionChecked(p))
            #expect(fx.isEmpty)
            #expect(s.permission == p)
        }
    }

    /// Captions are wanted by default, but until asked the card offers them.
    @Test func theDefaultOffersCaptionsWithoutAsking() {
        let s = CaptionSettings()
        #expect(s.mode == .on)
        #expect(Captions.card(s) == .offer)
        #expect(!Captions.captioning(s))
        #expect(Captions.playsAudio(s))
    }

    @Test func theFirstTapAsksAndOnlyThen() {
        let (s1, fx1) = Captions.reduce(CaptionSettings(), .tappedCaptions)
        #expect(fx1 == [.requestPermission])
        let (s2, fx2) = Captions.reduce(s1, .permissionAnswered(granted: true))
        #expect(fx2.isEmpty)
        #expect(Captions.card(s2) == .captioning)
        let (_, fx3) = Captions.reduce(s2, .tappedCaptions)
        #expect(fx3.isEmpty)
    }

    @Test func choosingAModeAsksUnlessItIsOff() {
        #expect(Captions.reduce(CaptionSettings(), .chose(.off)).1.isEmpty)
        #expect(Captions.reduce(CaptionSettings(), .chose(.on)).1 == [.requestPermission])
        #expect(Captions.reduce(CaptionSettings(), .chose(.only)).1 == [.requestPermission])
    }

    @Test func aNoIsExplainedNotAskedAgain() {
        let (s, _) = Captions.reduce(CaptionSettings(), .permissionAnswered(granted: false))
        #expect(Captions.card(s) == .denied)
        #expect(Captions.reduce(s, .tappedCaptions).1 == [.explainDenied])
        #expect(Captions.reduce(s, .chose(.only)).1 == [.explainDenied])
    }

    /// On-device or nothing: no recognizer means no captions, and no prompt.
    @Test func withNoOnDeviceRecognizerCaptionsAreUnavailable() {
        let (s, _) = Captions.reduce(CaptionSettings(), .permissionChecked(.unavailable))
        #expect(Captions.card(s) == .unavailable)
        #expect(Captions.reduce(s, .tappedCaptions).1 == [.explainUnavailable])
        let (after, _) = Captions.reduce(s, .permissionAnswered(granted: true))
        #expect(!Captions.captioning(after))
    }

    @Test func tappingTheOfferTurnsCaptionsBackOn() {
        let off = CaptionSettings(mode: .off, permission: .granted)
        #expect(Captions.card(off) == .hidden)
        let (s, fx) = Captions.reduce(off, .tappedCaptions)
        #expect(s.mode == .on)
        #expect(fx.isEmpty)
    }

    /// Captions-only never silences a message it cannot caption.
    @Test func captionsOnlySilencesOnlyWhatIsCaptioned() {
        #expect(!Captions.playsAudio(CaptionSettings(mode: .only, permission: .granted)))
        for p in [SpeechPermission.notAsked, .denied, .unavailable] {
            #expect(Captions.playsAudio(CaptionSettings(mode: .only, permission: p)))
        }
        #expect(Captions.playsAudio(CaptionSettings(mode: .on, permission: .granted)))
        #expect(Captions.playsAudio(CaptionSettings(mode: .off, permission: .granted)))
    }

    @Test func aTrackReplacesPartialsAndClosesOnFinal() {
        var t = CaptionTrack()
        let a = JitterBuffer.Speaker(peer: peer(1), epoch: 1)
        t.update(a, text: "We got", final: false, at: t0)
        t.update(a, text: "We got a table", final: false, at: at(1))
        #expect(t.caption(for: a)?.text == "We got a table")
        t.update(a, text: "", final: true, at: at(2))
        #expect(t.caption(for: a)?.text == "We got a table")
        #expect(t.caption(for: a)?.final == true)
        t.update(a, text: "late", final: false, at: at(3))
        #expect(t.caption(for: a)?.text == "We got a table")
        #expect(t.captions.count == 1)
    }

    @Test func aNewEpochIsANewCaptionAndLatestFindsIt() {
        var t = CaptionTrack()
        t.update(.init(peer: peer(1), epoch: 1), text: "one", final: true, at: t0)
        t.update(.init(peer: peer(1), epoch: 2), text: "two", final: false, at: at(1))
        t.update(.init(peer: peer(2), epoch: 1), text: "other", final: false, at: at(2))
        #expect(t.latest(from: peer(1))?.text == "two")
        #expect(t.latest(from: peer(3)) == nil)
    }

    @Test func theSameSpeakerKeyCaptionsEveryTurnAfterBegin() {
        var t = CaptionTrack()
        let a = JitterBuffer.Speaker(peer: peer(1), epoch: 7)   // one epoch for the whole launch
        t.begin(a, at: t0)
        t.update(a, text: "first turn", final: true, at: at(1))
        t.begin(a, at: at(2))
        // The new turn starts empty: last turn's words are not shown as this one's.
        #expect(t.latest(from: peer(1))?.text == "")
        #expect(t.latest(from: peer(1))?.final == false)
        t.update(a, text: "second turn", final: false, at: at(3))
        #expect(t.latest(from: peer(1))?.text == "second turn")
        t.update(a, text: "", final: true, at: at(4))
        t.update(a, text: "late", final: false, at: at(5))
        #expect(t.latest(from: peer(1))?.text == "second turn")
        #expect(t.captions.map(\.text) == ["first turn", "second turn"])
    }

    @Test func beginTwiceOnAnEmptyTurnOpensOne() {
        var t = CaptionTrack()
        let a = JitterBuffer.Speaker(peer: peer(1), epoch: 1)
        t.begin(a, at: t0)
        t.begin(a, at: at(1))
        #expect(t.captions.count == 1)
    }

    @Test func aTrackIsCapped() {
        var t = CaptionTrack(cap: 3)
        for i in 0..<5 { t.update(.init(peer: peer(1), epoch: UInt32(i)), text: "\(i)", final: true, at: at(Double(i))) }
        #expect(t.captions.map(\.text) == ["2", "3", "4"])
    }
}

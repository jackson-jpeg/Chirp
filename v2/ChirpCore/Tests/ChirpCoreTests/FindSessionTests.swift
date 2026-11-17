import Foundation
import Testing
@testable import ChirpCore

@Suite struct FindSessionTests {
    let mine = Data([1, 1, 1])
    let theirs = Data([2, 2, 2])

    /// 5.1.1(iv): an offer never starts a session on the phone that got it.
    @Test func anOfferWhileClosedIsOnlyARequest() {
        var s = FindSession()
        #expect(s.handle(.received(.offer(token: theirs))) == [.showRequest])
        #expect(s.phase == .closed)
        #expect(s.handle(.received(.offer(token: theirs))) == [])
    }

    @Test func openingAfterTheirOfferAnswersAndRanges() {
        var s = FindSession()
        _ = s.handle(.received(.offer(token: theirs)))
        #expect(s.handle(.opened(myToken: mine)) == [.send(.answer(token: mine)), .run(peerToken: theirs)])
        #expect(s.phase == .ranging(peerToken: theirs))
    }

    @Test func openingFirstOffersThenRangesOnTheAnswer() {
        var s = FindSession()
        #expect(s.handle(.opened(myToken: mine)) == [.send(.offer(token: mine))])
        #expect(s.handle(.received(.answer(token: theirs))) == [.run(peerToken: theirs)])
        #expect(s.phase == .ranging(peerToken: theirs))
    }

    @Test func bothOpeningAtOnceStillRanges() {
        var s = FindSession()
        _ = s.handle(.opened(myToken: mine))
        #expect(s.handle(.received(.offer(token: theirs))) == [.run(peerToken: theirs)])
    }

    @Test func withoutUWBItIsFallbackOnlyAndSendsNothing() {
        var s = FindSession()
        #expect(s.handle(.opened(myToken: nil)) == [])
        #expect(s.phase == .fallbackOnly)
        #expect(s.handle(.received(.answer(token: theirs))) == [])
        #expect(s.handle(.closed) == [])
        #expect(s.phase == .closed)
    }

    @Test func closingSendsStopAndForgetsARequest() {
        var s = FindSession()
        _ = s.handle(.received(.offer(token: theirs)))
        _ = s.handle(.opened(myToken: mine))
        #expect(s.handle(.closed) == [.send(.stop), .invalidate])
        #expect(s.pendingOffer == nil)
        // A fresh open offers again rather than reusing the old token.
        #expect(s.handle(.opened(myToken: mine)) == [.send(.offer(token: mine))])
    }

    @Test func theirStopEndsRangingButKeepsFindOpen() {
        var s = FindSession()
        _ = s.handle(.opened(myToken: mine))
        _ = s.handle(.received(.answer(token: theirs)))
        #expect(s.handle(.received(.stop)) == [.invalidate])
        #expect(s.phase == .offered)
    }

    @Test func aStopWithdrawsTheirRequest() {
        var s = FindSession()
        _ = s.handle(.received(.offer(token: theirs)))
        _ = s.handle(.received(.stop))
        #expect(s.handle(.opened(myToken: mine)) == [.send(.offer(token: mine))])
    }

    @Test func aRefusedPermissionFallsBack() {
        var s = FindSession()
        _ = s.handle(.opened(myToken: mine))
        #expect(s.handle(.rangingFailed) == [.invalidate])
        #expect(s.phase == .fallbackOnly)
    }

    @Test func aReopenedFriendIsRerunOnTheirNewToken() {
        var s = FindSession()
        _ = s.handle(.opened(myToken: mine))
        _ = s.handle(.received(.answer(token: theirs)))
        let fresh = Data([3, 3])
        #expect(s.handle(.received(.offer(token: fresh))) == [.run(peerToken: fresh)])
    }

    @Test func fixesRoundMetresAndTurnRadiansToDegrees() {
        #expect(Find.fix(distance: nil, horizontalAngle: 0.5) == nil)
        #expect(Find.fix(distance: .nan, horizontalAngle: nil) == nil)
        let f = Find.fix(distance: 12.6, horizontalAngle: Float.pi / 4)!
        #expect(f.meters == 13)
        #expect(abs(f.bearing! - 45) < 0.001)
        #expect(Find.fix(distance: 3, horizontalAngle: nil)?.bearing == nil)
    }

    @Test func tapsQuickenAsTheyGetCloser() {
        #expect(Find.tapInterval(meters: 0) == 0.15)
        #expect(abs(Find.tapInterval(meters: 30) - 1.2) < 1e-9)
        #expect(abs(Find.tapInterval(meters: 500) - 1.2) < 1e-9)
        #expect(Find.tapInterval(meters: 5) < Find.tapInterval(meters: 20))
    }
}

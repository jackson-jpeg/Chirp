import Testing
@testable import ChirpCore

@Suite struct BigFlockTests {
    @Test func fourBirdsAreFree() {
        #expect(BigFlock.freeBirds == 4)
        #expect(BigFlock.birds(members: 3) == 4)
    }

    @Test func theStarterOfAFullFreeFlockIsOfferedBigFlockFirst() {
        #expect(BigFlock.invite(birds: 3, startedByMe: true, unlocked: false) == .share)
        #expect(BigFlock.invite(birds: 4, startedByMe: true, unlocked: false) == .offerBigFlock)
        #expect(BigFlock.invite(birds: 9, startedByMe: true, unlocked: false) == .offerBigFlock)
    }

    @Test func joinersNeverSeeAPriceAndOwnersAreNeverAsked() {
        #expect(BigFlock.invite(birds: 9, startedByMe: false, unlocked: false) == .share)
        #expect(BigFlock.invite(birds: 9, startedByMe: true, unlocked: true) == .share)
    }

    @Test func theCardShowsPastTheCapUntilPutAwayAtThatSize() {
        #expect(!BigFlock.showsCard(birds: 4, startedByMe: true, unlocked: false, dismissedAt: nil))
        #expect(BigFlock.showsCard(birds: 5, startedByMe: true, unlocked: false, dismissedAt: nil))
        #expect(!BigFlock.showsCard(birds: 5, startedByMe: true, unlocked: false, dismissedAt: 5))
        // One more bird than when it was put away: asked again.
        #expect(BigFlock.showsCard(birds: 6, startedByMe: true, unlocked: false, dismissedAt: 5))
        #expect(!BigFlock.showsCard(birds: 6, startedByMe: false, unlocked: false, dismissedAt: nil))
        #expect(!BigFlock.showsCard(birds: 6, startedByMe: true, unlocked: true, dismissedAt: nil))
    }

    @Test func fourColorsAndTwoChirpsAreFree() {
        #expect((0..<7).filter(BigFlock.paletteIsFree) == [0, 2, 3, 4])
        #expect((0..<3).filter(BigFlock.chirpIsFree) == [0, 1])
        // Every free index is a real choice.
        #expect(BigFlock.freePalettes.allSatisfy { $0 < Int(Bird.paletteCount) })
        #expect(BigFlock.freeChirps.allSatisfy { $0 < ChirpSound.names.count })
    }

    @Test func aChoiceNotOwnedFallsBackToAFreeOne() {
        #expect(BigFlock.allowedPalette(5, unlocked: false) == 0)
        #expect(BigFlock.allowedPalette(5, unlocked: true) == 5)
        #expect(BigFlock.allowedPalette(3, unlocked: false) == 3)
        #expect(BigFlock.allowedChirp(2, unlocked: false) == 0)
        #expect(BigFlock.allowedChirp(2, unlocked: true) == 2)
    }
}

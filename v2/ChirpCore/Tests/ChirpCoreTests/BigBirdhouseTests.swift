import Testing
@testable import ChirpCore

@Suite struct BigBirdhouseTests {
    @Test func fourBirdsAreFree() {
        #expect(BigBirdhouse.freeBirds == 4)
        #expect(BigBirdhouse.birds(members: 3) == 4)
    }

    @Test func theStarterOfAFullFreeBirdhouseIsOfferedBigBirdhouseFirst() {
        #expect(BigBirdhouse.invite(birds: 3, startedByMe: true, unlocked: false) == .share)
        #expect(BigBirdhouse.invite(birds: 4, startedByMe: true, unlocked: false) == .offerBigBirdhouse)
        #expect(BigBirdhouse.invite(birds: 9, startedByMe: true, unlocked: false) == .offerBigBirdhouse)
    }

    @Test func joinersNeverSeeAPriceAndOwnersAreNeverAsked() {
        #expect(BigBirdhouse.invite(birds: 9, startedByMe: false, unlocked: false) == .share)
        #expect(BigBirdhouse.invite(birds: 9, startedByMe: true, unlocked: true) == .share)
    }

    @Test func theCardShowsPastTheCapUntilPutAwayAtThatSize() {
        #expect(!BigBirdhouse.showsCard(birds: 4, startedByMe: true, unlocked: false, dismissedAt: nil))
        #expect(BigBirdhouse.showsCard(birds: 5, startedByMe: true, unlocked: false, dismissedAt: nil))
        #expect(!BigBirdhouse.showsCard(birds: 5, startedByMe: true, unlocked: false, dismissedAt: 5))
        // One more bird than when it was put away: asked again.
        #expect(BigBirdhouse.showsCard(birds: 6, startedByMe: true, unlocked: false, dismissedAt: 5))
        #expect(!BigBirdhouse.showsCard(birds: 6, startedByMe: false, unlocked: false, dismissedAt: nil))
        #expect(!BigBirdhouse.showsCard(birds: 6, startedByMe: true, unlocked: true, dismissedAt: nil))
    }

    @Test func fourColorsAndTwoChirpsAreFree() {
        #expect((0..<7).filter(BigBirdhouse.paletteIsFree) == [0, 2, 3, 4])
        #expect((0..<3).filter(BigBirdhouse.chirpIsFree) == [0, 1])
        // Every free index is a real choice.
        #expect(BigBirdhouse.freePalettes.allSatisfy { $0 < Int(Bird.paletteCount) })
        #expect(BigBirdhouse.freeChirps.allSatisfy { $0 < ChirpSound.names.count })
    }

    @Test func aChoiceNotOwnedFallsBackToAFreeOne() {
        #expect(BigBirdhouse.allowedPalette(5, unlocked: false) == 0)
        #expect(BigBirdhouse.allowedPalette(5, unlocked: true) == 5)
        #expect(BigBirdhouse.allowedPalette(3, unlocked: false) == 3)
        #expect(BigBirdhouse.allowedChirp(2, unlocked: false) == 0)
        #expect(BigBirdhouse.allowedChirp(2, unlocked: true) == 2)
    }
}

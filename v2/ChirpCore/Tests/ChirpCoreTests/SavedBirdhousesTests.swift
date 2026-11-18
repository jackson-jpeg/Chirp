import Testing
@testable import ChirpCore

@Suite struct SavedBirdhousesTests {
    let ski = Channel.newLocked(name: "Ski trip")
    let camp = Channel.newLocked(name: "Camping")
    let fest = Channel.newLocked(name: "Festival")

    @Test func freeAsksBeforeLeavingAndKeepsOnlyOne() {
        var saved = SavedBirdhouses()
        #expect(saved.join(ski, unlocked: false) == .use)
        saved.use(ski, started: true, unlocked: false)
        #expect(saved.join(ski, unlocked: false) == .alreadyIn)
        #expect(saved.join(camp, unlocked: false) == .askToLeave)
        saved.use(camp, started: false, unlocked: false)
        #expect(saved.current == camp)
        #expect(saved.others.isEmpty)
        #expect(saved.started.isEmpty)
    }

    @Test func bigBirdhouseKeepsTheOldOneMostRecentFirst() {
        var saved = SavedBirdhouses()
        saved.use(ski, started: true, unlocked: true)
        #expect(saved.join(camp, unlocked: true) == .use)
        saved.use(camp, started: false, unlocked: true)
        saved.use(fest, started: false, unlocked: true)
        #expect(saved.current == fest)
        #expect(saved.others.map(\.id) == [camp.id, ski.id])
        #expect(saved.started == [ski.id])
    }

    @Test func switchingBackMovesItOutOfTheKeptListAndRemembersWhoStartedIt() {
        var saved = SavedBirdhouses()
        saved.use(ski, started: true, unlocked: true)
        saved.use(camp, started: false, unlocked: true)
        #expect(!saved.startedCurrent)
        let switched = saved.switchTo(ski.id, unlocked: true)
        #expect(switched == ski)
        #expect(saved.current == ski)
        #expect(saved.startedCurrent)
        #expect(saved.others.map(\.id) == [camp.id])
    }

    @Test func withoutBigBirdhouseNothingKeptIsOffered() {
        var saved = SavedBirdhouses()
        saved.use(ski, started: false, unlocked: true)
        saved.use(camp, started: false, unlocked: true)
        // A refund: the list stays on the phone, but none of it is offered or usable.
        #expect(saved.switchable(unlocked: false).isEmpty)
        let refused = saved.switchTo(ski.id, unlocked: false)
        #expect(refused == nil)
        #expect(saved.current == camp)
        #expect(saved.switchable(unlocked: true) == [ski])
    }

    @Test func leavingDropsOnlyTheCurrentOne() {
        var saved = SavedBirdhouses()
        saved.use(ski, started: true, unlocked: true)
        saved.use(camp, started: true, unlocked: true)
        saved.leaveCurrent()
        #expect(saved.current == nil)
        #expect(saved.others == [ski])
        #expect(saved.started == [ski.id])
        #expect(saved.join(fest, unlocked: false) == .use)
    }

    @Test func atMostEightAreKeptAndTheOldestGoes() {
        var saved = SavedBirdhouses()
        let all = (0..<10).map { Channel.newLocked(name: "B\($0)") }
        for c in all { saved.use(c, started: true, unlocked: true) }
        #expect(saved.others.count == SavedBirdhouses.cap - 1)
        #expect(saved.current == all[9])
        #expect(saved.others.first == all[8])
        #expect(!saved.others.contains(all[0]) && !saved.others.contains(all[1]))
        #expect(saved.started.count == SavedBirdhouses.cap)
    }

    @Test func openChannelsAndDuplicatesAreNeverKept() {
        let open = Channel(id: .random(), name: "Open", seed: nil)
        var saved = SavedBirdhouses(current: ski, others: [ski, camp, open, camp], started: [ski.id, fest.id])
        #expect(saved.others == [camp])
        #expect(saved.started == [ski.id])
        saved.use(open, started: false, unlocked: true)
        #expect(saved.current == ski)
    }
}

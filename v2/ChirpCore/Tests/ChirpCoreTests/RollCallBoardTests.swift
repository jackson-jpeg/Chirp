import Foundation
import Testing
@testable import ChirpCore

@Suite struct RollCallBoardTests {
    let me = peer(1), jon = peer(2), maya = peer(3), priya = peer(4)
    let ch = ChannelID.nearby

    @Test func whoeverAsksIsOKAndItIsMyTurn() {
        var b = RollCallBoard()
        b.apply(.ask(id: UUID(), at: t0), from: jon, channel: ch, now: t0)
        #expect(b.status(of: jon) == .ok(at: t0))
        #expect(b.status(of: priya) == .noAnswer)
        #expect(b.waitingOn(me))
        let sent = b.answer(me: me, ok: true, now: at(5))
        #expect(sent == .answer(id: b.ask!.id, ok: true))
        #expect(b.status(of: me) == .ok(at: at(5)))
        #expect(!b.waitingOn(me))
    }

    @Test func myOwnRollCallIsNotMyTurn() {
        var b = RollCallBoard()
        let r = b.start(me: me, on: ch, now: t0)
        guard case .ask = r else { Issue.record("not an ask"); return }
        #expect(!b.waitingOn(me))
        #expect(b.status(of: me) == .ok(at: t0))
    }

    @Test func answersToAnotherRollCallAreIgnored() {
        var b = RollCallBoard()
        b.apply(.ask(id: UUID(), at: t0), from: jon, channel: ch, now: t0)
        b.apply(.answer(id: UUID(), ok: true), from: maya, channel: ch, now: at(1))
        #expect(b.status(of: maya) == .noAnswer)
    }

    @Test func aNewerAskClearsTheOldAnswersAndAnOlderOneIsIgnored() {
        var b = RollCallBoard()
        let first = UUID()
        b.apply(.ask(id: first, at: at(10)), from: jon, channel: ch, now: at(10))
        b.apply(.answer(id: first, ok: true), from: maya, channel: ch, now: at(11))
        b.apply(.ask(id: UUID(), at: at(5)), from: priya, channel: ch, now: at(12))
        #expect(b.ask?.id == first)
        b.apply(.ask(id: UUID(), at: at(20)), from: priya, channel: ch, now: at(20))
        #expect(b.ask?.from == priya)
        #expect(b.status(of: maya) == .noAnswer)
        #expect(b.waitingOn(me))
    }

    @Test func helpCountsAsNeedsHelpUntilThatPersonSaysOK() {
        var b = RollCallBoard()
        let id = UUID()
        b.apply(.ask(id: id, at: t0), from: jon, channel: ch, now: t0)
        b.apply(HelpCall(at: at(3), note: ""), from: priya)
        #expect(b.status(of: priya) == .needsHelp(at: at(3)))
        #expect(b.needingHelp(except: me) == [priya])
        b.apply(.answer(id: id, ok: true), from: priya, channel: ch, now: at(9))
        #expect(b.status(of: priya) == .ok(at: at(9)))
        #expect(b.needingHelp(except: me).isEmpty)
    }

    @Test func helpWithNoRollCallStillShowsAndMineIsNotListed() {
        var b = RollCallBoard()
        b.apply(HelpCall(at: t0, note: ""), from: maya)
        _ = b.askForHelp(me: me, now: at(1))
        #expect(b.ask == nil)
        #expect(b.needingHelp(except: me) == [maya])
        #expect(b.heardFrom == [maya, me])
    }

    @Test func oldRollCallsAndHelpCallsAreForgotten() {
        var b = RollCallBoard()
        b.apply(.ask(id: UUID(), at: t0), from: jon, channel: ch, now: t0)
        b.apply(HelpCall(at: t0, note: ""), from: maya)
        b.expire(now: at(RollCallBoard.lifetime + 1))
        #expect(b.ask == nil)
        #expect(b.help.isEmpty)
        #expect(!b.waitingOn(me))
    }

    @Test func blockingSomeoneForgetsThem() {
        var b = RollCallBoard()
        b.apply(.ask(id: UUID(), at: t0), from: jon, channel: ch, now: t0)
        b.apply(HelpCall(at: t0, note: ""), from: maya)
        b.forget(maya)
        #expect(b.help.isEmpty && b.status(of: maya) == .noAnswer)
        b.forget(jon)
        #expect(b.ask == nil)
    }
}

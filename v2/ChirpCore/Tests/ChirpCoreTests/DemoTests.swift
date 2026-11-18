import Foundation
import Testing
@testable import ChirpCore

/// The phone in Demo Mode: its own Dispatch on the demo birdhouse, fed by `DemoBirdhouse`.
private final class DemoRun {
    var me = Dispatch(identity: newIdentity(), name: "You")
    var demo = DemoBirdhouse(now: t0)
    var events: [Dispatch.Event] = []
    init() { me.join(DemoBirdhouse.channel) }

    /// Plays the demo second by second up to `seconds`, feeding everything both ways.
    func play(to seconds: Int) {
        for s in 0...seconds {
            let now = at(Double(s))
            for p in demo.tick(now: now) { take(p, now: now) }
            if let presence = try? me.presence(now: now) { _ = demo.receive(presence, now: now) }
        }
    }
    func take(_ p: Packet, now: Date) {
        let out = me.receive(p, from: p.origin, now: now)
        events += out.events
        for b in out.broadcast { _ = demo.receive(b, now: now) }
    }
    func send(_ words: String, at s: Double) {
        let now = at(s)
        guard let t = try? me.text(words, on: DemoBirdhouse.channel.id, now: now) else { return }
        for back in demo.receive(t, now: now) { take(back, now: now) }
    }
}

@Suite struct DemoTests {
    @Test func theDemoBirdhouseIsNeverOnTheAir() {
        #expect(SendGate.isDemo(DemoBirdhouse.channel.id) && DemoBirdhouse.channel.isLocked)
        let run = DemoRun()
        run.play(to: 0)
        let p = try? run.me.text("hi", on: DemoBirdhouse.channel.id, now: t0)
        #expect(p.map { SendGate.allowsSend($0, sandboxed: false) } == false)
    }

    @Test func thePretendFriendsArriveThroughTheRealReceivePath() {
        let run = DemoRun()
        run.play(to: 3)
        let names = run.events.compactMap { e -> String? in if case .presence(let p) = e { return p.name }; return nil }
        #expect(Set(names) == ["Maya", "Jon", "Priya"])
        #expect(run.me.friends == Set(run.demo.ids))   // the locked demo birdhouse makes them friends
    }

    @Test func aLoopPlaysTalkTextsMeetupAndRollCallOnce() {
        let run = DemoRun()
        run.play(to: Int(DemoBirdhouse.cycle) - 1)
        var talks = 0, releases = 0, texts: [String] = [], meetups = 0, rollCalls = 0
        for e in run.events {
            switch e {
            case .floor(.request, _): talks += 1
            case .floor(.release, _): releases += 1
            case .text(let t): texts.append(t.text)
            case .meetup: meetups += 1
            case .rollCall: rollCalls += 1
            default: break
            }
        }
        #expect(talks == 1 && releases == 1 && meetups == 1 && rollCalls == 1)
        #expect(texts == ["We got a table by the fire. Lodge, second floor, come up when you're done.",
                          "Lift 4 in 10?", "Grabbing the boards first, 15 min"])
    }

    @Test func itLoops() {
        let run = DemoRun()
        run.play(to: Int(DemoBirdhouse.cycle * 2) - 1)
        let texts = run.events.filter { if case .text = $0 { return true }; return false }.count
        #expect(texts == 6)
    }

    @Test func myTextIsHeardByAllThree() {
        let run = DemoRun()
        run.play(to: 3)
        run.send("On my way, save me a seat", at: 4)
        let mine = run.me.ledger.texts.last
        #expect(mine?.outgoing == true && mine?.deliveredTo.count == 3)
    }

    @Test func jonAsksForARollCallAndMayaAnswers() {
        let run = DemoRun()
        run.play(to: 51)
        var asks: [UUID] = [], answers: [UUID] = []
        for e in run.events {
            if case .rollCall(.ask(let id, _), _, _) = e { asks.append(id) }
            if case .rollCall(.answer(let id, true), _, _) = e { answers.append(id) }
        }
        #expect(asks.count == 1)
        #expect(answers == asks)
    }

    @Test func thePretendFriendsAnswerMyRollCallButPriya() {
        let run = DemoRun()
        run.play(to: 5)
        let id = UUID()
        guard let ask = try? run.me.make(.rollCall, on: DemoBirdhouse.channel.id,
                                         body: RollCall.ask(id: id, at: at(6)).encode(), now: at(6)) else {
            Issue.record("could not make the roll call"); return
        }
        let back = run.demo.receive(ask, now: at(6))
        for p in back { run.take(p, now: at(6)) }
        let answered = run.events.compactMap { e -> PeerID? in
            if case .rollCall(.answer(id, true), let from, _) = e { return from }
            return nil
        }
        #expect(Set(answered) == Set([run.demo.ids[0], run.demo.ids[1]]))
    }
}

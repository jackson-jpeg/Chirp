import Foundation
import Testing
@testable import ChirpCore

/// The phone in Demo Mode: its own Dispatch on the demo flock, fed by `DemoFlock`.
private final class DemoRun {
    var me = Dispatch(identity: newIdentity(), name: "You")
    var demo = DemoFlock(now: t0)
    var events: [Dispatch.Event] = []
    init() { me.join(DemoFlock.channel) }

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
        guard let t = try? me.text(words, on: DemoFlock.channel.id, now: now) else { return }
        for back in demo.receive(t, now: now) { take(back, now: now) }
    }
}

@Suite struct DemoTests {
    @Test func theDemoFlockIsNeverOnTheAir() {
        #expect(SendGate.isDemo(DemoFlock.channel.id) && DemoFlock.channel.isLocked)
        let run = DemoRun()
        run.play(to: 0)
        let p = try? run.me.text("hi", on: DemoFlock.channel.id, now: t0)
        #expect(p.map { SendGate.allowsSend($0, sandboxed: false) } == false)
    }

    @Test func thePretendFriendsArriveThroughTheRealReceivePath() {
        let run = DemoRun()
        run.play(to: 3)
        let names = run.events.compactMap { e -> String? in if case .presence(let p) = e { return p.name }; return nil }
        #expect(Set(names) == ["Maya", "Jon", "Priya"])
        #expect(run.me.friends == Set(run.demo.ids))   // the locked demo flock makes them friends
    }

    @Test func aLoopPlaysTalkTextsMeetupAndRollCallOnce() {
        let run = DemoRun()
        run.play(to: Int(DemoFlock.cycle) - 1)
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
        run.play(to: Int(DemoFlock.cycle * 2) - 1)
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
}

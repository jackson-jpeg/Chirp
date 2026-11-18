import Foundation

/// Demo Mode (App Review 2.1(a)): a reviewer with one phone sees the app work.
///
/// The pretend friends are real `Dispatch` values with their own keys. What
/// they send are real packets (signed presence, membership, talking, texts,
/// a meet-up, a roll call), and the app hands them to its own `Dispatch`
/// through the same receive path as packets off the air. What the app sends
/// on the demo channel goes back to them, so its texts get real ticks.
///
/// The demo birdhouse is a locked channel whose ID starts "DEMO", so `SendGate`
/// keeps every packet on it off the radio, and the app runs Demo Mode only
/// with the transport sandboxed: nothing of it reaches a real phone nearby.
/// It has no voice (no audio frames): "Maya is talking" shows, then her words
/// arrive as a text.
public struct DemoBirdhouse: Sendable {
    /// The demo birdhouse: locked (so its people are friends: ping, battery and
    /// Find work in the demo), with a fixed key that is no secret.
    public static let channel = Channel(id: SendGate.demoChannel(1), name: "Ski trip", seed: Data(repeating: 0x5A, count: Channel.seedLength))

    /// One loop of the script, then it starts again.
    public static let cycle: TimeInterval = 60
    public static let presenceInterval: TimeInterval = 3

    struct Line: Sendable {
        let at: TimeInterval
        let who: Int
        let what: What
    }
    enum What: Sendable {
        /// Holds the floor for `seconds`, then lets go and the words arrive as a text.
        case talk(seconds: TimeInterval, words: String)
        case release(words: String)
        case text(String)
        case meetup(place: String, inMinutes: Double)
        case rollCall
    }

    /// Maya, Jon and Priya, as on the design's screens.
    public private(set) var people: [Dispatch]
    private let script: [Line] = [
        Line(at: 4, who: 0, what: .talk(seconds: 4, words: "We got a table by the fire. Lodge, second floor, come up when you're done.")),
        Line(at: 16, who: 1, what: .text("Lift 4 in 10?")),
        Line(at: 28, who: 2, what: .text("Grabbing the boards first, 15 min")),
        Line(at: 38, who: 1, what: .meetup(place: "Bottom of the blue gondola", inMinutes: 25)),
        Line(at: 50, who: 1, what: .rollCall),
    ]
    private let started: Date
    private var lastPresence: Date?
    /// How far into the script it has played, over all loops.
    private var played: TimeInterval = -1

    public init(now: Date) {
        let cast: [(String, UInt8)] = [("Maya", 2), ("Jon", 4), ("Priya", 5)]
        people = cast.map { name, palette in
            let id = LocalIdentity(signingKey: .init(), agreementKey: .init())
            var d = Dispatch(identity: id, name: name, bird: Bird(palette: palette, chirp: palette % Bird.chirpCount) ?? .default)
            d.join(DemoBirdhouse.channel)
            return d
        }
        started = now
    }

    public var ids: [PeerID] { people.map(\.me) }

    /// What the pretend friends send by `now`: presence every few seconds,
    /// membership, and any scripted line that has come due.
    public mutating func tick(now: Date) -> [Packet] {
        var out: [Packet] = []
        if lastPresence.map({ now.timeIntervalSince($0) >= Self.presenceInterval }) ?? true {
            lastPresence = now
            for i in people.indices {
                if let p = try? people[i].presence(now: now) { out.append(p) }
                out += people[i].memberships(now: now)
            }
        }
        let elapsed = now.timeIntervalSince(started)
        for line in due(after: played, upTo: elapsed) {
            out += perform(line, now: now)
        }
        played = max(played, elapsed)
        return out
    }

    /// The scripted steps whose time falls in (from, to], across loops; a
    /// talk adds its release `seconds` later.
    private func due(after from: TimeInterval, upTo to: TimeInterval) -> [Line] {
        guard to > from else { return [] }
        var steps: [(TimeInterval, Line)] = []
        var loop = max(0, floor(from / Self.cycle))
        while loop * Self.cycle <= to {
            for line in script {
                let t = loop * Self.cycle + line.at
                if t > from && t <= to { steps.append((t, line)) }
                if case .talk(let secs, let words) = line.what, t + secs > from, t + secs <= to {
                    steps.append((t + secs, Line(at: line.at + secs, who: line.who, what: .release(words: words))))
                }
            }
            loop += 1
        }
        return steps.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private mutating func perform(_ line: Line, now: Date) -> [Packet] {
        let ch = Self.channel.id
        var d = people[line.who]
        defer { people[line.who] = d }
        var out: [Packet?] = []
        switch line.what {
        case .talk:
            out.append(try? d.floor(.request(sender: d.me, name: d.name, claimedAt: now), on: ch, now: now))
        case .release(let words):
            out.append(try? d.floor(.release(sender: d.me), on: ch, now: now))
            out.append(try? d.text(words, on: ch, now: now))
        case .text(let words):
            out.append(try? d.text(words, on: ch, now: now))
        case .meetup(let place, let minutes):
            let spot = Meetup.spot(id: UUID(), place: place, latitude: nil, longitude: nil, at: now.addingTimeInterval(minutes * 60))
            out.append(try? d.make(.meetup, on: ch, body: spot.encode(), now: now))
        case .rollCall:
            let id = UUID()
            out.append(try? d.make(.rollCall, on: ch, body: RollCall.ask(id: id, at: now).encode(), now: now))
            // Maya answers at once; Priya is out of range, as on the design's screen.
            if line.who != 0 {
                out.append(try? people[0].make(.rollCall, on: ch, body: RollCall.answer(id: id, ok: true).encode(), now: now))
            }
        }
        return out.compactMap { $0 }
    }

    /// Who answers a roll call the real phone starts: everyone but Priya.
    static let answersRollCall = [0, 1]

    /// A packet from the real phone. Each pretend friend takes it as from the
    /// air; what they answer (acks for its texts) goes back to the phone.
    public mutating func receive(_ packet: Packet, now: Date) -> [Packet] {
        var out: [Packet] = []
        for i in people.indices {
            let o = people[i].receive(packet, from: packet.origin, now: now)
            out += o.broadcast
            for case .rollCall(.ask(let id, _), _, let channel) in o.events where Self.answersRollCall.contains(i) {
                if let a = try? people[i].make(.rollCall, on: channel, body: RollCall.answer(id: id, ok: true).encode(), now: now) {
                    out.append(a)
                }
            }
        }
        return out
    }
}

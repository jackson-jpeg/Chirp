import Foundation

/// What a phone knows about the roll call on its flock: the latest "everyone
/// OK?", who answered what and when, and anyone who asked for help.
///
/// - A newer ask replaces the old one and clears every answer, yours too.
/// - Whoever asked counts as OK at the moment they asked.
/// - A help call counts as "needs help" on the current roll call, and is kept
///   on its own (for the banner) until that person answers OK or it is old.
/// - Everything is forgotten after `lifetime`: a roll call from this morning
///   is not one to answer now.
public struct RollCallBoard: Equatable, Sendable {
    public static let lifetime: TimeInterval = 30 * 60

    public struct Ask: Equatable, Sendable {
        public let id: UUID
        public let from: PeerID
        public let at: Date
        public let channel: ChannelID
    }

    public enum Status: Equatable, Sendable {
        case noAnswer
        case ok(at: Date)
        case needsHelp(at: Date)
    }

    public private(set) var ask: Ask?
    private var answers: [PeerID: Status] = [:]
    /// The newest help call from each person still asking.
    public private(set) var help: [PeerID: HelpCall] = [:]

    public init() {}

    // MARK: In

    public mutating func apply(_ r: RollCall, from peer: PeerID, channel: ChannelID, now: Date) {
        switch r {
        case .ask(let id, let at):
            if let ask, ask.id == id || ask.at > at { return }
            ask = Ask(id: id, from: peer, at: at, channel: channel)
            answers = [peer: .ok(at: at)]
            help[peer] = nil
        case .answer(let id, let ok):
            guard id == ask?.id else { return }
            answers[peer] = ok ? .ok(at: now) : .needsHelp(at: now)
            if ok { help[peer] = nil }
        }
    }

    public mutating func apply(_ h: HelpCall, from peer: PeerID) {
        if let old = help[peer], old.at > h.at { return }
        help[peer] = h
        if ask != nil { answers[peer] = .needsHelp(at: h.at) }
    }

    // MARK: Me

    /// I start a roll call on `channel`; returns what to send.
    public mutating func start(me: PeerID, on channel: ChannelID, now: Date, id: UUID = UUID()) -> RollCall {
        let r = RollCall.ask(id: id, at: now)
        apply(r, from: me, channel: channel, now: now)
        return r
    }

    /// My answer to the current roll call, recorded and returned to send;
    /// nil when there is none to answer.
    public mutating func answer(me: PeerID, ok: Bool, now: Date) -> RollCall? {
        guard let ask else { return nil }
        let r = RollCall.answer(id: ask.id, ok: ok)
        apply(r, from: me, channel: ask.channel, now: now)
        return r
    }

    /// I ask for help: recorded like anyone's, returned to send.
    public mutating func askForHelp(me: PeerID, note: String = "", now: Date) -> HelpCall {
        let h = HelpCall(at: now, note: note)
        apply(h, from: me)
        return h
    }

    // MARK: Reading

    public func status(of peer: PeerID) -> Status { answers[peer] ?? .noAnswer }

    /// Everyone with an answer or a help call, for the tiles beside the flock.
    public var heardFrom: Set<PeerID> { Set(answers.keys).union(help.keys) }

    /// My turn: a roll call someone else started that I have not answered.
    public func waitingOn(_ me: PeerID) -> Bool {
        guard let ask, ask.from != me else { return false }
        return answers[me] == nil
    }

    /// Who asked for help, oldest first, never me.
    public func needingHelp(except me: PeerID) -> [PeerID] {
        help.filter { $0.key != me }.sorted { $0.value.at < $1.value.at }.map(\.key)
    }

    public mutating func expire(now: Date) {
        if let a = ask, now.timeIntervalSince(a.at) > Self.lifetime {
            ask = nil
            answers = [:]
        }
        let fresh = help.filter { now.timeIntervalSince($0.value.at) <= Self.lifetime }
        if fresh.count != help.count { help = fresh }
    }

    /// A blocked person's answers and help calls go.
    public mutating func forget(_ peer: PeerID) {
        answers[peer] = nil
        help[peer] = nil
        if ask?.from == peer { ask = nil; answers = [:] }
    }
}

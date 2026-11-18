import ChirpCore
import Foundation
import Observation

/// The app's side of dispatch: one ChirpCore `Dispatch`, fed every packet
/// the transport hands over, with what it returns sent back out and its
/// events applied to the birdhouse.
///
/// - Relay copies go to every link but the one they came in on; acks to
///   every link; catch-up answers only to the phone that asked.
/// - A signed presence goes out every `presenceInterval` while the radio
///   runs, so other phones learn this phone's keys (no presence, no message).
/// - Nothing here starts the radio: that is still the first hold to talk
///   (5.1.1(iv)).
@MainActor
@Observable
final class Mesh {
    static let presenceInterval: Duration = .seconds(3)

    private(set) var dispatch: Dispatch
    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private weak var birdhouse: Birdhouse?
    /// Events the birdhouse does not take (audio, floor, ping, Find, photos),
    /// for the audio engine and the screens that use them.
    @ObservationIgnored var onEvent: ((Dispatch.Event) -> Void)?
    /// Someone not heard for a while went out of range (the floor lets go of them).
    @ObservationIgnored var onPeerGone: ((PeerID) -> Void)?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    /// True while the app is not on screen: what arrives (over Bluetooth)
    /// becomes a notification instead.
    @ObservationIgnored var inBackground = false
    @ObservationIgnored private var alerts = LockedAlerts()
    /// The Lock Screen and Dynamic Island card (item 7).
    @ObservationIgnored let liveCard = LiveCardController()

    /// Friends whose Find is open on you ("Maya is looking for you").
    private(set) var lookingForYou: Set<PeerID> = []
    /// The Find screen that is open, and on whom. Find packets from that
    /// friend go to it; an offer from anyone else waits in `pendingFind`
    /// until you open Find on them.
    @ObservationIgnored private weak var finding: FindRanging?
    @ObservationIgnored private var findingPeer: PeerID?
    @ObservationIgnored private var pendingFind: [PeerID: Find.Message] = [:]

    /// Friends' check-ins: where each one is, until they stop or it runs out.
    /// Memory only.
    private(set) var checkIns = CheckInBoard()

    /// The birdhouse's roll call and anyone asking for help. Memory only.
    private(set) var rollCalls = RollCallBoard()
    /// The last ping from a friend, for Talk's "Maya pinged you" line.
    private(set) var lastPing: (from: PeerID, at: Date)?

    /// Your birdhouse: the locked channel you started or joined by invite (one at
    /// a time in 2.0). Its key is kept in the Keychain, as the invite link.
    private(set) var birdhouseChannel: Channel?
    @ObservationIgnored private let birdhouseStore: BirdhouseStore?

    /// The channel Talk and Chat are on: the demo birdhouse while the demo runs,
    /// else your birdhouse, else Nearby.
    var talkChannel: ChannelID {
        if inDemo { return DemoBirdhouse.channel.id }
        return birdhouseChannel?.id ?? .nearby
    }

    /// You started your birdhouse rather than joined it. Only the starter is
    /// ever asked about Big Birdhouse (joiners never see a price).
    private(set) var startedBirdhouse = false
    private static let startedKey = "startedBirdhouseID"

    /// Birds in your birdhouse as this phone sees it: you plus everyone proved on
    /// it, never anyone blocked (ChirpCore `BigBirdhouse`).
    var birdhouseBirds: Int {
        guard let id = birdhouseChannel?.id else { return 1 }
        return BigBirdhouse.birds(members: (dispatch.members[id] ?? []).subtracting(dispatch.blocked).count)
    }

    /// Starts using `channel` as your birdhouse (nil leaves it), and keeps it.
    func setBirdhouse(_ channel: Channel?, started: Bool = false) {
        if let old = birdhouseChannel, old.id != channel?.id { dispatch.leave(old.id) }
        birdhouseChannel = channel
        if let channel { dispatch.join(channel) }
        birdhouseStore?.save(channel)
        startedBirdhouse = channel != nil && started
        guard birdhouseStore != nil else { return }
        if let channel, started {
            UserDefaults.standard.set(channel.id.uuid.uuidString, forKey: Self.startedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.startedKey)
        }
    }

    init(identity: LocalIdentity, birdhouse: Birdhouse, transport: Transport, birdhouseStore: BirdhouseStore? = nil) {
        let you = birdhouse.you
        dispatch = Dispatch(identity: identity, name: you.name,
                            bird: Bird(palette: UInt8(you.palette.index), chirp: UInt8(you.chirp)) ?? .default)
        self.transport = transport
        self.birdhouse = birdhouse
        self.birdhouseStore = birdhouseStore
        if let saved = birdhouseStore?.load() {
            birdhouseChannel = saved
            dispatch.join(saved)
            startedBirdhouse = UserDefaults.standard.string(forKey: Self.startedKey) == saved.id.uuid.uuidString
        }
        transport.onPacket = { [weak self] packet, link in self?.receive(packet, from: link) }
        syncBlocked()
    }

    // MARK: In

    func receive(_ packet: Packet, from link: PeerID) {
        syncBlocked()
        let out = dispatch.receive(packet, from: link, now: .now)
        if let relay = out.relay { transport.send(relay, except: link) }
        for p in out.broadcast { emit(p) }
        for p in out.reply { transport.send(p, to: link) }
        for e in out.events {
            liveCard.apply(e) { [dispatch] peer in
                dispatch.roster.person(peer).map { ($0.name, $0.bird.palette) }
            }
            if inBackground,
               let alert = alerts.alert(for: e, now: .now, name: { [dispatch] in dispatch.roster.person($0)?.name }) {
                Notifier.post(alert)
            }
            if case .find(let m, let from) = e {
                routeFind(m, from: from)
            } else if case .checkIn(let m, let from, let channel) = e {
                checkIns.apply(m, from: from, channel: channel, now: .now)
            } else if case .rollCall(let r, let from, let channel) = e {
                rollCalls.apply(r, from: from, channel: channel, now: .now)
            } else if case .help(let h, let from, _) = e {
                rollCalls.apply(h, from: from)
            } else if case .ping(let from) = e {
                lastPing = (from, .now)
                if !inBackground { ChirpPlayer.ping(dispatch.roster.person(from).map { Int($0.bird.chirp) } ?? 0) }
            } else if birdhouse?.apply(e) != true {
                onEvent?(e)
            }
        }
    }

    // MARK: Find

    /// Find opened on `peer`: its exchange goes out on the whisper channel,
    /// and an offer that came while it was closed is handed over first, so
    /// opening answers it.
    func attach(_ ranging: FindRanging, to peer: PeerID) {
        finding = ranging
        findingPeer = peer
        lookingForYou.remove(peer)
        ranging.send = { [weak self] m in
            self?.send { try $0.toFriend(.find, m.encode(), peer: peer, now: .now) }
        }
        if let waiting = pendingFind.removeValue(forKey: peer) { ranging.received(waiting) }
    }

    func detach(_ ranging: FindRanging) {
        guard finding === ranging else { return }
        finding = nil
        findingPeer = nil
    }

    private func routeFind(_ m: Find.Message, from peer: PeerID) {
        if peer == findingPeer, let finding {
            finding.received(m)
            return
        }
        switch m {
        case .offer:
            pendingFind[peer] = m
            lookingForYou.insert(peer)
        case .stop:
            pendingFind[peer] = nil
            lookingForYou.remove(peer)
        case .answer:
            break   // an answer to a Find this phone no longer has open
        }
    }

    /// What the line knows about `peer`, for Find without a precision fix.
    func fallback(for peer: PeerID?) -> Find.Fallback {
        Find.fallback(for: peer.flatMap { dispatch.roster.person($0) }, lastSeen: nil, now: .now)
    }

    // MARK: Out

    /// Your name and bird, after Make your bird changes them.
    func youChanged(_ you: Person) {
        dispatch.name = you.name
        dispatch.bird = Bird(palette: UInt8(you.palette.index), chirp: UInt8(you.chirp)) ?? dispatch.bird
    }

    /// The birdhouse owns the block list (and saves it); dispatch follows it, so a
    /// block applies to the router, relaying and catch-up from the next packet.
    private func syncBlocked() {
        guard let birdhouse else { return }
        let wanted = Set(birdhouse.blockedIDs.compactMap(PeerID.init(hex:)))
        if wanted != dispatch.blocked { dispatch.setBlocked(wanted) }
        for p in wanted where checkIns.entries[p] != nil { checkIns.forget(p) }
        for p in wanted where rollCalls.heardFrom.contains(p) || rollCalls.ask?.from == p { rollCalls.forget(p) }
    }

    // MARK: Check-in

    /// A check-in goes to the locked channels this phone is on (the birdhouse),
    /// never Nearby or an open channel. With none, there is no one to share with.
    var canCheckIn: Bool { !dispatch.birdhouseChannels.isEmpty }

    func sendCheckIn(latitude: Double, longitude: Double, accuracy: Double, state: CheckInState) {
        for channel in dispatch.birdhouseChannels {
            send { try $0.checkInPosition(latitude: latitude, longitude: longitude, accuracyMetres: accuracy,
                                          on: channel, state: state, now: .now) }
        }
    }

    func sendCheckInStopped() {
        for channel in dispatch.birdhouseChannels {
            send { try $0.checkInStopped(on: channel, now: .now) }
        }
    }

    /// A friend's check-in still running, by their `Person`.
    func checkIn(of person: Person) -> CheckInBoard.Entry? {
        person.peer.flatMap { checkIns.position(of: $0, now: .now) }
    }

    // MARK: Roll call and help

    /// Roll call and help go to your birdhouse (or the demo birdhouse), never Nearby.
    var rollCallChannel: ChannelID? { talkChannel == .nearby ? nil : talkChannel }

    /// "Everyone OK?" to the birdhouse.
    func startRollCall() {
        guard let ch = rollCallChannel else { return }
        let r = rollCalls.start(me: dispatch.me, on: ch, now: .now)
        send { try $0.make(.rollCall, on: ch, body: r.encode(), now: .now) }
    }

    /// Your answer to the roll call on screen.
    func answerRollCall(ok: Bool) {
        guard let r = rollCalls.answer(me: dispatch.me, ok: ok, now: .now),
              let ch = rollCalls.ask?.channel else { return }
        send { try $0.make(.rollCall, on: ch, body: r.encode(), now: .now) }
    }

    /// "I need help" to the birdhouse: its own packet kind, so relays send it first.
    func askForHelp() {
        guard let ch = rollCallChannel else { return }
        let h = rollCalls.askForHelp(me: dispatch.me, now: .now)
        send { try $0.make(.help, on: ch, body: h.encode(), now: .now) }
        if rollCalls.ask != nil { answerRollCall(ok: false) }
    }

    /// Help no longer needed: said as "I'm OK", which clears it everywhere.
    func cancelHelp() {
        if rollCalls.ask == nil, let ch = rollCallChannel {
            // No roll call to answer: start one, which counts you as OK and
            // asks the others at the same time.
            let r = rollCalls.start(me: dispatch.me, on: ch, now: .now)
            send { try $0.make(.rollCall, on: ch, body: r.encode(), now: .now) }
        } else {
            answerRollCall(ok: true)
        }
    }

    @discardableResult
    func sendText(_ words: String, on channel: ChannelID = .nearby) -> Bool {
        guard let p = try? dispatch.text(words, on: channel, now: .now) else { return false }
        emit(p)
        if let stored = dispatch.ledger.texts.last { birdhouse?.texts.append(stored) }
        return true
    }

    func send(_ make: (inout Dispatch) throws -> Packet) {
        syncBlocked()
        guard let p = try? make(&dispatch) else { return }
        emit(p)
    }

    // MARK: Presence

    /// Starts the presence heartbeat; called when the radio starts.
    func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                // Strong only for one beat: holding `self` across the sleep
                // would keep the Mesh alive for as long as the loop runs.
                guard self?.beat() != nil else { return }
                try? await Task.sleep(for: Mesh.presenceInterval)
            }
        }
    }

    /// One heartbeat: a fresh presence, and people not heard lately leave.
    private func beat() {
        guard transport.running else { return }
        send { try $0.presence(now: .now) }
        // "I am on this channel" on each locked channel: how its people become
        // friends (ping, battery, Find) before anyone says anything.
        for p in dispatch.memberships(now: .now) { transport.send(p) }
        for gone in dispatch.prune(now: .now) {
            birdhouse?.left(gone)
            onPeerGone?(gone)
        }
        if !checkIns.entries.isEmpty { checkIns.expire(now: .now) }
        rollCalls.expire(now: .now)
        // Started here, so only while the app is open and the radio is on.
        if let birdhouse {
            liveCard.start(birdhouse: birdhouse.birdhouseName, onLine: dispatch.roster.visible(excluding: dispatch.blocked).count)
        }
    }

    // MARK: Demo Mode (App Review 2.1(a))

    @ObservationIgnored private var demo: DemoBirdhouse?
    @ObservationIgnored private var demoLoop: Task<Void, Never>?
    /// Stored (not derived from `demo`, which observation ignores) so Talk's
    /// demo banner appears and goes with it.
    private(set) var inDemo = false

    /// Pretend friends on the demo birdhouse, entering through `receive` like
    /// packets off the air. The radio is sandboxed first, so nothing of the
    /// demo (or anything else) reaches a real phone while it runs.
    func startDemo() {
        guard demo == nil else { return }
        transport.sandboxed = true
        dispatch.join(DemoBirdhouse.channel)
        demo = DemoBirdhouse(now: .now)
        inDemo = true
        demoLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.demoBeat() != nil else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopDemo() {
        demoLoop?.cancel()
        demoLoop = nil
        demo = nil
        inDemo = false
        dispatch.leave(DemoBirdhouse.channel.id)
        transport.sandboxed = false
    }

    private func demoBeat() {
        guard var d = demo else { return }
        let now = Date.now
        let packets = d.tick(now: now)
        // They learn my keys from my presence, as a real phone would.
        if let mine = try? dispatch.presence(now: now) { _ = d.receive(mine, now: now) }
        demo = d
        for p in packets { receive(p, from: p.origin) }
    }

    /// Out to the radio, and in Demo Mode to the pretend friends too, whose
    /// answers (ticks) come back through `receive`.
    private func emit(_ p: Packet) {
        transport.send(p)
        guard var d = demo else { return }
        let back = d.receive(p, now: .now)
        demo = d
        for b in back { receive(b, from: b.origin) }
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }
}

import ChirpCore
import Foundation
import Observation

/// The app's side of dispatch: one ChirpCore `Dispatch`, fed every packet
/// the transport hands over, with what it returns sent back out and its
/// events applied to the flock.
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
    @ObservationIgnored private weak var flock: Flock?
    /// Events the flock does not take (audio, floor, ping, Find, photos),
    /// for the audio engine and the screens that use them.
    @ObservationIgnored var onEvent: ((Dispatch.Event) -> Void)?
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

    init(identity: LocalIdentity, flock: Flock, transport: Transport) {
        let you = flock.you
        dispatch = Dispatch(identity: identity, name: you.name,
                            bird: Bird(palette: UInt8(you.palette.index), chirp: UInt8(you.chirp)) ?? .default)
        self.transport = transport
        self.flock = flock
        transport.onPacket = { [weak self] packet, link in self?.receive(packet, from: link) }
        syncBlocked()
    }

    // MARK: In

    func receive(_ packet: Packet, from link: PeerID) {
        syncBlocked()
        let out = dispatch.receive(packet, from: link, now: .now)
        if let relay = out.relay { transport.send(relay, except: link) }
        for p in out.broadcast { transport.send(p) }
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
            } else if flock?.apply(e) != true {
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

    /// The flock owns the block list (and saves it); dispatch follows it, so a
    /// block applies to the router, relaying and catch-up from the next packet.
    private func syncBlocked() {
        guard let flock else { return }
        let wanted = Set(flock.blockedIDs.compactMap(PeerID.init(hex:)))
        if wanted != dispatch.blocked { dispatch.setBlocked(wanted) }
    }

    @discardableResult
    func sendText(_ words: String, on channel: ChannelID = .nearby) -> Bool {
        guard let p = try? dispatch.text(words, on: channel, now: .now) else { return false }
        transport.send(p)
        if let stored = dispatch.ledger.texts.last { flock?.texts.append(stored) }
        return true
    }

    func send(_ make: (inout Dispatch) throws -> Packet) {
        syncBlocked()
        guard let p = try? make(&dispatch) else { return }
        transport.send(p)
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
        for gone in dispatch.prune(now: .now) { flock?.left(gone) }
        // Started here, so only while the app is open and the radio is on.
        if let flock {
            liveCard.start(flock: flock.flockName, onLine: dispatch.roster.visible(excluding: dispatch.blocked).count)
        }
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }
}

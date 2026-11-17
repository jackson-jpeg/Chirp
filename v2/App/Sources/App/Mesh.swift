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
            if flock?.apply(e) != true { onEvent?(e) }
        }
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
                guard let self else { return }
                if self.transport.running {
                    self.send { try $0.presence(now: .now) }
                    for gone in self.dispatch.prune(now: .now) { self.flock?.left(gone) }
                }
                try? await Task.sleep(for: Self.presenceInterval)
            }
        }
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }
}

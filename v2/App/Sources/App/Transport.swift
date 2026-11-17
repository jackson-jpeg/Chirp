import ChirpCore
import Foundation
import Network
import Observation
import SwiftUI

/// The radio: Bonjour with peer-to-peer Wi-Fi and TCP, on the Network
/// framework (MultipeerConnectivity is deprecated in Xcode 27). Rules from
/// ChirpCore's `Link`: the PeerID is in the service name, the lower PeerID
/// dials, every link opens with a hello, frames are length-prefixed and capped.
///
/// - Nothing starts at launch: `start()` is called on the first tap that needs
///   other phones, which is what brings up the Local Network prompt
///   (5.1.1(iv)). `stop()` on going to the background (foreground only, 2.5.4).
/// - Every packet in or out passes `SendGate` (Demo Mode never reaches the air,
///   2.1(a)). Blocking, dedup and relaying are the router's, above this.
/// - Callbacks run on the main queue; voice is 50 small packets a second.
@MainActor
@Observable
final class Transport {
    /// Phones with a working link right now.
    private(set) var linked: Set<PeerID> = []
    private(set) var running = false
    /// Demo Mode: nothing leaves or enters.
    var sandboxed = false

    /// Every packet that arrives, with the phone it came from.
    @ObservationIgnored var onPacket: ((Packet, PeerID) -> Void)?

    @ObservationIgnored private let local: PeerID
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var links: [ObjectIdentifier: LinkConnection] = [:]
    @ObservationIgnored private var table = LinkTable<ObjectIdentifier>()
    /// Peers we are dialing, so a browse update does not dial them twice.
    @ObservationIgnored private var dialing: Set<PeerID> = []

    init(local: PeerID) {
        self.local = local
    }

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true
        return p
    }

    // MARK: Start and stop

    func start() {
        wanted = true
        guard !running, !sandboxed else { return }
        running = true
        do {
            let l = try NWListener(using: Self.parameters())
            l.service = NWListener.Service(name: Link.serviceName(for: local), type: Link.serviceType)
            l.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection, dialed: nil) }
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed = state { MainActor.assumeIsolated { self?.restart() } }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            running = false
            return
        }
        let b = NWBrowser(for: .bonjour(type: Link.serviceType, domain: nil), using: Self.parameters())
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { r -> (PeerID, NWEndpoint)? in
                guard case .service(let name, _, _, _) = r.endpoint,
                      let peer = Link.peer(fromServiceName: name) else { return nil }
                return (peer, r.endpoint)
            }
            MainActor.assumeIsolated { self?.found(found) }
        }
        b.start(queue: .main)
        browser = b
    }

    /// Set by the first `start()`: the user has asked for other phones, so
    /// the radio comes back each time the app does.
    @ObservationIgnored private var wanted = false

    /// Off in the background (foreground only, 2.5.4); back on return, once wanted.
    func follow(_ phase: ScenePhase) {
        switch phase {
        case .background: stop()
        case .active: if wanted { start() }
        default: break
        }
    }

    func stop() {
        guard running else { return }
        running = false
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        for link in links.values { link.cancel() }
        links.removeAll()
        table = LinkTable()
        dialing.removeAll()
        linked = []
    }

    private func restart() {
        stop()
        start()
    }

    // MARK: Sending

    /// To every linked phone (the router has already decided to send or relay).
    func send(_ packet: Packet) {
        guard running, SendGate.allowsSend(packet, sandboxed: sandboxed) else { return }
        let frame = Link.frame(packet.encode())
        for id in table.byPeer.values { links[id]?.send(frame) }
    }

    /// To one phone, when it is linked directly.
    func send(_ packet: Packet, to peer: PeerID) {
        guard running, SendGate.allowsSend(packet, sandboxed: sandboxed),
              let id = table.byPeer[peer] else { return }
        links[id]?.send(Link.frame(packet.encode()))
    }

    // MARK: Links

    private func found(_ results: [(PeerID, NWEndpoint)]) {
        for (peer, endpoint) in results
        where Link.shouldDial(local: local, remote: peer) && table.byPeer[peer] == nil && !dialing.contains(peer) {
            dialing.insert(peer)
            accept(NWConnection(to: endpoint, using: Self.parameters()), dialed: peer)
        }
    }

    private func accept(_ connection: NWConnection, dialed: PeerID?) {
        let link = LinkConnection(connection, dialed: dialed)
        let id = ObjectIdentifier(link)
        links[id] = link
        link.onHello = { [weak self] peer in self?.linked(id, peer: peer) }
        link.onFrame = { [weak self] frame in self?.received(frame, on: id) }
        link.onClose = { [weak self] in self?.closed(id) }
        link.start(hello: Link.hello(local))
    }

    private func linked(_ id: ObjectIdentifier, peer: PeerID) {
        guard let link = links[id] else { return }
        if peer == local { link.cancel(); return }
        if let d = link.dialed { dialing.remove(d) }
        if let replaced = table.add(peer, id) { links.removeValue(forKey: replaced)?.cancel() }
        linked = table.peers
    }

    private func received(_ frame: Data, on id: ObjectIdentifier) {
        guard let peer = links[id]?.peer, let packet = Packet.decode(frame),
              SendGate.allowsReceive(packet, sandboxed: sandboxed) else { return }
        onPacket?(packet, peer)
    }

    private func closed(_ id: ObjectIdentifier) {
        guard let link = links.removeValue(forKey: id) else { return }
        if let d = link.dialed { dialing.remove(d) }
        table.remove(id)
        linked = table.peers
    }
}

/// One TCP link to one phone: the hello, then frames.
@MainActor
private final class LinkConnection {
    let dialed: PeerID?
    private(set) var peer: PeerID?
    var onHello: ((PeerID) -> Void)?
    var onFrame: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let connection: NWConnection
    private var deframer = Deframer()
    private var closed = false

    init(_ connection: NWConnection, dialed: PeerID?) {
        self.connection = connection
        self.dialed = dialed
    }

    func start(hello: Data) {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed, .cancelled: self?.close()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        send(Link.frame(hello))
        receive()
    }

    func send(_ frame: Data) {
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
        close()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let data, !data.isEmpty { self.take(data) }
                if isComplete || error != nil { self.cancel() } else if !self.closed { self.receive() }
            }
        }
    }

    private func take(_ data: Data) {
        for frame in deframer.push(data) {
            if peer != nil {
                onFrame?(frame)
            } else {
                // The first frame must be a hello, and a dialer must find the
                // phone it dialed.
                guard let hello = Link.decodeHello(frame), dialed == nil || dialed == hello else {
                    cancel()
                    return
                }
                peer = hello
                onHello?(hello)
            }
        }
        if deframer.broken { cancel() }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        onClose?()
    }
}

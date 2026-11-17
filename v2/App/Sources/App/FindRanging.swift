import ChirpCore
import Foundation
import NearbyInteraction
import Observation
import UIKit

/// Find's precision finding (scope 4), the app's side of ChirpCore's
/// `FindSession`.
///
/// - Nothing runs until `open()`, which Find calls when the user opens it on
///   a friend. Running the NISession is what brings up the Nearby Interaction
///   prompt, so the prompt follows that tap (5.1.1(iv)).
/// - Tokens travel as `Find.Message` on the whisper channel (sealed pairwise,
///   friends only): `send` is the transport's, injected so this compiles and
///   runs in Demo Mode with no radio.
/// - Phones without UWB, a refused permission or a lost session all fall back
///   to `Find.fallback`, which claims only what the line knows.
@MainActor
@Observable
final class FindRanging: NSObject {
    /// The latest fix; nil without one.
    private(set) var fix: Find.Fix?
    /// Set when the user refused Nearby Interaction for ChirpChirps.
    private(set) var permissionDenied = false
    /// They opened Find on you first; show it (open Find on them to help).
    private(set) var requested = false

    @ObservationIgnored private var exchange = FindSession()
    @ObservationIgnored private var session: NISession?
    /// Where tokens go: the mesh sets it to the whisper channel when Find
    /// opens on a friend (`Mesh.attach`). Nowhere until then, as in Demo Mode.
    @ObservationIgnored var send: @MainActor (Find.Message) -> Void
    @ObservationIgnored private var haptics: Task<Void, Never>?

    static var supported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }

    init(send: @escaping @MainActor (Find.Message) -> Void = { _ in }) {
        self.send = send
    }

    var ranging: Bool {
        if case .ranging = exchange.phase { return true }
        return false
    }

    /// The user opened Find on this friend.
    func open() {
        guard exchange.phase == .closed else { return }
        var token: Data?
        if Self.supported {
            let s = NISession()
            s.delegate = self
            s.delegateQueue = .main
            session = s
            token = s.discoveryToken.flatMap(Self.archive)
        }
        requested = false
        apply(exchange.handle(.opened(myToken: token)))
    }

    /// Find closed, or the app went to the background.
    func close() {
        apply(exchange.handle(.closed))
        fix = nil
    }

    /// A `.find` message from this friend, already opened and verified.
    func received(_ data: Data) {
        guard let message = Find.Message.decode(data) else { return }
        received(message)
    }

    func received(_ message: Find.Message) {
        apply(exchange.handle(.received(message)))
    }

    private func apply(_ effects: [FindSession.Effect]) {
        for effect in effects {
            switch effect {
            case .send(let m):
                send(m)
            case .run(let data):
                guard let session, let token = Self.unarchive(data) else {
                    apply(exchange.handle(.rangingFailed))
                    continue
                }
                session.run(NINearbyPeerConfiguration(peerToken: token))
            case .invalidate:
                session?.invalidate()
                session = nil
                fix = nil
                stopHaptics()
            case .showRequest:
                requested = true
            }
        }
    }

    private func isCurrent(_ id: ObjectIdentifier) -> Bool {
        session.map(ObjectIdentifier.init) == id
    }

    private func update(distance: Float?, angle: Float?) {
        fix = Find.fix(distance: distance, horizontalAngle: angle)
        if fix == nil { stopHaptics() } else if haptics == nil { startHaptics() }
    }

    /// Taps faster as the friend gets closer, while there is a fix.
    private func startHaptics() {
        haptics = Task { @MainActor [weak self] in
            let generator = UIImpactFeedbackGenerator(style: .light)
            while !Task.isCancelled, let meters = self?.fix?.meters {
                generator.impactOccurred()
                try? await Task.sleep(for: .seconds(Find.tapInterval(meters: meters)))
            }
        }
    }

    private func stopHaptics() {
        haptics?.cancel()
        haptics = nil
    }

    private func failed(denied: Bool) {
        if denied { permissionDenied = true }
        session = nil
        stopHaptics()
        apply(exchange.handle(.rangingFailed))
    }

    private static func archive(_ token: NIDiscoveryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func unarchive(_ data: Data) -> NIDiscoveryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}

extension FindRanging: NISessionDelegate {
    // The delegate queue is main (set in `open`), so these run on the main
    // actor in place. Only events from the current session count: a session
    // invalidated by a close or a reopen may still report once.
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let id = ObjectIdentifier(session)
        let distance = nearbyObjects.first?.distance
        let angle = nearbyObjects.first?.horizontalAngle
        MainActor.assumeIsolated { if isCurrent(id) { update(distance: distance, angle: angle) } }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        let id = ObjectIdentifier(session)
        MainActor.assumeIsolated { if isCurrent(id) { update(distance: nil, angle: nil) } }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        let id = ObjectIdentifier(session)
        MainActor.assumeIsolated { if isCurrent(id) { update(distance: nil, angle: nil) } }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        let id = ObjectIdentifier(session)
        let denied = (error as? NIError)?.code == .userDidNotAllow
        MainActor.assumeIsolated { if isCurrent(id) { failed(denied: denied) } }
    }
}

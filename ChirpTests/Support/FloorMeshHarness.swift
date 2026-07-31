import Foundation
import os
@testable import Chirp

/// One control message captured in flight between two simulated devices.
struct InFlightMessage: Sendable, Equatable {
    let from: String
    let message: FloorControlMessage
}

extension FloorControlMessage {
    /// Lets a test say "peer-B's own request is still queued" without caring
    /// what else that peer has emitted since.
    var isFloorRequest: Bool {
        if case .floorRequest = self { return true }
        return false
    }

    /// The speaker a `.floorGranted` names, or `nil` for any other message.
    var grantedSpeakerID: String? {
        if case .floorGranted(let speakerID) = self { return speakerID }
        return nil
    }
}

/// A deterministic, in-process stand-in for the mesh, for exercising floor
/// control across more than one device without radios.
///
/// The point of this harness is *ordering*. Floor-control defects are collision
/// defects: they only appear when two devices act before either has heard the
/// other, and on real hardware that window is milliseconds wide and cannot be
/// aimed at. Here, nothing is delivered until a test asks for it, so "both
/// devices pressed talk before either message landed" is just:
///
/// ```swift
/// harness["A"].requestFloor()
/// harness["B"].requestFloor()   // still in flight, B has not heard A
/// harness.deliverAll()          // now they hear each other
/// ```
///
/// Deliberately not a framework:
/// * No transports, no audio, no serialisation — this wires `FloorController`
///   instances to each other and nothing else. It tests the floor protocol,
///   not the radio.
/// * No timing. Delivery is manual. There are no sleeps in here and tests
///   built on it should not need any.
///
/// What it therefore cannot tell you: whether messages actually survive
/// MultipeerConnectivity, whether they arrive in this order on a real link, or
/// anything about audio. Those need two physical devices.
@MainActor
final class FloorMeshHarness {

    /// Messages a `FloorController` has emitted but that the harness has not
    /// yet handed to anyone.
    ///
    /// `FloorController.sendToAllPeers` is declared `@Sendable`, so the send
    /// closure may not capture this main-actor harness. The queue lives behind
    /// a lock instead — the same primitive the app uses in
    /// `TransportPreference` — and the closures capture the queue.
    private final class SendQueue: Sendable {
        private let storage = OSAllocatedUnfairLock(initialState: [InFlightMessage]())

        func post(_ item: InFlightMessage) {
            storage.withLock { $0.append(item) }
        }

        /// Removes and returns everything currently queued.
        func take() -> [InFlightMessage] {
            storage.withLock { queued in
                let all = queued
                queued.removeAll()
                return all
            }
        }

        var contents: [InFlightMessage] {
            storage.withLock { $0 }
        }
    }

    /// A simulated device.
    struct Node {
        let id: String
        let name: String
        let controller: FloorController
    }

    private(set) var nodes: [Node] = []
    private let queue = SendQueue()

    /// Every message the harness has delivered, oldest first. Lets a test assert
    /// on the whole conversation rather than on one controller's view of it.
    private(set) var delivered: [InFlightMessage] = []

    /// Creates one `FloorController` per entry and wires each one's broadcast
    /// callback into the shared queue.
    init(peers: [(id: String, name: String)]) {
        for peer in peers {
            let controller = FloorController(localPeerID: peer.id, localPeerName: peer.name)
            let senderID = peer.id
            let queue = self.queue
            controller.sendToAllPeers = { message in
                queue.post(InFlightMessage(from: senderID, message: message))
            }
            nodes.append(Node(id: peer.id, name: peer.name, controller: controller))
        }
    }

    subscript(id: String) -> FloorController {
        guard let node = nodes.first(where: { $0.id == id }) else {
            fatalError("FloorMeshHarness has no node '\(id)'. Nodes: \(nodes.map(\.id))")
        }
        return node.controller
    }

    /// Messages that have been sent but not yet delivered.
    var inFlight: [InFlightMessage] { queue.contents }

    /// Delivers every queued message to every node except its sender, then
    /// repeats for anything those deliveries produced, until the mesh goes
    /// quiet.
    ///
    /// - Parameter maxRounds: Safety stop. If the protocol is exchanging
    ///   messages forever — each device answering the other's answer — this
    ///   traps instead of hanging the test. A floor-control protocol that does
    ///   not settle is itself a defect, so this limit is an assertion, not a
    ///   convenience. It throws rather than trapping so the test reports a
    ///   failure instead of taking the whole test process down.
    func deliverAll(maxRounds: Int = 20) throws {
        for round in 0..<maxRounds {
            let batch = queue.take()
            if batch.isEmpty { return }
            deliver(batch)
            if round == maxRounds - 1, !queue.contents.isEmpty {
                throw HarnessError.protocolDidNotSettle(
                    rounds: maxRounds,
                    stillInFlight: queue.contents
                )
            }
        }
    }

    enum HarnessError: Error, CustomStringConvertible {
        case protocolDidNotSettle(rounds: Int, stillInFlight: [InFlightMessage])

        var description: String {
            switch self {
            case .protocolDidNotSettle(let rounds, let stillInFlight):
                return """
                    Floor control did not settle within \(rounds) delivery rounds — \
                    the devices are answering each other's answers. Still in flight: \
                    \(stillInFlight.map { "\($0.from) -> \($0.message)" })
                    """
            }
        }
    }

    /// Delivers only what the named node has sent so far, leaving everyone
    /// else's messages queued.
    ///
    /// This is how a test aims at a specific interleaving: deliver A's request
    /// to B while B's own request is still in flight, and B is now in the state
    /// a real device reaches when the radio was a few milliseconds slower than
    /// the user's thumb.
    func deliverMessages(from senderID: String) {
        let batch = queue.take()
        let (toSend, toRequeue) = batch.reduce(into: ([InFlightMessage](), [InFlightMessage]())) {
            $1.from == senderID ? $0.0.append($1) : $0.1.append($1)
        }
        for item in toRequeue { queue.post(item) }
        deliver(toSend)
    }

    /// Discards everything the named node has sent without delivering it —
    /// the peer spoke and nobody heard.
    ///
    /// Models the real case behind the "both devices transmit at once" report:
    /// a device that missed a floor request has no idea the floor is taken.
    @discardableResult
    func dropMessages(from senderID: String) -> [InFlightMessage] {
        let batch = queue.take()
        let dropped = batch.filter { $0.from == senderID }
        for item in batch where item.from != senderID { queue.post(item) }
        return dropped
    }

    /// Discards everything in flight.
    @discardableResult
    func dropAll() -> [InFlightMessage] {
        queue.take()
    }

    // MARK: - Assertion helpers

    /// The nodes currently transmitting. More than one means every device in
    /// that list has a live microphone and believes it holds the floor.
    var transmittingNodeIDs: [String] {
        nodes.filter { $0.controller.state == .transmitting }.map(\.id)
    }

    /// What each node believes the current state to be, keyed by node ID.
    var states: [String: PTTState] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.controller.state) })
    }

    /// What each node believes the current speaker to be, keyed by node ID.
    /// Absent means that node thinks nobody is speaking.
    var speakerIDs: [String: String] {
        var result: [String: String] = [:]
        for node in nodes {
            if let speaker = node.controller.currentSpeaker {
                result[node.id] = speaker.id
            }
        }
        return result
    }

    // MARK: - Private

    private func deliver(_ batch: [InFlightMessage]) {
        for item in batch {
            delivered.append(item)
            for node in nodes where node.id != item.from {
                node.controller.handleMessage(item.message)
            }
        }
    }
}

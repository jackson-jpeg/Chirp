import Foundation
import os
@testable import Chirp

/// Records the control messages a `FloorSession` broadcasts.
///
/// `FloorSession.sendToAllPeers` is declared `@Sendable`, so the production
/// contract is "may be invoked from any isolation domain". A test that recorded
/// into main-actor state would only be correct under an assumption the type does
/// not make. The array lives behind an `OSAllocatedUnfairLock`, and the
/// closure captures this object rather than the test case.
final class ControlMessageLog: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [FloorControlMessage]())

    var messages: [FloorControlMessage] { storage.withLock { $0 } }

    func record(_ message: FloorControlMessage) {
        storage.withLock { $0.append(message) }
    }

    func reset() {
        storage.withLock { $0.removeAll() }
    }

    var releases: [FloorControlMessage] {
        messages.filter {
            if case .floorRelease = $0 { return true }
            return false
        }
    }

    var floorRequests: [FloorControlMessage] {
        messages.filter(\.isFloorRequest)
    }
}


@MainActor
extension FloorSession {
    /// Delivers a message as if the transport observed its claimed sender —
    /// the honest case, and what every pre-existing floor test means.
    /// Impersonation tests pass `from:` explicitly to make the two disagree.
    func handleMessage(_ message: FloorControlMessage) {
        let sender: String
        switch message {
        case .floorRequest(let id, _, _): sender = id
        case .floorRelease(let id): sender = id
        case .peerLeave(let id): sender = id
        case .peerJoin(let id, _): sender = id
        case .heartbeat(let id, _): sender = id
        case .floorGranted(let speakerID): sender = speakerID
        }
        handleMessage(message, from: sender)
    }
}

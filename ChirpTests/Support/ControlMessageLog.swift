import Foundation
import os
@testable import Chirp

/// Records the control messages a `FloorController` broadcasts.
///
/// `FloorController.sendToAllPeers` is declared `@Sendable`, so the production
/// contract is "may be invoked from any isolation domain". A test that recorded
/// into main-actor state would only be correct under an assumption the type does
/// not make. The array lives behind the same lock primitive the app uses in
/// `TransportPreference`, and the closure captures this object rather than the
/// test case.
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

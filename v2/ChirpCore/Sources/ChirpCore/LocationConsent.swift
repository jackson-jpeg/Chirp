import Foundation

// Location sharing for 2.0: off by default, asked every time (App Review
// 5.1.2(i), "declinable location consent, check-in each time").
//
// Carried over from 1.0's design, which the audit found sound (section 6): a
// check-in is one tap, one consent, 15 minutes, held in memory only, never
// resumed. Rewritten as one reducer so "nothing leaves without a fresh yes" is
// a property of a single function with a test per arm. iOS authorization is an
// input, not something this asks for: the app's own consent sheet comes first,
// and the system prompt follows only after a yes on it, on a tap (5.1.1(iv):
// no prompt before the user acts).

public enum OSLocationAuthorization: Sendable, Equatable {
    case notDetermined, denied, granted
}

public enum CheckInState: Equatable, Sendable {
    /// Not sharing. Where every launch starts.
    case off
    /// The user tapped Check In; our consent sheet is showing.
    case askingConsent
    /// The user said yes on our sheet; waiting for the iOS prompt's answer.
    case awaitingSystemPermission
    /// Sharing until `until`.
    case sharing(until: Date)
}

public enum CheckInEvent: Equatable, Sendable {
    case tappedCheckIn(authorization: OSLocationAuthorization)
    case consentAnswered(yes: Bool, authorization: OSLocationAuthorization, at: Date)
    case systemPermissionAnswered(granted: Bool, at: Date)
    case tappedStop
    case tick(Date)
    case enteredBackground
    /// Location access changed in Settings (or Control Center) while not
    /// waiting on our own request. Turned off ends a check-in at once.
    case authorizationChanged(OSLocationAuthorization)
}

public enum CheckInEffect: Equatable, Sendable {
    case showConsentSheet
    case requestSystemPermission
    case startLocationUpdates
    case stopLocationUpdates
    /// Permission is denied in Settings; tell the user how to change it.
    case explainDenied
}

public enum CheckIn {
    public static let duration: TimeInterval = 15 * 60

    public static func reduce(_ state: CheckInState, _ event: CheckInEvent) -> (CheckInState, [CheckInEffect]) {
        switch (state, event) {
        case (.off, .tappedCheckIn(let auth)):
            // The consent sheet shows every time, whatever was answered before.
            if auth == .denied { return (.off, [.explainDenied]) }
            return (.askingConsent, [.showConsentSheet])

        case (.askingConsent, .consentAnswered(let yes, let auth, let at)):
            guard yes else { return (.off, []) }
            switch auth {
            case .granted: return (.sharing(until: at.addingTimeInterval(duration)), [.startLocationUpdates])
            case .notDetermined: return (.awaitingSystemPermission, [.requestSystemPermission])
            case .denied: return (.off, [.explainDenied])
            }

        case (.awaitingSystemPermission, .systemPermissionAnswered(let granted, let at)):
            guard granted else { return (.off, []) }
            return (.sharing(until: at.addingTimeInterval(duration)), [.startLocationUpdates])

        case (.sharing, .tappedStop), (.sharing, .enteredBackground):
            return (.off, [.stopLocationUpdates])

        case (.sharing(let until), .tick(let now)):
            return now >= until ? (.off, [.stopLocationUpdates]) : (state, [])

        case (.sharing, .authorizationChanged(.denied)):
            return (.off, [.stopLocationUpdates])

        case (.askingConsent, .enteredBackground), (.askingConsent, .tappedStop):
            return (.off, [])

        case (.awaitingSystemPermission, .authorizationChanged(.denied)):
            return (.off, [])

        case (.awaitingSystemPermission, .tappedStop):
            return (.off, [])

        default:
            return (state, [])
        }
    }

    /// Whether a position may go into a packet right now. The only gate.
    public static func maySend(_ state: CheckInState, at now: Date) -> Bool {
        if case .sharing(let until) = state { return now < until }
        return false
    }
}

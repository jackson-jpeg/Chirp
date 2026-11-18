import ChirpCore
import CoreLocation
import Foundation
import Observation
import SwiftUI

/// Check-in (2.0 scope: "location off by default and asked every time"; App
/// Review 5.1.1(iv) and 5.1.2(i)), the app's side of ChirpCore's `CheckIn`
/// reducer.
///
/// - Nothing happens until the user taps Share on Nearby. Our own sheet comes
///   first, every time; the iOS prompt follows only a yes on it.
/// - When In Use only. No background location, no "Always".
/// - A check-in lasts `CheckIn.duration` (15 minutes), and ends on Stop, on
///   leaving the app, or when location access is turned off. It never restarts
///   by itself: every launch starts at `.off`.
/// - Positions go out through `send` (the mesh, to the locked channels this
///   phone is on), and only while `CheckIn.maySend` says so; the mesh's
///   `Dispatch.checkInPosition` checks it again.
@MainActor
@Observable
final class CheckInLocation: NSObject {
    private(set) var state: CheckInState = .off
    /// Our consent sheet is up (bound to Nearby's alert).
    var askingConsent = false
    /// Location is off for ChirpChirps in Settings; say how to change it.
    var showDenied = false
    /// Where this phone is, only while sharing.
    private(set) var here: CLLocation?

    /// Out to the flock: latitude, longitude, accuracy in metres, and the state
    /// that allows it. Set by `ChirpApp` to the mesh.
    @ObservationIgnored var send: @MainActor (Double, Double, Double, CheckInState) -> Void = { _, _, _, _ in }
    /// "Forget where I was", to the flock.
    @ObservationIgnored var sendStopped: @MainActor () -> Void = {}

    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastSent: (at: Date, place: CLLocation)?

    /// A fresh position goes out at most this often, unless the phone moved
    /// more than `sendDistance` metres.
    static let sendInterval: TimeInterval = 30
    static let sendDistance: CLLocationDistance = 25

    var sharing: Bool { CheckIn.maySend(state, at: .now) }

    /// Whole minutes left in this check-in (at least 1 while sharing).
    func minutesLeft(at now: Date) -> Int? {
        guard case .sharing(let until) = state, until > now else { return nil }
        return max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
    }

    // MARK: What the user does

    /// Share on Nearby.
    func tapShare() { handle(.tappedCheckIn(authorization: authorization)) }

    /// Our sheet's answer.
    func answer(yes: Bool) { handle(.consentAnswered(yes: yes, authorization: authorization, at: .now)) }

    /// Stop on Nearby.
    func stop() { handle(.tappedStop) }

    func follow(_ phase: ScenePhase) {
        if phase == .background { handle(.enteredBackground) }
    }

    // MARK: The reducer

    private var authorization: OSLocationAuthorization {
        Self.map((manager ?? CLLocationManager()).authorizationStatus)
    }

    nonisolated private static func map(_ status: CLAuthorizationStatus) -> OSLocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        default: return .denied   // denied, restricted
        }
    }

    private func handle(_ event: CheckInEvent) {
        let (next, effects) = CheckIn.reduce(state, event)
        state = next
        if next != .askingConsent { askingConsent = false }
        for effect in effects { run(effect) }
    }

    private func run(_ effect: CheckInEffect) {
        switch effect {
        case .showConsentSheet:
            askingConsent = true
        case .requestSystemPermission:
            locationManager().requestWhenInUseAuthorization()
        case .startLocationUpdates:
            let m = locationManager()
            m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            m.distanceFilter = 10
            lastSent = nil
            m.startUpdatingLocation()
            startTicker()
        case .stopLocationUpdates:
            manager?.stopUpdatingLocation()
            ticker?.cancel()
            ticker = nil
            here = nil
            lastSent = nil
            sendStopped()
        case .explainDenied:
            showDenied = true
        }
    }

    /// Made on the first tap, never at launch. Creating one asks nothing.
    private func locationManager() -> CLLocationManager {
        if let manager { return manager }
        let m = CLLocationManager()
        m.delegate = self
        m.pausesLocationUpdatesAutomatically = true
        manager = m
        return m
    }

    /// The 15 minutes run out even if no position arrives.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.handle(.tick(.now))
                if !self.sharing { return }
            }
        }
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        let auth = Self.map(status)
        if state == .awaitingSystemPermission {
            guard auth != .notDetermined else { return }
            handle(.systemPermissionAnswered(granted: auth == .granted, at: .now))
        } else {
            handle(.authorizationChanged(auth))
        }
    }

    private func located(_ location: CLLocation) {
        let now = Date.now
        guard CheckIn.maySend(state, at: now), location.horizontalAccuracy >= 0 else { return }
        here = location
        if let last = lastSent, now.timeIntervalSince(last.at) < Self.sendInterval,
           location.distance(from: last.place) < Self.sendDistance { return }
        lastSent = (now, location)
        send(location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy, state)
    }
}

extension CheckInLocation: CLLocationManagerDelegate {
    // The manager is made on the main thread, so Core Location calls back
    // there: these run on the main actor in place.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated { located(latest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix (no sky, airplane mode) leaves the check-in running
        // until it ends; nothing is sent without a position.
    }
}

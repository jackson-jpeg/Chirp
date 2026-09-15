import CoreLocation
import Foundation
import Observation
import OSLog
import UIKit

// MARK: - Check-in

/// One bounded, deliberate grant to put this device's position on the mesh.
///
/// A check-in exists only in memory and only for ``duration``. It is created
/// by an explicit user tap and by nothing else: there is no timer that starts
/// one, no setting that re-arms one, and nothing that writes one to disk. A
/// relaunch therefore always begins checked out.
struct LocationCheckIn: Equatable, Sendable {

    /// How long a single check-in lasts before it stops on its own.
    static let duration: TimeInterval = 15 * 60

    let startedAt: Date

    var expiresAt: Date { startedAt.addingTimeInterval(Self.duration) }

    func isActive(at now: Date) -> Bool { now < expiresAt }

    func remaining(at now: Date) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }
}

// MARK: - The gate

/// The single decision point for whether a coordinate may leave this device.
///
/// Every code path that can put a position into a packet asks this and
/// nothing else — the mesh beacon (map pins) and the chat location
/// attachment. Keeping it a pure function of its four inputs is what makes
/// "no check-in, no emission" a property that can be tested exhaustively
/// rather than a convention that has to be re-audited.
enum LocationBroadcastGate {

    struct Coordinate: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    /// The coordinate this device is allowed to broadcast right now, or `nil`.
    ///
    /// All four conditions are required, in this order:
    /// 1. the user granted iOS location permission,
    /// 2. a check-in exists — the user tapped Check In,
    /// 3. that check-in has not expired,
    /// 4. a fix has actually arrived.
    static func coordinateForBroadcast(
        authorization: CLAuthorizationStatus,
        checkIn: LocationCheckIn?,
        location: CLLocation?,
        at now: Date
    ) -> Coordinate? {
        switch authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .notDetermined, .denied, .restricted:
            return nil
        @unknown default:
            // An authorization state this build does not recognise is treated
            // as "not granted". The safe default for a location gate is off.
            return nil
        }

        guard let checkIn, checkIn.isActive(at: now) else { return nil }
        guard let location else { return nil }

        return Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}

// MARK: - Controller

/// Owns the check-in state and is the only thing that starts or stops the
/// location manager.
///
/// Deliberately absent, and deliberately not to be added back:
/// - no `UserDefaults` key, so nothing survives a relaunch,
/// - no "always share" / "share automatically" toggle,
/// - no timer that begins a check-in; the one timer here only ends one,
/// - no background emission — leaving the foreground stops sharing.
@Observable
@MainActor
final class LocationSharing {

    /// Why sharing stopped, so the UI can say so instead of going quiet.
    enum StopReason: Equatable {
        /// The user tapped Stop.
        case user
        /// The 15-minute window ran out.
        case expired
        /// The app left the foreground.
        case background
        /// Permission was revoked while sharing.
        case permissionLost
    }

    // MARK: State

    /// The live check-in, if any. `nil` means this device is not on anyone's map.
    private(set) var checkIn: LocationCheckIn?

    /// Set when sharing ends, cleared when a new check-in begins.
    private(set) var lastStopReason: StopReason?

    /// Ticks once a second while sharing so the countdown re-renders.
    /// Not a broadcast timer — it can only end a check-in, never start one.
    private(set) var tick: Date = .now

    // MARK: Dependencies

    private let locationService: LocationService
    private var expiryTask: Task<Void, Never>?
    private var lifecycleObservers: [Any] = []
    private let logger = Logger(subsystem: Constants.subsystem, category: "LocationSharing")

    // MARK: Derived

    var authorizationStatus: CLAuthorizationStatus { locationService.authorizationStatus }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// The user was asked and said no — or an MDM profile says no. The app
    /// stays fully usable in this state; only the map pin is withheld.
    var isDeclined: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var hasBeenAsked: Bool { authorizationStatus != .notDetermined }

    /// True from the moment the user taps Check In — before the first fix
    /// lands — so the indicator and the Stop button appear immediately.
    var isSharing: Bool { checkIn?.isActive(at: .now) ?? false }

    /// Seconds left in the current check-in, for the countdown label.
    var remaining: TimeInterval { checkIn?.remaining(at: tick) ?? 0 }

    /// "14:32" — the countdown shown next to the sharing indicator.
    var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Init

    init(locationService: LocationService) {
        self.locationService = locationService

        // Losing permission mid-session ends the check-in immediately rather
        // than leaving a check-in alive that can never produce a coordinate.
        locationService.onAuthorizationChanged = { [weak self] status in
            guard let self else { return }
            switch status {
            case .denied, .restricted:
                self.stopSharing(reason: .permissionLost)
            default:
                break
            }
        }

        observeLifecycle()
    }

    // MARK: Permission

    /// Ask iOS for location permission. Only ever called from the check-in
    /// sheet, after the user has read what sharing means and tapped Continue.
    func requestPermission() {
        locationService.requestPermission()
    }

    // MARK: Check in / out

    /// Begin a check-in. Returns `false` if permission is not granted, in
    /// which case nothing changes and the caller shows the explanation first.
    @discardableResult
    func beginCheckIn() -> Bool {
        guard isAuthorized else {
            logger.info("Check-in refused: location not authorized")
            return false
        }

        checkIn = LocationCheckIn(startedAt: .now)
        tick = .now
        lastStopReason = nil
        locationService.startUpdating()
        startExpiryCountdown()
        logger.info("Checked in — sharing for \(Int(LocationCheckIn.duration / 60)) minutes")
        return true
    }

    /// End sharing now. Idempotent.
    func stopSharing(reason: StopReason = .user) {
        guard checkIn != nil else { return }
        checkIn = nil
        lastStopReason = reason
        expiryTask?.cancel()
        expiryTask = nil
        locationService.stopUpdating()
        logger.info("Stopped sharing (\(String(describing: reason), privacy: .public))")
    }

    // MARK: The gate

    /// The coordinate this device may broadcast right now, or `nil`.
    /// Both emission paths call this; neither reads the location manager.
    func coordinateForBroadcast() -> LocationBroadcastGate.Coordinate? {
        LocationBroadcastGate.coordinateForBroadcast(
            authorization: locationService.authorizationStatus,
            checkIn: checkIn,
            location: locationService.currentLocation,
            at: .now
        )
    }

    // MARK: Private

    /// One second tick that ends the check-in when the window runs out.
    private func startExpiryCountdown() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick = .now
                if let checkIn = self.checkIn, !checkIn.isActive(at: .now) {
                    self.stopSharing(reason: .expired)
                    return
                }
            }
        }
    }

    /// Leaving the foreground stops sharing. With when-in-use authorization
    /// iOS stops delivering fixes shortly after backgrounding anyway, so the
    /// alternative is beaconing a position that silently goes stale — and the
    /// app stays alive in the background for push-to-talk audio, so the
    /// beacon really would keep going. Coming back requires a fresh tap.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        for name in [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification
        ] {
            lifecycleObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.stopSharing(reason: .background)
                    }
                }
            )
        }
    }
}

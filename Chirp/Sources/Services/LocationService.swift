import CoreLocation
import OSLog

@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: Constants.subsystem, category: "Location")

    private(set) var currentLocation: CLLocation?
    private(set) var currentHeading: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fires when the user denies or restricts location access — but only in
    /// response to a request *this* session made. A device that was denied
    /// long ago must not be greeted with a permission alert on launch.
    var onPermissionDenied: (() -> Void)?

    /// Fires on every authorization change, including the first one the
    /// delegate reports. ``LocationSharing`` uses it to end a live check-in
    /// the moment permission goes away.
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?

    /// True once ``requestPermission()`` has been called in this session.
    private(set) var hasRequestedPermission = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Reading the current status never prompts; it just means the first
        // render is honest about where we stand.
        authorizationStatus = manager.authorizationStatus
    }

    /// Ask iOS for permission. Called only from the in-app check-in sheet,
    /// after the user has read what location sharing does and tapped
    /// Continue — never on launch, and never as a side effect of opening a
    /// screen.
    func requestPermission() {
        hasRequestedPermission = true
        manager.requestWhenInUseAuthorization()
    }

    /// Start receiving fixes. Called only by ``LocationSharing/beginCheckIn()``.
    func startUpdating() {
        manager.startUpdatingLocation()
        startHeadingUpdates()
    }

    /// Stop receiving fixes and drop the last one, so a coordinate cannot
    /// outlive the check-in that justified holding it.
    func stopUpdating() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        currentLocation = nil
        currentHeading = nil
    }

    func startHeadingUpdates() { manager.startUpdatingHeading() }

    // MARK: - Encoding / Decoding

    /// Encode location as compact string: "LOC:lat,lon,accuracy"
    static func encodeLocation(_ location: CLLocation) -> String {
        encodeLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
    }

    /// Same wire format, from a coordinate that has already cleared
    /// ``LocationBroadcastGate``. Callers that hold a gated coordinate use
    /// this rather than reaching back for the raw `CLLocation`.
    static func encodeLocation(latitude: Double, longitude: Double, accuracy: Double) -> String {
        String(format: "LOC:%.6f,%.6f,%.1f", latitude, longitude, accuracy)
    }

    /// Decode a "LOC:lat,lon,accuracy" string into a coordinate.
    static func decodeLocation(_ text: String) -> CLLocationCoordinate2D? {
        guard text.hasPrefix("LOC:") else { return nil }
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Parse accuracy from encoded string, if present.
    static func decodeAccuracy(_ text: String) -> Double? {
        guard text.hasPrefix("LOC:") else { return nil }
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 3, let acc = Double(parts[2]) else { return nil }
        return acc
    }

    // MARK: - Geometry helpers

    /// Distance in meters between a CLLocation and a coordinate.
    static func distance(from: CLLocation, to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: target)
    }

    /// Bearing in degrees (0 = north, clockwise) from one coordinate to another.
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360) // normalize to 0-360
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = latest
            self.logger.debug("Location updated: \(latest.coordinate.latitude, privacy: .private), \(latest.coordinate.longitude, privacy: .private)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.currentHeading = heading
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.handleAuthorizationChange(status)
        }
    }

    @MainActor
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        logger.info("Authorization changed: \(String(describing: status.rawValue))")

        onAuthorizationChanged?(status)

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // Granting permission does NOT start location updates. Nothing
            // reaches the mesh until the user taps Check In; that tap is the
            // only caller of startUpdating().
            break
        case .denied, .restricted:
            logger.warning("Location access denied or restricted")
            stopUpdating()
            // Only surface the alert if the user just answered our prompt.
            // Otherwise this fires on every launch of a device that declined
            // once, which is the dead end the app must not have.
            if hasRequestedPermission {
                onPermissionDenied?()
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

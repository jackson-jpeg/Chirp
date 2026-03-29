import CoreLocation
import OSLog

@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: Constants.subsystem, category: "Location")

    private(set) var currentLocation: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func startUpdating() { manager.startUpdatingLocation() }
    func stopUpdating() { manager.stopUpdatingLocation() }

    // MARK: - Encoding / Decoding

    /// Encode location as compact string: "LOC:lat,lon,accuracy"
    static func encodeLocation(_ location: CLLocation) -> String {
        String(format: "LOC:%.6f,%.6f,%.1f",
               location.coordinate.latitude,
               location.coordinate.longitude,
               location.horizontalAccuracy)
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.logger.info("Authorization changed: \(String(describing: status.rawValue))")

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.logger.warning("Location access denied or restricted")
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

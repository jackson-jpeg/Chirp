import CoreLocation
import Foundation
import OSLog
import UIKit

/// Emergency SOS beacon that broadcasts location and distress signal
/// across the entire mesh network at maximum TTL.
///
/// Activation triggers a repeating broadcast every 5 seconds containing
/// GPS coordinates, battery level, and device identity. The beacon uses
/// TTL 8 (maximum mesh range) so every reachable node receives the alert.
@Observable
@MainActor
final class EmergencyBeacon: NSObject {
    static let shared = EmergencyBeacon()

    // MARK: - Public State

    private(set) var isActive = false
    private(set) var lastLocation: CLLocation?
    private(set) var broadcastCount: UInt64 = 0
    private(set) var receivedAlerts: [SOSMessage] = []

    /// External callback invoked when an SOS is received from the mesh.
    var onSOSReceived: ((SOSMessage) -> Void)?

    // MARK: - SOS Message

    struct SOSMessage: Codable, Sendable, Identifiable {
        let senderID: String
        let senderName: String
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let batteryLevel: Float
        let timestamp: Date
        let message: String

        var id: String { "\(senderID)-\(timestamp.timeIntervalSince1970)" }

        /// Human-readable coordinate string.
        var coordinateString: String {
            let latDir = latitude >= 0 ? "N" : "S"
            let lonDir = longitude >= 0 ? "E" : "W"
            return String(format: "%.5f%@ %.5f%@", abs(latitude), latDir, abs(longitude), lonDir)
        }
    }

    // MARK: - Private

    private var broadcastTask: Task<Void, Never>?
    private var locationManager: CLLocationManager?
    private var activeSenderID: String?
    private var activeSenderName: String?
    private let logger = Logger(subsystem: Constants.subsystem, category: "Emergency")

    /// Magic bytes prepended to SOS payloads for identification.
    static let sosMagic: [UInt8] = [0x53, 0x4F, 0x53, 0x21] // "SOS!"

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Activation

    /// Activate the emergency beacon. Broadcasts SOS every 5 seconds
    /// at maximum TTL until explicitly deactivated.
    func activate(senderID: String, senderName: String) {
        guard !isActive else {
            logger.warning("Emergency beacon already active")
            return
        }

        logger.critical("SOS BEACON ACTIVATED by \(senderName, privacy: .public) (\(senderID, privacy: .public))")

        activeSenderID = senderID
        activeSenderName = senderName
        isActive = true
        broadcastCount = 0

        // Enable battery monitoring so we can report level.
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Start location services.
        setupLocationManager()

        // Fire the first broadcast immediately, then every 5 seconds.
        broadcastSOS()
        broadcastTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { break }
                self.broadcastSOS()
            }
        }
    }

    /// Deactivate the emergency beacon and stop broadcasting.
    func deactivate() {
        guard isActive else { return }

        logger.info("SOS beacon deactivated after \(self.broadcastCount) broadcasts")

        isActive = false
        broadcastTask?.cancel()
        broadcastTask = nil
        locationManager?.stopUpdatingLocation()
        locationManager = nil
        activeSenderID = nil
        activeSenderName = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Receiving

    /// Process an incoming SOS payload received from the mesh network.
    /// Call this from the mesh router's local delivery handler.
    func handleReceivedSOSData(_ data: Data) {
        // Verify magic header.
        guard data.count > Self.sosMagic.count else { return }
        let magic = Array(data.prefix(Self.sosMagic.count))
        guard magic == Self.sosMagic else { return }

        let jsonData = data.dropFirst(Self.sosMagic.count)

        do {
            let message = try JSONDecoder().decode(SOSMessage.self, from: Data(jsonData))

            // Deduplicate: skip if we already have a recent alert from the same sender.
            if let existing = receivedAlerts.first(where: { $0.senderID == message.senderID }) {
                // Update if newer timestamp.
                if message.timestamp > existing.timestamp {
                    receivedAlerts.removeAll { $0.senderID == message.senderID }
                    receivedAlerts.insert(message, at: 0)
                }
            } else {
                receivedAlerts.insert(message, at: 0)
            }

            // Cap stored alerts.
            if receivedAlerts.count > 50 {
                receivedAlerts = Array(receivedAlerts.prefix(50))
            }

            logger.warning("SOS received from \(message.senderName, privacy: .public) at \(message.coordinateString, privacy: .public)")
            onSOSReceived?(message)
        } catch {
            logger.error("Failed to decode SOS message: \(error.localizedDescription)")
        }
    }

    /// Encode an SOS message into a payload suitable for mesh broadcast.
    /// The result includes the magic header followed by JSON.
    func encodeSOSPayload(_ message: SOSMessage) -> Data? {
        guard let json = try? JSONEncoder().encode(message) else { return nil }
        var payload = Data(Self.sosMagic)
        payload.append(json)
        return payload
    }

    /// Compute the distance in meters from the user's current location
    /// to a received SOS sender's location.
    func distanceToSOS(_ sos: SOSMessage) -> CLLocationDistance? {
        guard let current = lastLocation else { return nil }
        let sosLocation = CLLocation(latitude: sos.latitude, longitude: sos.longitude)
        return current.distance(from: sosLocation)
    }

    /// Compute the bearing (in degrees, 0 = north, clockwise) from the
    /// user's current location to a received SOS sender.
    func bearingToSOS(_ sos: SOSMessage) -> Double? {
        guard let current = lastLocation else { return nil }

        let lat1 = current.coordinate.latitude.radians
        let lon1 = current.coordinate.longitude.radians
        let lat2 = sos.latitude.radians
        let lon2 = sos.longitude.radians

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)

        return (bearing.degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Clear all received SOS alerts.
    func clearReceivedAlerts() {
        receivedAlerts.removeAll()
    }

    // MARK: - Private Helpers

    private func setupLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = false // Requires entitlement
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        locationManager = manager
    }

    private func broadcastSOS() {
        guard isActive,
              let senderID = activeSenderID,
              let senderName = activeSenderName else { return }

        let location = lastLocation
        let batteryLevel = UIDevice.current.batteryLevel

        let sosMessage = SOSMessage(
            senderID: senderID,
            senderName: senderName,
            latitude: location?.coordinate.latitude ?? 0,
            longitude: location?.coordinate.longitude ?? 0,
            altitude: location?.altitude ?? 0,
            batteryLevel: batteryLevel >= 0 ? batteryLevel : 0,
            timestamp: Date(),
            message: "SOS"
        )

        guard let payload = encodeSOSPayload(sosMessage) else {
            logger.error("Failed to encode SOS payload")
            return
        }

        // Create a mesh packet at maximum TTL for widest reach.
        // The packet uses control type with broadcast channel (empty string).
        let packet = MeshPacket(
            type: .control,
            ttl: MeshPacket.maxTTL,
            originID: UUID(uuidString: senderID) ?? UUID(),
            packetID: UUID(),
            sequenceNumber: UInt32(broadcastCount),
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            channelID: "",
            payload: payload
        )

        broadcastCount += 1

        let bat = Int(sosMessage.batteryLevel * 100)
        logger.info("SOS broadcast #\(self.broadcastCount) battery=\(bat)%")

        // Post the packet for the mesh router to forward.
        NotificationCenter.default.post(
            name: .emergencySOSBroadcast,
            object: nil,
            userInfo: ["packet": packet.serialize()]
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension EmergencyBeacon: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let logger = Logger(subsystem: Constants.subsystem, category: "Emergency")
        logger.error("Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let logger = Logger(subsystem: Constants.subsystem, category: "Emergency")
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.info("Location authorized, starting updates")
            manager.startUpdatingLocation()
        case .denied, .restricted:
            logger.warning("Location access denied or restricted")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when the emergency beacon has a new SOS packet ready for mesh broadcast.
    /// The `userInfo` dictionary contains key `"packet"` with the serialized `Data`.
    static let emergencySOSBroadcast = Notification.Name("com.chirpchirp.emergencySOSBroadcast")
}

// MARK: - Helpers

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

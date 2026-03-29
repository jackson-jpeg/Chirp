import Foundation
import OSLog

struct TrackingAlert: Identifiable, Sendable {
    let id: UUID
    let device: BLEDevice
    let alertType: AlertType
    let confidence: Double // 0-1
    let detectedAt: Date

    enum AlertType: String, Sendable {
        case followingDevice = "Possible Tracker"
        case hiddenCamera = "Hidden Camera"
        case stationaryTracker = "Stationary Tracker"
        case surveillanceInfrastructure = "Tracking Infrastructure"
    }
}

@Observable
@MainActor
final class PrivacyShield {

    private let logger = Logger(subsystem: Constants.subsystem, category: "PrivacyShield")

    // Public state
    private(set) var privacyScore: Int = 100
    private(set) var trackingAlerts: [TrackingAlert] = []
    private(set) var ownBroadcasts: [OwnBroadcast] = []

    // Dependencies
    private let bleScanner: BLEScanner

    // History for tracking detection
    private var scanSnapshots: [(date: Date, devices: [BLEDevice])] = []
    private var analysisTask: Task<Void, Never>?
    private static let maxSnapshots = 20

    init(bleScanner: BLEScanner) {
        self.bleScanner = bleScanner
        self.ownBroadcasts = OwnBroadcast.detectOwnBroadcasts()
        startAnalysisLoop()
    }

    // MARK: - Analysis

    /// Call periodically (or when scan data updates) to refresh analysis.
    func analyze() {
        // Take snapshot of current devices
        let currentDevices = bleScanner.discoveredDevices
        if !currentDevices.isEmpty {
            scanSnapshots.append((date: Date(), devices: currentDevices))
            if scanSnapshots.count > Self.maxSnapshots {
                scanSnapshots.removeFirst()
            }
        }

        // Detect tracking patterns
        detectTrackers()

        // Calculate privacy score
        calculateScore()

        // Refresh own broadcasts
        ownBroadcasts = OwnBroadcast.detectOwnBroadcasts()
    }

    private func startAnalysisLoop() {
        analysisTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { break }
                if self.bleScanner.isScanning {
                    self.analyze()
                }
            }
        }
    }

    private func detectTrackers() {
        var alerts: [TrackingAlert] = []

        // 1. Camera/surveillance devices from current scan
        for device in bleScanner.discoveredDevices where device.category == .camera {
            alerts.append(TrackingAlert(
                id: UUID(),
                device: device,
                alertType: .hiddenCamera,
                confidence: 0.8,
                detectedAt: Date()
            ))
        }

        // 2. Known tracker devices
        for device in bleScanner.discoveredDevices where device.category == .tracker {
            // Check if seen across multiple snapshots (following)
            let snapshotCount = scanSnapshots.filter { snapshot in
                snapshot.devices.contains { $0.peripheralID == device.peripheralID }
            }.count

            if snapshotCount >= 3 {
                alerts.append(TrackingAlert(
                    id: UUID(),
                    device: device,
                    alertType: .followingDevice,
                    confidence: min(1.0, Double(snapshotCount) / 5.0),
                    detectedAt: Date()
                ))
            }
        }

        // 3. Surveillance infrastructure
        for device in bleScanner.discoveredDevices where device.category == .infrastructure {
            alerts.append(TrackingAlert(
                id: UUID(),
                device: device,
                alertType: .surveillanceInfrastructure,
                confidence: 0.6,
                detectedAt: Date()
            ))
        }

        // 4. Unknown devices with strong signal seen repeatedly
        for device in bleScanner.discoveredDevices where device.category == .unknown && device.rssi > -50 {
            let snapshotCount = scanSnapshots.filter { snapshot in
                snapshot.devices.contains { $0.peripheralID == device.peripheralID }
            }.count
            if snapshotCount >= 2 {
                alerts.append(TrackingAlert(
                    id: UUID(),
                    device: device,
                    alertType: .stationaryTracker,
                    confidence: 0.5,
                    detectedAt: Date()
                ))
            }
        }

        trackingAlerts = alerts
    }

    private func calculateScore() {
        var score = 100

        let threats = bleScanner.threatDevices
        // Deduct for threat devices
        score -= threats.filter({ $0.threatLevel == .high }).count * 15
        score -= threats.filter({ $0.threatLevel == .medium }).count * 8

        // Deduct for tracking alerts
        score -= trackingAlerts.count * 10

        // Deduct for infrastructure devices
        let infraCount = bleScanner.discoveredDevices.filter { $0.category == .infrastructure }.count
        score -= infraCount * 5

        privacyScore = max(0, min(100, score))
    }
}

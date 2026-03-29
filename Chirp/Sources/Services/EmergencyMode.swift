import Foundation
import OSLog
import UIKit

// MARK: - Audio Quality

/// Audio encoding quality preset.
enum AudioQuality: Sendable {
    /// Normal quality (24 kbps Opus).
    case normal
    /// Emergency quality (8 kbps Opus) — maximizes battery life and range.
    case emergency
}

// MARK: - Emergency Mode

/// Global emergency/disaster toggle that optimizes the entire app for
/// survival scenarios: maximum mesh TTL, aggressive relay, low-bandwidth
/// audio, and periodic location broadcasts.
///
/// Singleton accessed via `EmergencyMode.shared`. State is persisted in
/// UserDefaults so it survives a crash or force-quit.
@Observable
final class EmergencyMode: @unchecked Sendable {

    static let shared = EmergencyMode()

    // MARK: - Public State

    private(set) var isActive: Bool = false

    // MARK: - Emergency Channel

    /// Well-known channel name that all devices switch to in emergency mode.
    static let emergencyChannelName = "EMERGENCY"
    /// Fixed UUID for the emergency channel so all devices agree on the ID.
    static let emergencyChannelID = "00000000-0000-0000-0000-000000000911"

    // MARK: - Derived Properties

    /// Maximum TTL for mesh packets. Emergency mode uses the absolute max.
    var maxTTL: UInt8 {
        isActive ? 8 : MeshPacket.defaultTTL
    }

    /// Beacon broadcast interval. Emergency mode beacons more frequently
    /// (every 10 seconds) to keep the mesh map up to date.
    var beaconInterval: TimeInterval {
        isActive ? 10.0 : 2.0
    }

    /// Audio encoding quality. Emergency mode drops to 8 kbps to save
    /// bandwidth and battery.
    var audioQuality: AudioQuality {
        isActive ? .emergency : .normal
    }

    /// When true, relay every packet regardless of battery thresholds.
    var shouldRelayEverything: Bool {
        isActive
    }

    /// Location broadcast interval in seconds. 0 means disabled (normal mode).
    /// Emergency mode broadcasts location every 30 seconds.
    var locationBroadcastInterval: TimeInterval {
        isActive ? 30.0 : 0
    }

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "EmergencyMode")

    private enum Keys {
        static let isActive = "com.chirpchirp.emergencyMode.isActive"
    }

    // MARK: - Init

    private init() {
        // Restore state from UserDefaults for crash recovery.
        let persisted = UserDefaults.standard.bool(forKey: Keys.isActive)
        if persisted {
            isActive = true
            logger.warning("Emergency mode restored from persisted state (crash recovery)")
        }
    }

    // MARK: - Activation

    /// Activate emergency mode. Optimizes the entire app for disaster scenarios.
    func activate() {
        guard !isActive else {
            logger.info("Emergency mode already active, ignoring duplicate activation")
            return
        }

        logger.critical("EMERGENCY MODE ACTIVATED")

        isActive = true
        UserDefaults.standard.set(true, forKey: Keys.isActive)

        // Enable battery monitoring so the overlay can show battery %.
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }

        NotificationCenter.default.post(
            name: .emergencyModeChanged,
            object: nil,
            userInfo: ["active": true]
        )
    }

    /// Deactivate emergency mode and return to normal operation.
    func deactivate() {
        guard isActive else { return }

        logger.info("Emergency mode deactivated")

        isActive = false
        UserDefaults.standard.set(false, forKey: Keys.isActive)

        NotificationCenter.default.post(
            name: .emergencyModeChanged,
            object: nil,
            userInfo: ["active": false]
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted when emergency mode is activated or deactivated.
    /// `userInfo` contains `["active": Bool]`.
    static let emergencyModeChanged = Notification.Name("com.chirpchirp.emergencyModeChanged")
}

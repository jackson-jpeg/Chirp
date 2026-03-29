import Foundation
import Observation
import OSLog

/// Fires notification-style alerts when friends come into mesh range.
/// Tracks which friends have been seen recently to avoid duplicate alerts.
@Observable
@MainActor
final class ProximityAlert {
    private let logger = Logger(subsystem: Constants.subsystem, category: "ProximityAlert")

    // MARK: - Types

    struct Alert: Identifiable, Sendable {
        let id: UUID
        let friendName: String
        let friendID: String
        let distance: String   // "nearby", "~80m", "~160m"
        let timestamp: Date

        init(friendName: String, friendID: String, distance: String, timestamp: Date = Date()) {
            self.id = UUID()
            self.friendName = friendName
            self.friendID = friendID
            self.distance = distance
            self.timestamp = timestamp
        }
    }

    // MARK: - Public State

    /// Active alerts that haven't been dismissed yet.
    private(set) var recentAlerts: [Alert] = []

    /// Whether proximity alerting is enabled.
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                recentAlerts.removeAll()
            }
        }
    }

    // MARK: - Private

    /// Tracks friend IDs we have already alerted about in this session,
    /// mapped to the time they were last seen. Prevents spam when peers
    /// flicker in and out of range.
    private var alertedFriends: [String: Date] = [:]

    /// Minimum interval before re-alerting about the same friend (5 minutes).
    private let cooldownInterval: TimeInterval = 300

    /// Maximum number of simultaneous alerts shown.
    private let maxVisibleAlerts = 5

    // MARK: - Public API

    /// Check online peers against the friends list and fire alerts for
    /// friends who have newly come into range.
    ///
    /// Call this whenever the peer list changes (from MultipeerTransport.onPeersChanged).
    func checkProximity(onlinePeers: [ChirpPeer], friends: [ChirpFriend]) {
        guard isEnabled else { return }

        let now = Date()
        let onlinePeerIDs = Set(onlinePeers.map(\.id))

        // Prune cooldown entries older than the cooldown window
        alertedFriends = alertedFriends.filter { _, lastAlerted in
            now.timeIntervalSince(lastAlerted) < cooldownInterval
        }

        for friend in friends {
            guard onlinePeerIDs.contains(friend.id) else { continue }

            // Skip if we recently alerted about this friend
            if let lastAlerted = alertedFriends[friend.id],
               now.timeIntervalSince(lastAlerted) < cooldownInterval {
                continue
            }

            // Determine approximate distance from signal strength
            let peer = onlinePeers.first { $0.id == friend.id }
            let distance = estimateDistance(signalStrength: peer?.signalStrength ?? 0)

            let alert = Alert(
                friendName: friend.name,
                friendID: friend.id,
                distance: distance,
                timestamp: now
            )

            recentAlerts.append(alert)
            alertedFriends[friend.id] = now

            // Trim old alerts
            if recentAlerts.count > maxVisibleAlerts {
                recentAlerts.removeFirst(recentAlerts.count - maxVisibleAlerts)
            }

            logger.info("Proximity alert: \(friend.name) is \(distance)")

            // Haptic + sound feedback
            HapticsManager.shared.peerConnected()
            SoundEffects.shared.playPeerJoined()
        }
    }

    /// Dismiss a specific alert.
    func dismiss(_ alert: Alert) {
        recentAlerts.removeAll { $0.id == alert.id }
    }

    /// Dismiss all alerts.
    func dismissAll() {
        recentAlerts.removeAll()
    }

    /// Reset cooldowns — allows re-alerting for all friends on next check.
    func resetCooldowns() {
        alertedFriends.removeAll()
    }

    // MARK: - Distance Estimation

    /// Rough distance estimate based on Bluetooth/WiFi signal strength bars.
    /// ChirpPeer.signalStrength is 0-3.
    private func estimateDistance(signalStrength: Int) -> String {
        switch signalStrength {
        case 3:
            return "nearby"
        case 2:
            return "~80m"
        case 1:
            return "~160m"
        default:
            return "in range"
        }
    }
}

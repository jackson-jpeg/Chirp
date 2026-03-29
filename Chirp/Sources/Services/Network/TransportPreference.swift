import Foundation

/// Determines which transport(s) to use for sending, based on current peer connectivity.
///
/// The rule is simple: skip a transport if no peers need it.
/// - If ALL peers are reachable via Wi-Fi Aware, skip MultipeerConnectivity.
/// - If ALL peers are reachable via MC, skip Wi-Fi Aware.
/// - If no peers are connected, send on both (for discovery).
/// - Forwarding (relay) always uses both transports regardless.
enum TransportPreference {

    /// Returns `true` if at least one peer is only reachable via MultipeerConnectivity.
    static func shouldSendOnMC(peers: [ChirpPeer]) -> Bool {
        guard !peers.isEmpty else { return true } // No peers → send on both for discovery
        return peers.contains { $0.transportType == .multipeer }
    }

    /// Returns `true` if at least one peer is reachable via Wi-Fi Aware.
    static func shouldSendOnWA(peers: [ChirpPeer]) -> Bool {
        guard !peers.isEmpty else { return true }
        return peers.contains { $0.transportType == .wifiAware || $0.transportType == .both }
    }
}

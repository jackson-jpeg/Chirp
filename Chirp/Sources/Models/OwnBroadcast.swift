import Foundation

/// Represents something this device broadcasts that could be used for tracking.
struct OwnBroadcast: Identifiable, Sendable {
    let id: String
    let protocolName: String
    let description: String
    let riskLevel: BLEDevice.ThreatLevel
    let recommendation: String
    /// SF Symbol icon name.
    let icon: String

    /// Detect what this device is currently broadcasting.
    static func detectOwnBroadcasts() -> [OwnBroadcast] {
        var broadcasts: [OwnBroadcast] = []

        // Bluetooth is always on by default on iPhones
        broadcasts.append(OwnBroadcast(
            id: "bluetooth",
            protocolName: "Bluetooth",
            description: "Your device continuously broadcasts BLE advertisements that can be detected by nearby scanners",
            riskLevel: .low,
            recommendation: "Turn off Bluetooth in Settings when not using wireless accessories",
            icon: "antenna.radiowaves.left.and.right"
        ))

        // Wi-Fi probe requests
        broadcasts.append(OwnBroadcast(
            id: "wifi-probes",
            protocolName: "Wi-Fi Probes",
            description: "Your device broadcasts the names of saved Wi-Fi networks, revealing places you've visited",
            riskLevel: .medium,
            recommendation: "Remove saved networks you no longer use in Settings → Wi-Fi → Edit",
            icon: "wifi"
        ))

        // AirDrop
        broadcasts.append(OwnBroadcast(
            id: "airdrop",
            protocolName: "AirDrop",
            description: "When set to 'Everyone', your device name is visible to all nearby Apple devices",
            riskLevel: .low,
            recommendation: "Set AirDrop to 'Contacts Only' or 'Off' in Control Center",
            icon: "airdrop"
        ))

        // ChirpChirp's own broadcasts
        broadcasts.append(OwnBroadcast(
            id: "chirpchirp-mc",
            protocolName: "ChirpChirp Mesh",
            description: "ChirpChirp advertises via Bonjour for MultipeerConnectivity mesh discovery",
            riskLevel: .none,
            recommendation: "This is required for mesh networking. All mesh traffic is encrypted.",
            icon: "dot.radiowaves.left.and.right"
        ))

        return broadcasts
    }
}

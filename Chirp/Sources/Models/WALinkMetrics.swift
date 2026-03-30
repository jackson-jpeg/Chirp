import Foundation

struct WALinkMetrics: Sendable, Identifiable {
    let peerID: String
    let deviceName: String
    var signalStrength: Double? // dBm or normalized
    var throughputCeiling: Double? // bits/s
    var throughputCapacity: Double? // bits/s
    var capacityRatio: Double? // 0-1
    var voiceLatency: Duration?
    var videoLatency: Duration?
    var bestEffortLatency: Duration?
    var connectionUptime: Duration?
    var lastUpdated: Date = Date()

    var id: String { peerID }

    var signalBars: Int { // 0-4
        guard let sig = signalStrength else { return 0 }
        if sig > -50 { return 4 }
        if sig > -60 { return 3 }
        if sig > -70 { return 2 }
        if sig > -80 { return 1 }
        return 0
    }

    var qualityLabel: String {
        guard let ratio = capacityRatio else { return "Unknown" }
        if ratio > 0.7 { return "Excellent" }
        if ratio > 0.4 { return "Good" }
        if ratio > 0.2 { return "Fair" }
        return "Poor"
    }
}

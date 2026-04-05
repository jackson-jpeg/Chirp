import Foundation

/// A Bluetooth Low Energy device detected during a room scan.
struct BLEDevice: Identifiable, Sendable, Codable {
    let id: UUID
    let peripheralID: String
    var name: String?
    var rssi: Int
    var manufacturerID: UInt16?
    var manufacturerName: String?
    var category: DeviceCategory
    var threatLevel: ThreatLevel
    let firstSeen: Date
    var lastSeen: Date
    var advertisedServices: [String]

    enum DeviceCategory: String, Codable, Sendable, CaseIterable {
        case phone
        case tablet
        case computer
        case wearable
        case headphones
        case speaker
        case tracker
        case camera
        case tv
        case iot
        case infrastructure
        case unknown
    }

    enum ThreatLevel: Int, Codable, Sendable, Comparable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .none: "Safe"
            case .low: "Low"
            case .medium: "Unknown"
            case .high: "Flagged"
            }
        }
    }
}

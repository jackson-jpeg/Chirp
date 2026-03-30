import CoreLocation
import Foundation

/// Unified position output from the PositioningEngine.
/// Combines GPS, UWB ranging, dead reckoning, and LIGHTHOUSE WiFi fingerprinting
/// into a single best-available position with confidence scoring.
struct PositionEstimate: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let horizontalAccuracyMeters: Double
    let source: PositionSource
    let confidence: Double              // 0.0 ... 1.0
    let timestamp: Date

    /// Where this estimate came from (ordered by decreasing trustworthiness).
    enum PositionSource: UInt8, Codable, Sendable, Comparable {
        case gps = 0
        case uwbAnchored = 1           // UWB ranging with at least one GPS-anchored node
        case meshCorrected = 2          // Dead reckoning corrected by mesh UWB measurements
        case lighthouseWifi = 3         // WiFi/BLE fingerprint match from LIGHTHOUSE DB
        case deadReckoning = 4          // Inertial dead reckoning only
        case uwbRelative = 5            // UWB ranging, no GPS anchor (relative only)
        case unknown = 255

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        var displayName: String {
            switch self {
            case .gps: return "GPS"
            case .uwbAnchored: return "UWB + GPS"
            case .meshCorrected: return "Mesh Corrected"
            case .lighthouseWifi: return "Indoor Map"
            case .deadReckoning: return "Dead Reckoning"
            case .uwbRelative: return "UWB Relative"
            case .unknown: return "Unknown"
            }
        }
    }

    /// CLLocationCoordinate2D convenience.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// CLLocation convenience for distance calculations.
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Encode as compact mesh-transmittable string.
    /// Format: "POS:lat,lon,acc,source"
    var encoded: String {
        String(format: "POS:%.6f,%.6f,%.1f,%d", latitude, longitude, horizontalAccuracyMeters, source.rawValue)
    }

    /// Decode from "POS:lat,lon,acc,source" string.
    static func decode(_ text: String) -> PositionEstimate? {
        guard text.hasPrefix("POS:") else { return nil }
        let parts = text.dropFirst(4).split(separator: ",")
        guard parts.count >= 4,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              let acc = Double(parts[2]),
              let srcRaw = UInt8(parts[3]),
              let source = PositionSource(rawValue: srcRaw) else { return nil }
        return PositionEstimate(
            latitude: lat,
            longitude: lon,
            altitudeMeters: nil,
            horizontalAccuracyMeters: acc,
            source: source,
            confidence: 1.0 / max(1.0, acc),
            timestamp: Date()
        )
    }
}

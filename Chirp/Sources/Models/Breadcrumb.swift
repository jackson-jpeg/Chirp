import Foundation

/// A single point in a dead-reckoned or GPS-derived trail.
/// Used by LIGHTHOUSE to build crowd-sourced indoor positioning maps.
struct Breadcrumb: Codable, Sendable, Identifiable {
    let id: UUID
    let peerID: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let source: PositionEstimate.PositionSource
    let timestamp: Date
    /// Estimated floor level from barometric altimeter data.
    let floorLevel: Int?

    init(
        peerID: String,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        source: PositionEstimate.PositionSource,
        timestamp: Date = Date(),
        floorLevel: Int? = nil
    ) {
        self.id = UUID()
        self.peerID = peerID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.source = source
        self.timestamp = timestamp
        self.floorLevel = floorLevel
    }

    /// Reconstruct from persisted storage with a known ID.
    init(
        storedID: UUID,
        peerID: String,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        source: PositionEstimate.PositionSource,
        timestamp: Date,
        floorLevel: Int?
    ) {
        self.id = storedID
        self.peerID = peerID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.source = source
        self.timestamp = timestamp
        self.floorLevel = floorLevel
    }
}

/// A trail of breadcrumbs from a single user session.
struct BreadcrumbTrail: Codable, Sendable, Identifiable {
    let id: UUID
    let peerID: String
    let startTime: Date
    var endTime: Date
    var crumbs: [Breadcrumb]

    init(peerID: String, startTime: Date = Date()) {
        self.id = UUID()
        self.peerID = peerID
        self.startTime = startTime
        self.endTime = startTime
        self.crumbs = []
    }

    mutating func addCrumb(_ crumb: Breadcrumb) {
        crumbs.append(crumb)
        endTime = crumb.timestamp
    }

    /// Total distance covered in this trail (meters).
    var totalDistanceMeters: Double {
        guard crumbs.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<crumbs.count {
            let prev = crumbs[i - 1]
            let curr = crumbs[i]
            total += haversineDistance(
                lat1: prev.latitude, lon1: prev.longitude,
                lat2: curr.latitude, lon2: curr.longitude
            )
        }
        return total
    }

    /// Haversine distance between two coordinates in meters.
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

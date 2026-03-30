import Foundation
import NetworkExtension
import OSLog

/// Crowd-sourced indoor positioning service that records breadcrumb trails
/// and WiFi/BLE fingerprints, shares data over the mesh network, and matches
/// incoming radio observations against the local database to produce position
/// estimates when GPS is unavailable.
@Observable
@MainActor
final class LighthouseService {

    // MARK: - Constants

    private static let recordingInterval: TimeInterval = 5.0
    private static let searchRadiusMeters: Double = 100.0
    private static let similarityThreshold: Double = 0.7
    private static let geohashPrecision = 6

    // MARK: - Logger

    private let logger = Logger(subsystem: Constants.subsystem, category: "Lighthouse")

    // MARK: - Dependencies

    private let database: LighthouseDatabase

    // MARK: - Public State

    private(set) var isRecording = false
    private(set) var currentTrail: BreadcrumbTrail?
    private(set) var totalBreadcrumbs: Int = 0
    private(set) var totalFingerprints: Int = 0

    // MARK: - Callbacks

    /// Called when the service needs to send a packet over the mesh.
    /// Parameters: (payload data, destination peer ID or empty for broadcast).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private State

    private var lastRecordedPosition: PositionEstimate?
    private var lastRecordTime: Date = .distantPast
    private var recordingPeerID: String = ""

    // MARK: - Init

    init(database: LighthouseDatabase) {
        self.database = database
        refreshCounts()
    }

    // MARK: - Recording Control

    /// Begin recording a new breadcrumb trail.
    func startRecording(peerID: String) {
        guard !isRecording else {
            logger.warning("Already recording a trail")
            return
        }
        recordingPeerID = peerID
        currentTrail = BreadcrumbTrail(peerID: peerID)
        isRecording = true
        lastRecordTime = .distantPast
        lastRecordedPosition = nil
        logger.info("Started LIGHTHOUSE trail for peer \(peerID, privacy: .public)")
    }

    /// Stop recording the current breadcrumb trail.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        let crumbCount = currentTrail?.crumbs.count ?? 0
        logger.info("Stopped LIGHTHOUSE trail — \(crumbCount, privacy: .public) breadcrumbs recorded")
        currentTrail = nil
        lastRecordedPosition = nil
        refreshCounts()
    }

    // MARK: - Position Recording

    /// Record a position as a breadcrumb if enough time has elapsed and
    /// the position has meaningfully changed.
    func recordPosition(_ estimate: PositionEstimate, peerID: String) {
        guard isRecording, var trail = currentTrail else { return }

        let now = Date()
        guard now.timeIntervalSince(lastRecordTime) >= Self.recordingInterval else { return }

        // Skip if position hasn't moved meaningfully (within accuracy radius)
        if let last = lastRecordedPosition {
            let distance = haversineDistance(
                lat1: last.latitude, lon1: last.longitude,
                lat2: estimate.latitude, lon2: estimate.longitude
            )
            if distance < max(1.0, estimate.horizontalAccuracyMeters) {
                return
            }
        }

        let crumb = Breadcrumb(
            peerID: peerID,
            latitude: estimate.latitude,
            longitude: estimate.longitude,
            accuracyMeters: estimate.horizontalAccuracyMeters,
            source: estimate.source,
            timestamp: now,
            floorLevel: nil
        )

        trail.addCrumb(crumb)
        currentTrail = trail

        database.saveBreadcrumb(crumb, trailID: trail.id.uuidString)

        lastRecordedPosition = estimate
        lastRecordTime = now
        totalBreadcrumbs = database.totalBreadcrumbs

        logger.debug("Breadcrumb recorded at \(estimate.latitude, privacy: .public), \(estimate.longitude, privacy: .public)")
    }

    // MARK: - Fingerprint Recording

    /// Record a WiFi/BLE fingerprint at the given position.
    func recordFingerprint(
        at position: PositionEstimate,
        observations: [RadioObservation],
        peerID: String
    ) {
        guard !observations.isEmpty else { return }

        let fingerprint = WiFiFingerprint(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyMeters: position.horizontalAccuracyMeters,
            floorLevel: nil,
            observations: observations,
            contributorPeerID: peerID
        )

        database.saveFingerprint(fingerprint)
        totalFingerprints = database.totalFingerprints

        logger.info("Fingerprint recorded with \(observations.count, privacy: .public) observations")
    }

    // MARK: - WiFi Scanning

    /// Fetch the current WiFi network as a RadioObservation using NEHotspotNetwork.
    /// Requires the `com.apple.developer.networking.HotspotHelper` entitlement.
    func scanCurrentWiFi() async -> RadioObservation? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                guard let network else {
                    continuation.resume(returning: nil)
                    return
                }
                let observation = RadioObservation(
                    identifier: network.bssid,
                    type: .wifi,
                    rssi: Int(network.signalStrength * -100), // Normalize 0..1 to dBm approximation
                    ssid: network.ssid,
                    channel: nil
                )
                continuation.resume(returning: observation)
            }
        }
    }

    // MARK: - Fingerprint Matching

    /// Attempt to determine position from a set of radio observations by matching
    /// against the local fingerprint database using cosine similarity of RSSI vectors.
    ///
    /// Returns the best matching position if similarity exceeds the threshold.
    func findPosition(for observations: [RadioObservation]) -> PositionEstimate? {
        guard !observations.isEmpty else { return nil }

        // Use the centroid of recent position as search center, or fallback
        guard let searchCenter = lastRecordedPosition else {
            logger.debug("No recent position for fingerprint search center")
            return nil
        }

        let candidates = database.findFingerprints(
            near: searchCenter.latitude,
            longitude: searchCenter.longitude,
            radiusMeters: Self.searchRadiusMeters
        )

        guard !candidates.isEmpty else {
            logger.debug("No fingerprints in search radius")
            return nil
        }

        // Build the observation lookup: identifier -> RSSI
        let observedMap: [String: Int] = Dictionary(
            observations.map { ($0.identifier, $0.rssi) },
            uniquingKeysWith: { first, _ in first }
        )

        var bestSimilarity = 0.0
        var bestFingerprint: WiFiFingerprint?

        for candidate in candidates {
            let similarity = cosineSimilarity(
                observed: observedMap,
                stored: candidate.observations
            )
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestFingerprint = candidate
            }
        }

        guard bestSimilarity >= Self.similarityThreshold, let match = bestFingerprint else {
            logger.debug("Best fingerprint similarity \(bestSimilarity, privacy: .public) below threshold")
            return nil
        }

        logger.info("Fingerprint match: similarity=\(bestSimilarity, privacy: .public) at \(match.latitude, privacy: .public), \(match.longitude, privacy: .public)")

        return PositionEstimate(
            latitude: match.latitude,
            longitude: match.longitude,
            altitudeMeters: nil,
            horizontalAccuracyMeters: max(match.accuracyMeters, 5.0),
            source: .lighthouseWifi,
            confidence: bestSimilarity,
            timestamp: Date()
        )
    }

    // MARK: - Mesh Packet Handling

    /// Dispatch incoming LIGHTHOUSE mesh packets (LHQ! queries and LHR! records).
    func handlePacket(_ data: Data) {
        guard data.count >= 4 else { return }

        let prefix = Array(data.prefix(4))

        if prefix == LighthousePacket.Query.magicPrefix {
            handleQuery(data)
        } else if prefix == LighthousePacket.Record.magicPrefix {
            handleRecord(data)
        } else {
            logger.debug("Unknown LIGHTHOUSE packet prefix")
        }
    }

    /// Handle an incoming LHQ! query — respond with local fingerprint data
    /// for the requested geohash region.
    private func handleQuery(_ data: Data) {
        guard let query = LighthousePacket.Query.from(payload: data) else {
            logger.warning("Failed to decode LHQ! packet")
            return
        }

        logger.info("Received LIGHTHOUSE query from \(query.requestorPeerID, privacy: .public) for geohash \(query.geohashPrefix, privacy: .public)")

        // Decode geohash center for spatial lookup
        let (centerLat, centerLon) = geohashDecode(query.geohashPrefix)

        let fingerprints = database.findFingerprints(
            near: centerLat,
            longitude: centerLon,
            radiusMeters: Self.searchRadiusMeters
        )

        let breadcrumbCount = database.findBreadcrumbs(
            near: centerLat,
            longitude: centerLon,
            radiusMeters: Self.searchRadiusMeters
        ).count

        // Only respond if we have data to share
        guard !fingerprints.isEmpty || breadcrumbCount > 0 else { return }

        let record = LighthousePacket.Record(
            requestID: query.requestID,
            regionHash: query.geohashPrefix,
            fingerprints: fingerprints,
            breadcrumbCount: breadcrumbCount,
            version: 1,
            lastUpdated: Date()
        )

        let payload = record.wirePayload()
        onSendPacket?(payload, query.requestorPeerID)

        logger.info("Sent LHR! response: \(fingerprints.count, privacy: .public) fingerprints, \(breadcrumbCount, privacy: .public) breadcrumbs")
    }

    /// Handle an incoming LHR! record — merge received fingerprints into
    /// the local database.
    private func handleRecord(_ data: Data) {
        guard let record = LighthousePacket.Record.from(payload: data) else {
            logger.warning("Failed to decode LHR! packet")
            return
        }

        logger.info("Received LIGHTHOUSE record: \(record.fingerprints.count, privacy: .public) fingerprints for region \(record.regionHash, privacy: .public)")

        for fingerprint in record.fingerprints {
            database.saveFingerprint(fingerprint)
        }

        refreshCounts()
    }

    // MARK: - Mesh Query

    /// Send a LIGHTHOUSE query for data near the current position.
    func queryMeshForData(peerID: String) {
        guard let position = lastRecordedPosition else {
            logger.debug("No position available for mesh query")
            return
        }

        let geohash = geohashEncode(
            latitude: position.latitude,
            longitude: position.longitude,
            precision: Self.geohashPrecision
        )

        let query = LighthousePacket.Query(
            requestID: UUID(),
            geohashPrefix: geohash,
            requestorPeerID: peerID,
            timestamp: Date()
        )

        let payload = query.wirePayload()
        onSendPacket?(payload, "") // Broadcast

        logger.info("Sent LHQ! for geohash \(geohash, privacy: .public)")
    }

    // MARK: - Maintenance

    /// Prune old data from the database.
    func pruneOldData(days: Int = 30) {
        database.pruneOlderThan(days: days)
        refreshCounts()
    }

    // MARK: - Private Helpers

    private func refreshCounts() {
        totalBreadcrumbs = database.totalBreadcrumbs
        totalFingerprints = database.totalFingerprints
    }

    /// Cosine similarity between an observed RSSI map and a stored fingerprint's
    /// observation list. Only identifiers present in both sets contribute.
    ///
    /// Returns a value in [0, 1] where 1 means identical RSSI patterns.
    private func cosineSimilarity(
        observed: [String: Int],
        stored: [RadioObservation]
    ) -> Double {
        // Build stored map
        let storedMap: [String: Int] = Dictionary(
            stored.map { ($0.identifier, $0.rssi) },
            uniquingKeysWith: { first, _ in first }
        )

        // Find common identifiers
        let commonKeys = Set(observed.keys).intersection(storedMap.keys)
        guard !commonKeys.isEmpty else { return 0.0 }

        var dotProduct = 0.0
        var normObserved = 0.0
        var normStored = 0.0

        for key in commonKeys {
            // Shift RSSI values to positive range for meaningful cosine similarity.
            // Typical RSSI: -30 (strong) to -100 (weak). Add 100 to make positive.
            let obsVal = Double(observed[key]! + 100)
            let stoVal = Double(storedMap[key]! + 100)

            dotProduct += obsVal * stoVal
            normObserved += obsVal * obsVal
            normStored += stoVal * stoVal
        }

        guard normObserved > 0, normStored > 0 else { return 0.0 }

        return dotProduct / (sqrt(normObserved) * sqrt(normStored))
    }

    /// Haversine distance between two coordinates in meters.
    private func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    // MARK: - Geohash Utilities

    /// Encode a coordinate into a geohash string of the given precision.
    private func geohashEncode(
        latitude: Double,
        longitude: Double,
        precision: Int
    ) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLon = true
        var bit = 0
        var charIndex = 0
        var hash = ""

        while hash.count < precision {
            if isLon {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    charIndex = (charIndex << 1) | 1
                    lonRange.0 = mid
                } else {
                    charIndex <<= 1
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    charIndex = (charIndex << 1) | 1
                    latRange.0 = mid
                } else {
                    charIndex <<= 1
                    latRange.1 = mid
                }
            }

            isLon.toggle()
            bit += 1

            if bit == 5 {
                hash.append(base32[charIndex])
                bit = 0
                charIndex = 0
            }
        }

        return hash
    }

    /// Decode a geohash string to approximate center coordinates.
    private func geohashDecode(_ hash: String) -> (latitude: Double, longitude: Double) {
        let base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isLon = true

        for char in hash.lowercased() {
            guard let index = base32.firstIndex(of: char) else { continue }
            let charValue = base32.distance(from: base32.startIndex, to: index)

            for bit in stride(from: 4, through: 0, by: -1) {
                let bitValue = (charValue >> bit) & 1
                if isLon {
                    let mid = (lonRange.0 + lonRange.1) / 2
                    if bitValue == 1 {
                        lonRange.0 = mid
                    } else {
                        lonRange.1 = mid
                    }
                } else {
                    let mid = (latRange.0 + latRange.1) / 2
                    if bitValue == 1 {
                        latRange.0 = mid
                    } else {
                        latRange.1 = mid
                    }
                }
                isLon.toggle()
            }
        }

        return (
            latitude: (latRange.0 + latRange.1) / 2,
            longitude: (lonRange.0 + lonRange.1) / 2
        )
    }
}

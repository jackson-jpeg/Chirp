import CoreLocation
import Foundation
import OSLog

/// Fuses position data from multiple sources (GPS, UWB, dead reckoning, LIGHTHOUSE)
/// into a single best-available position estimate using weighted averaging.
///
/// Sensor fusion weights each source by `1 / max(1, accuracy)` so more precise
/// sources dominate. GPS always wins when available; when GPS is lost the engine
/// seamlessly transitions to mesh-corrected dead reckoning.
actor PositioningEngine {

    // MARK: - Constants

    private static let gpsDegradedThreshold: TimeInterval = 30.0
    private static let sourceStaleThreshold: TimeInterval = 10.0
    private static let maxRecentPositions = 100

    // MARK: - Logger

    private let logger = Logger(subsystem: "com.chirpchirp.app", category: "PositioningEngine")

    // MARK: - Source State

    private var lastGPS: PositionEstimate?
    private var lastDR: PositionEstimate?
    private var lastUWB: PositionEstimate?
    private var lastLighthouse: PositionEstimate?

    /// Known positions of remote peers, keyed by peer ID.
    private var peerPositions: [String: PositionEstimate] = [:]

    /// Ring buffer of fused positions for trail display.
    private var _recentPositions: [PositionEstimate] = []

    /// Timestamp of last GPS update for degradation detection.
    private var lastGPSUpdate: Date?

    // MARK: - Public Read-Only Properties

    /// The current fused position, or `nil` if no sources are available.
    var currentPosition: PositionEstimate? {
        fuse()
    }

    /// Recent fused positions for trail / breadcrumb display.
    var recentPositions: [PositionEstimate] {
        _recentPositions
    }

    /// Number of sources that contributed fresh data within the stale threshold.
    var activeSourceCount: Int {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.sourceStaleThreshold)
        var count = 0
        if let t = lastGPS?.timestamp, t > cutoff { count += 1 }
        if let t = lastDR?.timestamp, t > cutoff { count += 1 }
        if let t = lastUWB?.timestamp, t > cutoff { count += 1 }
        if let t = lastLighthouse?.timestamp, t > cutoff { count += 1 }
        return count
    }

    /// When GPS was last received, if ever.
    var lastGPSTime: Date? {
        lastGPSUpdate
    }

    /// `true` when GPS has not been received for more than 30 seconds.
    var isGPSDegraded: Bool {
        guard let last = lastGPSUpdate else { return true }
        return Date().timeIntervalSince(last) > Self.gpsDegradedThreshold
    }

    // MARK: - Source Updates

    /// Ingest a new GPS fix.
    func updateGPS(latitude: Double, longitude: Double, accuracy: Double, altitude: Double?) {
        let estimate = PositionEstimate(
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: altitude,
            horizontalAccuracyMeters: accuracy,
            source: .gps,
            confidence: min(1.0, 1.0 / max(1.0, accuracy)),
            timestamp: Date()
        )
        lastGPS = estimate
        lastGPSUpdate = Date()
        logger.debug("GPS update: \(latitude, privacy: .public), \(longitude, privacy: .public) acc=\(accuracy, privacy: .public)m")
        recordFusedPosition()
    }

    /// Ingest a UWB range measurement, optionally with the remote peer's known position.
    func updateUWB(measurement: UWBMeasurement, remotePeerPosition: PositionEstimate?) {
        // If we have a remote peer position, attempt mesh-corrected dead reckoning.
        if let remotePos = remotePeerPosition, let dr = lastDR {
            let corrected = meshCorrectDR(
                localDR: dr,
                remotePeerDR: remotePos,
                uwbDistance: Double(measurement.distanceMeters)
            )
            lastUWB = corrected
            // Also update our DR with the correction to reduce ongoing drift.
            lastDR = corrected
            logger.debug("UWB mesh correction applied, peer=\(measurement.remotePeerID, privacy: .public)")
        } else if let remotePos = remotePeerPosition {
            // No DR yet -- use the UWB distance from the remote peer's known position
            // as a rough position estimate (bearing unknown, use remote position as proxy).
            let estimate = PositionEstimate(
                latitude: remotePos.latitude,
                longitude: remotePos.longitude,
                altitudeMeters: remotePos.altitudeMeters,
                horizontalAccuracyMeters: Double(measurement.distanceMeters),
                source: .uwbAnchored,
                confidence: min(1.0, 1.0 / max(1.0, Double(measurement.distanceMeters))),
                timestamp: Date()
            )
            lastUWB = estimate
            logger.debug("UWB anchored estimate from peer=\(measurement.remotePeerID, privacy: .public)")
        } else {
            // Relative-only UWB measurement -- cannot produce absolute position.
            logger.debug("UWB relative only (no remote position), peer=\(measurement.remotePeerID, privacy: .public)")
        }

        // Always store the remote peer position if provided.
        if let remotePos = remotePeerPosition {
            peerPositions[measurement.remotePeerID] = remotePos
        }

        recordFusedPosition()
    }

    /// Ingest a dead-reckoning position estimate.
    func updateDeadReckoning(_ estimate: PositionEstimate) {
        lastDR = estimate
        logger.debug("DR update: \(estimate.latitude, privacy: .public), \(estimate.longitude, privacy: .public)")
        recordFusedPosition()
    }

    /// Ingest a LIGHTHOUSE WiFi fingerprint position estimate.
    func updateLighthouse(_ estimate: PositionEstimate) {
        lastLighthouse = estimate
        logger.debug("LIGHTHOUSE update: \(estimate.latitude, privacy: .public), \(estimate.longitude, privacy: .public)")
        recordFusedPosition()
    }

    /// Register or update a remote peer's position for mesh correction.
    func updatePeerPosition(peerID: String, position: PositionEstimate) {
        peerPositions[peerID] = position
    }

    // MARK: - Sensor Fusion

    /// Weighted-average fusion of all non-stale sources.
    ///
    /// Weight per source = `1.0 / max(1.0, horizontalAccuracyMeters)`.
    /// Fused accuracy = `1.0 / sumOfWeights`.
    private func fuse() -> PositionEstimate? {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.sourceStaleThreshold)

        // Collect fresh sources. Order matters for tie-breaking only.
        var sources: [PositionEstimate] = []
        if let s = lastGPS, s.timestamp > cutoff { sources.append(s) }
        if let s = lastUWB, s.timestamp > cutoff { sources.append(s) }
        if let s = lastLighthouse, s.timestamp > cutoff { sources.append(s) }
        if let s = lastDR, s.timestamp > cutoff { sources.append(s) }

        guard !sources.isEmpty else { return nil }

        // Fast path: single source.
        if sources.count == 1 {
            return sources[0]
        }

        var totalWeight = 0.0
        var weightedLat = 0.0
        var weightedLon = 0.0
        var weightedAlt = 0.0
        var altCount = 0.0
        var bestSource: PositionEstimate.PositionSource = .unknown

        for source in sources {
            let weight = 1.0 / max(1.0, source.horizontalAccuracyMeters)
            totalWeight += weight
            weightedLat += source.latitude * weight
            weightedLon += source.longitude * weight

            if let alt = source.altitudeMeters {
                weightedAlt += alt * weight
                altCount += weight
            }

            // Track the most trustworthy source for labelling.
            if bestSource == .unknown || source.source < bestSource {
                bestSource = source.source
            }
        }

        guard totalWeight > 0 else { return nil }

        let fusedLat = weightedLat / totalWeight
        let fusedLon = weightedLon / totalWeight
        let fusedAlt: Double? = altCount > 0 ? weightedAlt / altCount : nil
        let fusedAccuracy = 1.0 / totalWeight
        let fusedConfidence = min(1.0, totalWeight)

        return PositionEstimate(
            latitude: fusedLat,
            longitude: fusedLon,
            altitudeMeters: fusedAlt,
            horizontalAccuracyMeters: fusedAccuracy,
            source: bestSource,
            confidence: fusedConfidence,
            timestamp: now
        )
    }

    // MARK: - Mesh-Corrected Dead Reckoning

    /// Corrects our DR position using a UWB distance measurement to a remote peer.
    ///
    /// 1. Compute DR-estimated distance between self and remote peer.
    /// 2. Compare with UWB-measured distance.
    /// 3. Error = drDistance - uwbDistance.
    /// 4. Apply half the correction toward/away from remote peer.
    private func meshCorrectDR(
        localDR: PositionEstimate,
        remotePeerDR: PositionEstimate,
        uwbDistance: Double
    ) -> PositionEstimate {
        let localLocation = CLLocation(latitude: localDR.latitude, longitude: localDR.longitude)
        let remoteLocation = CLLocation(latitude: remotePeerDR.latitude, longitude: remotePeerDR.longitude)
        let drDistance = localLocation.distance(from: remoteLocation)

        // Avoid division by zero when positions coincide.
        guard drDistance > 0.001 else {
            return PositionEstimate(
                latitude: localDR.latitude,
                longitude: localDR.longitude,
                altitudeMeters: localDR.altitudeMeters,
                horizontalAccuracyMeters: max(1.0, uwbDistance * 0.3),
                source: .meshCorrected,
                confidence: min(1.0, 1.0 / max(1.0, uwbDistance * 0.3)),
                timestamp: Date()
            )
        }

        let error = drDistance - uwbDistance
        // Apply half the error correction (split evenly between two peers conceptually).
        let correctionFraction = (error / 2.0) / drDistance

        // Unit vector from local toward remote in lat/lon space.
        let dLat = remotePeerDR.latitude - localDR.latitude
        let dLon = remotePeerDR.longitude - localDR.longitude

        let correctedLat = localDR.latitude + dLat * correctionFraction
        let correctedLon = localDR.longitude + dLon * correctionFraction

        // Corrected accuracy is improved over raw DR.
        let correctedAccuracy = max(1.0, localDR.horizontalAccuracyMeters * 0.6)

        return PositionEstimate(
            latitude: correctedLat,
            longitude: correctedLon,
            altitudeMeters: localDR.altitudeMeters,
            horizontalAccuracyMeters: correctedAccuracy,
            source: .meshCorrected,
            confidence: min(1.0, 1.0 / max(1.0, correctedAccuracy)),
            timestamp: Date()
        )
    }

    // MARK: - History

    /// Append the current fused position to the recent trail buffer.
    private func recordFusedPosition() {
        guard let position = fuse() else { return }

        _recentPositions.append(position)
        if _recentPositions.count > Self.maxRecentPositions {
            _recentPositions.removeFirst(_recentPositions.count - Self.maxRecentPositions)
        }
    }
}

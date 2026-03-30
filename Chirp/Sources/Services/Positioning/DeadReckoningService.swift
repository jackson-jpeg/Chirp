#if canImport(CoreMotion)
import CoreMotion
import Foundation
import OSLog

/// Inertial dead reckoning service using pedometer step counting and compass heading.
///
/// When GPS is unavailable, this service estimates the user's position by counting
/// steps (via `CMPedometer`), combining with compass heading, and projecting movement
/// onto latitude/longitude deltas. Relative altitude changes from `CMAltimeter` provide
/// floor-level estimation.
///
/// Drift accumulates at ~3% of distance traveled. Call ``resetDrift(to:)`` when a GPS fix
/// or UWB correction arrives to re-anchor the estimate.
@Observable
@MainActor
final class DeadReckoningService {

    // MARK: - Constants

    private static let defaultStepLength: Double = 0.75 // meters
    private static let stepLengthKey = "com.chirpchirp.stepLength"
    private static let driftRate: Double = 0.03 // 3% per meter traveled
    private static let baseAccuracy: Double = 5.0 // meters
    private static let metersPerDegreeLat: Double = 111_320.0
    private static let minCalibrationSteps: Int = 20
    private static let maxStepLength: Double = 1.5
    private static let minStepLength: Double = 0.3

    // MARK: - Dependencies

    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let logger = Logger(subsystem: Constants.subsystem, category: "DeadReckoning")

    // MARK: - Public State

    /// The current dead-reckoned position estimate, or `nil` if not tracking.
    private(set) var currentPosition: PositionEstimate?

    /// Whether the service is actively tracking movement.
    private(set) var isTracking: Bool = false

    /// Total steps counted since tracking began.
    private(set) var totalStepCount: Int = 0

    /// Accumulated drift estimate in meters since last reset.
    private(set) var accumulatedDrift: Double = 0.0

    /// Current calibrated step length in meters. Persisted to UserDefaults.
    var stepLength: Double {
        didSet {
            let clamped = min(Self.maxStepLength, max(Self.minStepLength, stepLength))
            if clamped != stepLength { stepLength = clamped }
            UserDefaults.standard.set(stepLength, forKey: Self.stepLengthKey)
            logger.info("Step length updated to \(self.stepLength, format: .fixed(precision: 3))m")
        }
    }

    // MARK: - Private State

    private var lastStepCount: Int = 0
    private var headingRadians: Double = 0.0
    private var currentLatitude: Double = 0.0
    private var currentLongitude: Double = 0.0
    private var currentAltitude: Double?
    private var relativeAltitudeOffset: Double = 0.0
    private var trackingStartDate: Date?

    // MARK: - Init

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.stepLengthKey)
        self.stepLength = stored > 0 ? stored : Self.defaultStepLength
    }

    // MARK: - Public Methods

    /// Begin dead reckoning from a known position (e.g., last GPS fix).
    func startTracking(from position: PositionEstimate) {
        guard !isTracking else {
            logger.warning("startTracking called while already tracking; ignoring")
            return
        }

        guard CMPedometer.isStepCountingAvailable() else {
            logger.error("Step counting is not available on this device")
            return
        }

        currentLatitude = position.latitude
        currentLongitude = position.longitude
        currentAltitude = position.altitudeMeters
        accumulatedDrift = 0.0
        totalStepCount = 0
        lastStepCount = 0
        relativeAltitudeOffset = 0.0

        let startDate = Date()
        trackingStartDate = startDate

        emitPosition(accuracy: Self.baseAccuracy)

        startPedometer(from: startDate)
        startAltimeter()

        isTracking = true
        logger.info("Dead reckoning started from (\(position.latitude, format: .fixed(precision: 6)), \(position.longitude, format: .fixed(precision: 6)))")
    }

    /// Stop dead reckoning and release sensor resources.
    func stopTracking() {
        guard isTracking else { return }

        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()

        isTracking = false
        trackingStartDate = nil
        logger.info("Dead reckoning stopped. Total steps: \(self.totalStepCount), drift: \(self.accumulatedDrift, format: .fixed(precision: 1))m")
    }

    /// Update the current compass heading. Called externally by `LocationService`.
    ///
    /// - Parameter headingDegrees: Magnetic or true heading in degrees (0 = north, clockwise).
    func updateHeading(_ headingDegrees: Double) {
        headingRadians = headingDegrees * .pi / 180.0
    }

    /// Reset accumulated drift and re-anchor position to a corrected fix
    /// (GPS, UWB, or mesh correction).
    func resetDrift(to position: PositionEstimate) {
        let previousDrift = accumulatedDrift

        currentLatitude = position.latitude
        currentLongitude = position.longitude
        if let alt = position.altitudeMeters {
            currentAltitude = alt
        }
        accumulatedDrift = 0.0

        emitPosition(accuracy: position.horizontalAccuracyMeters)
        logger.info("Drift reset from \(previousDrift, format: .fixed(precision: 1))m. Re-anchored to (\(position.latitude, format: .fixed(precision: 6)), \(position.longitude, format: .fixed(precision: 6)))")
    }

    /// Auto-calibrate step length by comparing GPS-measured distance against pedometer step count.
    ///
    /// - Parameters:
    ///   - gpsDistance: Distance in meters measured by GPS over a calibration window.
    ///   - stepCount: Number of steps counted over the same window.
    func calibrateStepLength(gpsDistance: Double, stepCount: Int) {
        guard stepCount >= Self.minCalibrationSteps else {
            logger.warning("Calibration rejected: only \(stepCount) steps (minimum \(Self.minCalibrationSteps))")
            return
        }

        guard gpsDistance > 0 else {
            logger.warning("Calibration rejected: GPS distance is zero or negative")
            return
        }

        let computed = gpsDistance / Double(stepCount)
        let clamped = min(Self.maxStepLength, max(Self.minStepLength, computed))

        // Blend with current value to smooth out noisy readings (70% new, 30% old).
        let blended = clamped * 0.7 + stepLength * 0.3

        logger.info("Calibrating step length: GPS=\(gpsDistance, format: .fixed(precision: 1))m / \(stepCount) steps = \(computed, format: .fixed(precision: 3))m -> blended \(blended, format: .fixed(precision: 3))m")
        stepLength = blended
    }

    // MARK: - Pedometer

    private func startPedometer(from date: Date) {
        pedometer.startUpdates(from: date) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.logger.error("Pedometer error: \(error.localizedDescription)")
                    return
                }

                guard let data else { return }
                self.handlePedometerUpdate(data)
            }
        }
    }

    private func handlePedometerUpdate(_ data: CMPedometerData) {
        let currentSteps = data.numberOfSteps.intValue

        guard currentSteps > lastStepCount else { return }

        let deltaSteps = currentSteps - lastStepCount
        lastStepCount = currentSteps
        totalStepCount = currentSteps

        let distance = Double(deltaSteps) * stepLength
        let heading = headingRadians

        // Project movement onto latitude / longitude
        let deltaLat = distance * cos(heading) / Self.metersPerDegreeLat
        let metersPerDegreeLon = Self.metersPerDegreeLat * cos(currentLatitude * .pi / 180.0)
        let deltaLon: Double
        if metersPerDegreeLon > 1.0 {
            deltaLon = distance * sin(heading) / metersPerDegreeLon
        } else {
            // Near the poles; avoid division by near-zero
            deltaLon = 0.0
        }

        currentLatitude += deltaLat
        currentLongitude += deltaLon

        // Accumulate drift estimate
        accumulatedDrift += distance * Self.driftRate

        let accuracy = Self.baseAccuracy + accumulatedDrift
        emitPosition(accuracy: accuracy)

        logger.debug("DR step: +\(deltaSteps) steps, dist=\(distance, format: .fixed(precision: 2))m, heading=\(heading * 180 / .pi, format: .fixed(precision: 1)) deg, drift=\(self.accumulatedDrift, format: .fixed(precision: 1))m")
    }

    // MARK: - Altimeter

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            logger.info("Relative altitude not available on this device")
            return
        }

        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.logger.error("Altimeter error: \(error.localizedDescription)")
                    return
                }

                guard let data else { return }
                self.handleAltimeterUpdate(data)
            }
        }
    }

    private func handleAltimeterUpdate(_ data: CMAltitudeData) {
        let relativeChange = data.relativeAltitude.doubleValue
        if let baseAltitude = currentAltitude {
            // relativeAltitude is the change since altimeter started
            currentAltitude = baseAltitude + relativeChange - relativeAltitudeOffset
            relativeAltitudeOffset = relativeChange
        }

        let estimatedFloor = Int(round(relativeChange / 3.0)) // ~3m per floor
        if abs(estimatedFloor) > 0 {
            logger.debug("Relative altitude: \(relativeChange, format: .fixed(precision: 2))m (~\(estimatedFloor) floors)")
        }
    }

    // MARK: - Position Emission

    private func emitPosition(accuracy: Double) {
        let confidence = max(0.0, min(1.0, 1.0 / max(1.0, accuracy)))

        currentPosition = PositionEstimate(
            latitude: currentLatitude,
            longitude: currentLongitude,
            altitudeMeters: currentAltitude,
            horizontalAccuracyMeters: accuracy,
            source: .deadReckoning,
            confidence: confidence,
            timestamp: Date()
        )
    }
}
#endif

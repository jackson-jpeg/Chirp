#if canImport(NearbyInteraction)
import NearbyInteraction
#endif
import Foundation
import Observation
import OSLog

// MARK: - SessionInfo

struct SessionInfo: Sendable {
    let peerID: String
    var distanceMeters: Float?
    var direction: SIMD3<Float>?
    var lastUpdate: Date
}

// MARK: - UWBService

@Observable
@MainActor
final class UWBService {
    private let logger = Logger(subsystem: Constants.subsystem, category: "UWB")

    // MARK: - Public State

    private(set) var activeSessions: [String: SessionInfo] = [:]
    private(set) var measurements: [UWBMeasurement] = []
    private(set) var isSupported: Bool = false

    // MARK: - Callbacks

    var onSendPacket: ((Data, String) -> Void)?
    var onMeasurement: ((UWBMeasurement) -> Void)?

    // MARK: - Private State

    /// Local peer ID used to tag outgoing measurements.
    private let localPeerID: String

    #if canImport(NearbyInteraction)
    /// Active NI sessions keyed by peer ID.
    private var sessions: [String: NISession] = [:]
    /// Delegate instances kept alive per session (NI holds delegates weakly).
    private var delegates: [String: SessionDelegate] = [:]
    #endif

    /// Maximum concurrent UWB sessions (NearbyInteraction framework limit).
    private let maxConcurrentSessions = 6

    /// Ring buffer capacity for recent measurements.
    private let measurementBufferSize = 50

    // MARK: - Init

    init(localPeerID: String) {
        self.localPeerID = localPeerID
        #if canImport(NearbyInteraction)
        self.isSupported = NISession.deviceCapabilities.supportsDirectionMeasurement
        #else
        self.isSupported = false
        #endif
        if isSupported {
            logger.info("UWB hardware available — ready for ranging")
        } else {
            logger.info("UWB hardware not available on this device")
        }
    }

    // MARK: - Public Methods

    /// Initiate a UWB ranging session with a direct mesh peer.
    ///
    /// Creates an ``NISession``, retrieves the local discovery token,
    /// wraps it in a ``UWBTokenExchange`` packet, and sends it via ``onSendPacket``.
    /// The session begins ranging once we receive the remote peer's token
    /// through ``handleTokenPacket(_:fromPeer:)``.
    func startSession(with peerID: String) {
        #if canImport(NearbyInteraction)
        guard isSupported else {
            logger.warning("Cannot start session — UWB not supported")
            return
        }
        guard sessions[peerID] == nil else {
            logger.debug("Session already exists for peer \(peerID)")
            return
        }
        guard sessions.count < maxConcurrentSessions else {
            logger.warning("Maximum concurrent sessions (\(self.maxConcurrentSessions)) reached — cannot add peer \(peerID)")
            return
        }

        let session = NISession()
        let delegate = SessionDelegate(peerID: peerID) { [weak self] peerID, distance, direction in
            Task { @MainActor [weak self] in
                self?.handleRangingUpdate(peerID: peerID, distance: distance, direction: direction)
            }
        } onInvalidated: { [weak self] peerID, reason in
            Task { @MainActor [weak self] in
                self?.handleSessionInvalidated(peerID: peerID, reason: reason)
            }
        } onSuspended: { [weak self] peerID in
            Task { @MainActor [weak self] in
                self?.logger.info("Session suspended for peer \(peerID)")
            }
        }

        session.delegate = delegate
        sessions[peerID] = session
        delegates[peerID] = delegate

        activeSessions[peerID] = SessionInfo(
            peerID: peerID,
            distanceMeters: nil,
            direction: nil,
            lastUpdate: Date()
        )

        // Retrieve discovery token and send to peer
        guard let discoveryToken = session.discoveryToken else {
            logger.error("Failed to obtain discovery token for session with \(peerID)")
            cleanupSession(peerID: peerID)
            return
        }

        guard let tokenData = try? NSKeyedArchiver.archivedData(
            withRootObject: discoveryToken,
            requiringSecureCoding: true
        ) else {
            logger.error("Failed to serialize discovery token for peer \(peerID)")
            cleanupSession(peerID: peerID)
            return
        }

        let exchange = UWBTokenExchange(
            peerID: localPeerID,
            discoveryToken: tokenData,
            timestamp: Date()
        )
        let payload = exchange.wirePayload()

        logger.info("Sending UWB discovery token to peer \(peerID) (\(tokenData.count) bytes)")
        onSendPacket?(payload, peerID)
        #else
        logger.warning("NearbyInteraction not available — cannot start UWB session")
        #endif
    }

    /// Stop and clean up the UWB session for a specific peer.
    func stopSession(with peerID: String) {
        #if canImport(NearbyInteraction)
        guard sessions[peerID] != nil else { return }
        logger.info("Stopping UWB session with peer \(peerID)")
        cleanupSession(peerID: peerID)
        #endif
    }

    /// Stop all active UWB sessions.
    func stopAllSessions() {
        #if canImport(NearbyInteraction)
        let peerIDs = Array(sessions.keys)
        for peerID in peerIDs {
            cleanupSession(peerID: peerID)
        }
        logger.info("All UWB sessions stopped")
        #endif
    }

    /// Process an incoming mesh packet that may contain a UWB token exchange.
    ///
    /// Validates the ``UWB!`` magic prefix, deserializes the ``UWBTokenExchange``,
    /// extracts the remote discovery token, creates an ``NINearbyPeerConfiguration``,
    /// and runs the corresponding session.
    func handleTokenPacket(_ data: Data, fromPeer peerID: String) {
        #if canImport(NearbyInteraction)
        guard isSupported else { return }

        guard let exchange = UWBTokenExchange.from(payload: data) else {
            logger.warning("Failed to decode UWB token exchange from peer \(peerID)")
            return
        }

        logger.info("Received UWB discovery token from peer \(peerID) (\(exchange.discoveryToken.count) bytes)")

        // Deserialize the remote discovery token
        guard let remoteToken = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NIDiscoveryToken.self,
            from: exchange.discoveryToken
        ) else {
            logger.error("Failed to deserialize remote discovery token from peer \(peerID)")
            return
        }

        // If we don't have a session for this peer yet, create one and send our token back
        if sessions[peerID] == nil {
            startSession(with: peerID)
        }

        guard let session = sessions[peerID] else {
            logger.error("No session available for peer \(peerID) after attempted creation")
            return
        }

        // Configure and run the session with the remote peer's token
        let config = NINearbyPeerConfiguration(peerToken: remoteToken)
        session.run(config)
        logger.info("UWB session running with peer \(peerID)")
        #else
        logger.warning("NearbyInteraction not available — ignoring UWB token packet")
        #endif
    }

    // MARK: - Private Helpers

    #if canImport(NearbyInteraction)
    private func handleRangingUpdate(peerID: String, distance: Float, direction: SIMD3<Float>?) {
        let now = Date()

        // Update session info
        activeSessions[peerID] = SessionInfo(
            peerID: peerID,
            distanceMeters: distance,
            direction: direction,
            lastUpdate: now
        )

        // Create measurement
        let measurement = UWBMeasurement(
            localPeerID: localPeerID,
            remotePeerID: peerID,
            distanceMeters: distance,
            direction: direction,
            timestamp: now
        )

        // Ring buffer: drop oldest if at capacity
        if measurements.count >= measurementBufferSize {
            measurements.removeFirst()
        }
        measurements.append(measurement)

        onMeasurement?(measurement)
    }

    private func handleSessionInvalidated(peerID: String, reason: String) {
        logger.warning("UWB session invalidated for peer \(peerID): \(reason)")
        cleanupSession(peerID: peerID)
    }

    private func cleanupSession(peerID: String) {
        sessions[peerID]?.invalidate()
        sessions.removeValue(forKey: peerID)
        delegates.removeValue(forKey: peerID)
        activeSessions.removeValue(forKey: peerID)
    }
    #endif
}

// MARK: - SessionDelegate (non-MainActor, receives NI callbacks on arbitrary queues)

#if canImport(NearbyInteraction)
private final class SessionDelegate: NSObject, NISessionDelegate, Sendable {
    let peerID: String
    private let onUpdate: @Sendable (String, Float, SIMD3<Float>?) -> Void
    private let onInvalidated: @Sendable (String, String) -> Void
    private let onSuspended: @Sendable (String) -> Void

    init(
        peerID: String,
        onUpdate: @escaping @Sendable (String, Float, SIMD3<Float>?) -> Void,
        onInvalidated: @escaping @Sendable (String, String) -> Void,
        onSuspended: @escaping @Sendable (String) -> Void
    ) {
        self.peerID = peerID
        self.onUpdate = onUpdate
        self.onInvalidated = onInvalidated
        self.onSuspended = onSuspended
        super.init()
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        for object in nearbyObjects {
            guard let distance = object.distance else { continue }

            let direction: SIMD3<Float>?
            if let dir = object.direction {
                direction = dir
            } else {
                direction = nil
            }

            onUpdate(peerID, distance, direction)
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        onInvalidated(peerID, error.localizedDescription)
    }

    func sessionWasSuspended(_ session: NISession) {
        onSuspended(peerID)
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // Session will automatically resume ranging — no action needed.
        // The framework re-runs the last configuration.
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        switch reason {
        case .peerEnded:
            onInvalidated(peerID, "Peer ended session")
        case .timeout:
            onInvalidated(peerID, "Session timed out")
        @unknown default:
            onInvalidated(peerID, "Unknown removal reason")
        }
    }
}
#endif

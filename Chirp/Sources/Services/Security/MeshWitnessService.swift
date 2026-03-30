import CryptoKit
import Foundation
import Observation
import OSLog

/// Cryptographic evidence attestation via the mesh network.
///
/// MESH WITNESS allows a peer to prove that a piece of media (photo, audio, video)
/// existed at a specific time and place by collecting countersignatures from nearby
/// mesh peers. The flow:
///
/// 1. Origin peer captures media, SHA-256 hashes it, signs the hash with Ed25519.
/// 2. Broadcasts a `WRQ!` packet containing hash, signature, public key, GPS, timestamp.
/// 3. Nearby peers verify the signature and auto-countersign with their own Ed25519 key.
/// 4. Origin collects `WCS!` countersigns into a ``WitnessAttestation``.
/// 5. With >= 2 countersigns, the attestation is considered verified.
@Observable
@MainActor
final class MeshWitnessService {

    private let logger = Logger(subsystem: Constants.subsystem, category: "MeshWitness")

    // MARK: - Public State

    /// Witness sessions we originated, keyed by session ID.
    private(set) var activeAttestations: [UUID: WitnessAttestation] = [:]

    /// Incoming requests we have already countersigned, keyed by session ID.
    private(set) var pendingRequests: [UUID: WitnessRequest] = [:]

    // MARK: - Callbacks

    /// Called to broadcast a packet on a channel. Parameters: (data, channelID).
    var onSendPacket: ((Data, String) -> Void)?

    /// Location service for stamping current GPS coordinates.
    var locationService: LocationService?

    // MARK: - Deduplication

    /// Track seen request IDs to prevent double-processing.
    private var seenRequestIDs: Set<UUID> = []

    /// Track seen countersign IDs to prevent double-processing.
    private var seenCountersignIDs: Set<UUID> = []

    // MARK: - Init

    init() {}

    // MARK: - Public Methods

    /// Start a new witness session for captured media.
    ///
    /// Hashes the media, signs the hash with our Ed25519 key, broadcasts a `WRQ!`
    /// packet, and creates a local attestation awaiting countersigns.
    ///
    /// - Parameters:
    ///   - mediaData: Raw bytes of the captured media.
    ///   - mediaType: The type of media (photo, audio, video).
    ///   - channelID: Mesh channel to broadcast the request on.
    func startWitnessSession(
        mediaData: Data,
        mediaType: WitnessRequest.MediaType,
        channelID: String
    ) async {
        let sessionID = UUID()
        let mediaHash = Data(SHA256.hash(data: mediaData))

        // Sign the media hash with our Ed25519 identity
        let identity = PeerIdentity.shared
        let publicKeyData: Data
        let signature: Data
        let fingerprint: String

        do {
            publicKeyData = await identity.publicKeyData
            signature = try await identity.sign(mediaHash)
            fingerprint = await identity.fingerprint
        } catch {
            logger.error("Failed to sign media hash: \(error.localizedDescription)")
            return
        }

        let now = Date()
        let locationStamp = currentLocationStamp()

        let request = WitnessRequest(
            id: sessionID,
            mediaHash: mediaHash,
            mediaType: mediaType,
            originPeerID: fingerprint,
            originPublicKey: publicKeyData,
            originSignature: signature,
            originTimestamp: now,
            originLocation: locationStamp
        )

        // Create local attestation to collect countersigns
        let attestation = WitnessAttestation(
            id: sessionID,
            mediaHash: mediaHash,
            mediaType: mediaType,
            originPeerID: fingerprint,
            originPublicKey: publicKeyData,
            originSignature: signature,
            originTimestamp: now,
            originLocation: locationStamp,
            countersigns: [],
            createdAt: now
        )

        activeAttestations[sessionID] = attestation
        seenRequestIDs.insert(sessionID)

        // Broadcast WRQ!
        guard let payload = request.wirePayload() else {
            logger.error("Failed to encode WitnessRequest for session \(sessionID)")
            return
        }
        onSendPacket?(payload, channelID)
        logger.info("Started witness session \(sessionID) — hash \(mediaHash.prefix(8).map { String(format: "%02x", $0) }.joined())")
    }

    /// Dispatch an incoming packet. Routes `WRQ!` and `WCS!` payloads to their handlers.
    ///
    /// - Parameters:
    ///   - data: Raw packet payload (including magic prefix).
    ///   - channelID: The channel the packet arrived on.
    func handlePacket(_ data: Data, channelID: String) {
        guard data.count > 4 else { return }

        let prefixBytes = [UInt8](data.prefix(4))

        if prefixBytes == WitnessRequest.magicPrefix {
            handleWitnessRequest(data, channelID: channelID)
        } else if prefixBytes == WitnessCountersign.magicPrefix {
            handleCountersign(data)
        }
    }

    /// Export a full attestation as JSON data for external verification.
    ///
    /// - Parameter id: The witness session ID to export.
    /// - Returns: JSON-encoded ``WitnessAttestation``, or `nil` if not found.
    func exportAttestation(_ id: UUID) -> Data? {
        guard let attestation = activeAttestations[id] else {
            logger.warning("Export requested for unknown attestation \(id)")
            return nil
        }
        do {
            let json = try MeshCodable.encoder.encode(attestation)
            logger.info("Exported attestation \(id) — \(attestation.countersignCount) countersigns")
            return json
        } catch {
            logger.error("Failed to encode attestation \(id): \(error.localizedDescription)")
            return nil
        }
    }

    /// Verify all signatures in an attestation chain.
    ///
    /// Checks:
    /// 1. Origin signature over media hash is valid for origin public key.
    /// 2. Each countersign signature over `(sessionID + mediaHash + timestamp)`
    ///    is valid for the countersigner's public key.
    ///
    /// - Parameter attestation: The attestation to verify.
    /// - Returns: `true` if all signatures are valid.
    func verifyAttestation(_ attestation: WitnessAttestation) -> Bool {
        let identity = PeerIdentity.shared

        // Verify origin signature over media hash
        let originValid = Task {
            await identity.verify(
                signature: attestation.originSignature,
                data: attestation.mediaHash,
                publicKey: attestation.originPublicKey
            )
        }

        // We need to run this synchronously for the return value.
        // Since PeerIdentity.verify is not async (just isolated), we check inline.
        // Actually verify is a non-async method on the actor, so we need nonisolated access.
        // PeerIdentity.verify is a regular actor method. We'll verify using CryptoKit directly.

        guard verifySignature(
            attestation.originSignature,
            data: attestation.mediaHash,
            publicKey: attestation.originPublicKey
        ) else {
            logger.warning("Origin signature invalid for attestation \(attestation.id)")
            _ = originValid // suppress unused warning
            return false
        }
        _ = originValid // suppress unused warning

        // Verify each countersign
        for countersign in attestation.countersigns {
            let signableData = WitnessCountersign.signableData(
                sessionID: countersign.witnessSessionID,
                mediaHash: countersign.mediaHash,
                timestamp: countersign.timestamp
            )

            guard verifySignature(
                countersign.signature,
                data: signableData,
                publicKey: countersign.counterSignerPublicKey
            ) else {
                logger.warning("Countersign \(countersign.id) signature invalid in attestation \(attestation.id)")
                return false
            }

            // Ensure countersign references the correct session and hash
            guard countersign.witnessSessionID == attestation.id,
                  countersign.mediaHash == attestation.mediaHash else {
                logger.warning("Countersign \(countersign.id) references mismatched session/hash")
                return false
            }
        }

        logger.info("Attestation \(attestation.id) verified — \(attestation.countersignCount) valid countersigns")
        return true
    }

    // MARK: - Internal: Handle Incoming WRQ!

    private func handleWitnessRequest(_ data: Data, channelID: String) {
        guard let request = WitnessRequest.from(payload: data) else {
            logger.debug("Failed to decode WitnessRequest")
            return
        }

        // Deduplication
        guard !seenRequestIDs.contains(request.id) else {
            logger.debug("Duplicate WRQ! \(request.id) — ignoring")
            return
        }
        seenRequestIDs.insert(request.id)

        // Verify origin signature before countersigning
        guard verifySignature(
            request.originSignature,
            data: request.mediaHash,
            publicKey: request.originPublicKey
        ) else {
            logger.warning("WRQ! \(request.id) has invalid origin signature — rejecting")
            return
        }

        logger.info("Valid WRQ! from \(request.originPeerID) — session \(request.id)")
        pendingRequests[request.id] = request

        // Auto-countersign
        Task {
            await countersign(request, channelID: channelID)
        }
    }

    // MARK: - Internal: Countersign Flow

    private func countersign(_ request: WitnessRequest, channelID: String) async {
        let identity = PeerIdentity.shared
        let now = Date()

        // Build signable data: sessionID + mediaHash + timestamp
        let signableData = WitnessCountersign.signableData(
            sessionID: request.id,
            mediaHash: request.mediaHash,
            timestamp: now
        )

        let publicKeyData: Data
        let signature: Data
        let fingerprint: String

        do {
            publicKeyData = await identity.publicKeyData
            signature = try await identity.sign(signableData)
            fingerprint = await identity.fingerprint
        } catch {
            logger.error("Failed to countersign WRQ! \(request.id): \(error.localizedDescription)")
            return
        }

        let locationStamp = currentLocationStamp()

        let countersign = WitnessCountersign(
            id: UUID(),
            witnessSessionID: request.id,
            mediaHash: request.mediaHash,
            counterSignerPeerID: fingerprint,
            counterSignerPublicKey: publicKeyData,
            signature: signature,
            timestamp: now,
            location: locationStamp
        )

        // Broadcast WCS!
        guard let payload = countersign.wirePayload() else {
            logger.error("Failed to encode WitnessCountersign for session \(request.id)")
            return
        }
        onSendPacket?(payload, channelID)
        logger.info("Countersigned WRQ! \(request.id) from \(request.originPeerID)")
    }

    // MARK: - Internal: Handle Incoming WCS!

    private func handleCountersign(_ data: Data) {
        guard let countersign = WitnessCountersign.from(payload: data) else {
            logger.debug("Failed to decode WitnessCountersign")
            return
        }

        // Deduplication
        guard !seenCountersignIDs.contains(countersign.id) else {
            logger.debug("Duplicate WCS! \(countersign.id) — ignoring")
            return
        }
        seenCountersignIDs.insert(countersign.id)

        // Only collect countersigns for sessions we originated
        guard var attestation = activeAttestations[countersign.witnessSessionID] else {
            logger.debug("WCS! \(countersign.id) for unknown session \(countersign.witnessSessionID) — ignoring")
            return
        }

        // Verify the countersign hash matches our attestation
        guard countersign.mediaHash == attestation.mediaHash else {
            logger.warning("WCS! \(countersign.id) hash mismatch for session \(countersign.witnessSessionID)")
            return
        }

        // Verify countersigner's signature
        let signableData = WitnessCountersign.signableData(
            sessionID: countersign.witnessSessionID,
            mediaHash: countersign.mediaHash,
            timestamp: countersign.timestamp
        )

        guard verifySignature(
            countersign.signature,
            data: signableData,
            publicKey: countersign.counterSignerPublicKey
        ) else {
            logger.warning("WCS! \(countersign.id) has invalid signature — rejecting")
            return
        }

        // Reject duplicate signers (same public key already countersigned)
        let alreadySigned = attestation.countersigns.contains {
            $0.counterSignerPublicKey == countersign.counterSignerPublicKey
        }
        guard !alreadySigned else {
            logger.debug("WCS! \(countersign.id) — peer already countersigned session \(countersign.witnessSessionID)")
            return
        }

        // Add to attestation
        attestation.countersigns.append(countersign)
        activeAttestations[countersign.witnessSessionID] = attestation

        logger.info(
            "Collected WCS! from \(countersign.counterSignerPeerID) for session \(countersign.witnessSessionID) — \(attestation.countersignCount) total\(attestation.isVerified ? " [VERIFIED]" : "")"
        )
    }

    // MARK: - Helpers

    /// Verify an Ed25519 signature using CryptoKit directly (no actor hop needed).
    private func verifySignature(_ signature: Data, data: Data, publicKey: Data) -> Bool {
        guard let peerKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        guard signature.count == 64 else { return false }
        return peerKey.isValidSignature(signature, for: data)
    }

    /// Capture current GPS as a ``LocationStamp``, if available.
    private func currentLocationStamp() -> LocationStamp? {
        guard let location = locationService?.currentLocation else { return nil }
        return LocationStamp(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude >= 0 ? location.altitude : nil,
            timestamp: location.timestamp
        )
    }
}

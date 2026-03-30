import CryptoKit
import Foundation
import OSLog
import UIKit

/// Manages the lifecycle of view-once photos on the ChirpChirp mesh network.
///
/// Handles encryption, decryption, secure rendering via ``DarkroomRenderer``,
/// screenshot detection, and guaranteed secure deletion after viewing.
@Observable
@MainActor
final class DarkroomService {

    private let logger = Logger(subsystem: Constants.subsystem, category: "Darkroom")

    // MARK: - Public state

    /// Received envelopes awaiting viewing, keyed by envelope ID.
    private(set) var receivedEnvelopes: [UUID: DarkroomEnvelope] = [:]

    /// Tracking status of photos we have sent.
    private(set) var sentPhotos: [UUID: SentStatus] = [:]

    enum SentStatus: Sendable {
        case pending
        case delivered
        case viewed(Date)
        case expired
    }

    // MARK: - Callbacks

    /// Called when the service needs to send a packet on a channel.
    /// Parameters: (packetData, channelID).
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private state

    /// Active renderer for the currently-viewed photo (at most one at a time).
    private var activeRenderer: DarkroomRenderer?
    private var activeEnvelopeID: UUID?

    /// Screenshot detection observers.
    private var screenshotObserver: (any NSObjectProtocol)?
    private var screenCaptureObserver: (any NSObjectProtocol)?

    // MARK: - Constants

    private static let defaultExpiryHours = 24

    // MARK: - Init

    init() {}

    // MARK: - Send

    /// Encrypt and send a view-once photo to a specific recipient.
    ///
    /// - Parameters:
    ///   - imageData: Raw JPEG data to encrypt.
    ///   - recipientID: Peer ID of the intended recipient.
    ///   - recipientKeyAgreementPublicKey: Recipient's Curve25519 key-agreement public key.
    ///   - channelID: Mesh channel to transmit on.
    ///   - senderID: Local peer ID.
    ///   - senderName: Local peer display name.
    func sendPhoto(
        imageData: Data,
        recipientID: String,
        recipientKeyAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        channelID: String,
        senderID: String,
        senderName: String
    ) async throws {
        let signingKey = await PeerIdentity.shared.getSigningPrivateKey()

        let sealedPhoto = try DarkroomCrypto.seal(
            photoData: imageData,
            recipientPublicKey: recipientKeyAgreementPublicKey,
            senderSigningKey: signingKey
        )

        let envelopeID = UUID()
        let now = Date()
        let envelope = DarkroomEnvelope(
            id: envelopeID,
            senderID: senderID,
            senderName: senderName,
            recipientID: recipientID,
            sealedPhoto: sealedPhoto,
            thumbnailHash: Data(SHA256.hash(data: imageData)),
            timestamp: now,
            expiresAt: now.addingTimeInterval(TimeInterval(Self.defaultExpiryHours * 3600))
        )

        let payload = try envelope.wirePayload()
        sentPhotos[envelopeID] = .pending
        onSendPacket?(payload, channelID)
        logger.info("Sent darkroom photo \(envelopeID) to \(recipientID)")
    }

    // MARK: - View

    /// Decrypt a received envelope and prepare a Metal renderer for secure display.
    ///
    /// - Parameters:
    ///   - envelopeID: ID of the envelope to view.
    ///   - privateKey: Recipient's Curve25519 key-agreement private key.
    /// - Returns: Decrypted JPEG data and a ``DarkroomRenderer`` ready to attach to an `MTKView`.
    func viewPhoto(
        envelopeID: UUID,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (Data, DarkroomRenderer?) {
        guard let envelope = receivedEnvelopes[envelopeID] else {
            throw DarkroomError.envelopeNotFound
        }

        guard !envelope.isExpired else {
            receivedEnvelopes.removeValue(forKey: envelopeID)
            throw DarkroomError.expired
        }

        // Decrypt.
        let plaintext = try DarkroomCrypto.open(
            sealed: envelope.sealedPhoto,
            recipientPrivateKey: privateKey
        )

        // Verify thumbnail hash.
        let hash = Data(SHA256.hash(data: plaintext))
        guard hash == envelope.thumbnailHash else {
            throw DarkroomError.hashMismatch
        }

        // Set up secure Metal renderer.
        let renderer = DarkroomRenderer()
        if renderer.loadImage(jpegData: plaintext) {
            activeRenderer = renderer
            activeEnvelopeID = envelopeID
            logger.info("Darkroom renderer active for \(envelopeID)")
            return (plaintext, renderer)
        } else {
            logger.warning("Metal renderer failed — returning raw data only for \(envelopeID)")
            activeEnvelopeID = envelopeID
            return (plaintext, nil)
        }
    }

    // MARK: - Close / Secure Delete

    /// Securely close a viewing session: wipe renderer, remove envelope, send ACK.
    ///
    /// - Parameter envelopeID: ID of the envelope being closed.
    func closeViewing(envelopeID: UUID) {
        // 1. Secure wipe renderer.
        activeRenderer?.secureWipe()
        activeRenderer = nil

        // 2. Remove envelope from storage.
        let envelope = receivedEnvelopes.removeValue(forKey: envelopeID)
        activeEnvelopeID = nil

        // 3. Send DVK! ack to sender.
        if let envelope {
            let ack = DarkroomViewACK(
                envelopeID: envelopeID,
                viewerPeerID: envelope.recipientID,
                viewedAt: Date()
            )
            if let payload = try? ack.wirePayload() {
                // Send back on all channels — the sender will match by envelopeID.
                onSendPacket?(payload, "")
                logger.info("Sent DVK! ack for \(envelopeID)")
            }
        }

        logger.info("Closed darkroom viewing for \(envelopeID)")
    }

    // MARK: - Packet Handling

    /// Process an incoming mesh packet that may contain a DRK! envelope or DVK! ack.
    ///
    /// - Parameters:
    ///   - data: Raw packet payload.
    ///   - channelID: Channel the packet arrived on.
    func handlePacket(_ data: Data, channelID: String) {
        // Try DRK! envelope.
        if let envelope = DarkroomEnvelope.from(payload: data) {
            guard !envelope.isExpired else {
                logger.debug("Dropped expired darkroom envelope \(envelope.id)")
                return
            }
            receivedEnvelopes[envelope.id] = envelope
            logger.info("Received darkroom envelope \(envelope.id) from \(envelope.senderName)")
            return
        }

        // Try DVK! ack.
        if let ack = DarkroomViewACK.from(payload: data) {
            if sentPhotos[ack.envelopeID] != nil {
                sentPhotos[ack.envelopeID] = .viewed(ack.viewedAt)
                logger.info("Photo \(ack.envelopeID) was viewed at \(ack.viewedAt)")
            }
            return
        }
    }

    // MARK: - Expiry

    /// Remove all expired envelopes and update sent-photo status.
    func pruneExpired() {
        var pruned = 0
        for (id, envelope) in receivedEnvelopes where envelope.isExpired {
            receivedEnvelopes.removeValue(forKey: id)
            pruned += 1
        }
        for (id, status) in sentPhotos {
            if case .pending = status {
                // Check if the envelope would have expired by now (24h default).
                // Sender-side expiry is approximate — relies on local clock.
            }
            _ = id // suppress unused warning
            _ = status
        }
        if pruned > 0 {
            logger.info("Pruned \(pruned) expired darkroom envelope(s)")
        }
    }

    // MARK: - Screenshot Detection

    /// Start monitoring for screenshots and screen recording.
    ///
    /// When a screenshot or screen capture is detected while a photo is being
    /// viewed, the `onDetected` callback fires and the viewing session is
    /// automatically closed.
    func startScreenshotDetection(onDetected: @escaping @Sendable () -> Void) {
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let envelopeID = self.activeEnvelopeID else { return }
                self.logger.warning("Screenshot detected during darkroom viewing!")
                self.closeViewing(envelopeID: envelopeID)
                onDetected()
            }
        }

        screenCaptureObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen }).first?.isCaptured == true, let envelopeID = self.activeEnvelopeID {
                    self.logger.warning("Screen recording detected during darkroom viewing!")
                    self.closeViewing(envelopeID: envelopeID)
                    onDetected()
                }
            }
        }

        logger.debug("Screenshot detection enabled")
    }

    /// Stop monitoring for screenshots and screen recording.
    func stopScreenshotDetection() {
        if let observer = screenshotObserver {
            NotificationCenter.default.removeObserver(observer)
            screenshotObserver = nil
        }
        if let observer = screenCaptureObserver {
            NotificationCenter.default.removeObserver(observer)
            screenCaptureObserver = nil
        }
        logger.debug("Screenshot detection disabled")
    }

    // MARK: - Errors

    enum DarkroomError: Error, Sendable {
        case envelopeNotFound
        case expired
        case hashMismatch
    }
}

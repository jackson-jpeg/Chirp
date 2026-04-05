import Foundation
import OSLog
import Security

/// Delivers gateway messages to the outside world via Twilio (SMS) and SendGrid (email).
///
/// API credentials are stored securely in the Keychain via ``GatewayKeychain``.
/// Failed deliveries are retried with exponential backoff (3 attempts: 2s, 4s, 8s).
@Observable
@MainActor
final class GatewayDeliveryService {

    static let shared = GatewayDeliveryService()

    // MARK: - Types

    enum DeliveryStatus: String, Sendable {
        case pending
        case sent
        case failed
    }

    /// Result of a delivery attempt, posted back to the sender via mesh.
    struct DeliveryReceipt: Codable, Sendable {
        let messageID: UUID
        let status: String          // "sent" or "failed"
        let detail: String?
        let timestamp: Date
    }

    // MARK: - Public State

    /// Last delivery status by message ID, for UI feedback.
    private(set) var deliveryStatuses: [UUID: DeliveryStatus] = [:]

    // MARK: - Constants

    /// Magic bytes for gateway delivery receipt: `GDR!` — but we use 3-byte prefix for consistency.
    /// Actually 4 bytes to distinguish from GW!/GR!.
    static let receiptMagic: [UInt8] = [0x47, 0x44, 0x52, 0x21]   // GDR!

    private static let maxRetries = 3
    private static let baseDelay: TimeInterval = 2.0

    // MARK: - Private

    private let logger = Logger(subsystem: Constants.subsystem, category: "GatewayDelivery")
    private let session: URLSession

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Delivery

    /// Deliver a gateway message via SMS or email, with retry logic.
    /// Returns the final delivery status.
    @discardableResult
    func deliver(_ message: MeshGateway.GatewayMessage) async -> DeliveryStatus {
        deliveryStatuses[message.id] = .pending

        if let phone = message.recipientPhone {
            let status = await deliverSMS(message: message, to: phone)
            deliveryStatuses[message.id] = status
            return status
        } else if let email = message.recipientEmail {
            let status = await deliverEmail(message: message, to: email)
            deliveryStatuses[message.id] = status
            return status
        } else {
            logger.warning("Gateway message \(message.id) has no recipient")
            deliveryStatuses[message.id] = .failed
            return .failed
        }
    }

    // MARK: - SMS (Twilio)

    private func deliverSMS(message: MeshGateway.GatewayMessage, to phone: String) async -> DeliveryStatus {
        guard let accountSID = GatewayKeychain.retrieve(key: .twilioAccountSID),
              let authToken = GatewayKeychain.retrieve(key: .twilioAuthToken),
              let fromNumber = GatewayKeychain.retrieve(key: .twilioFromNumber) else {
            logger.error("Twilio credentials not configured in Keychain")
            return .failed
        }

        let url = URL(string: "https://api.twilio.com/2010-04-01/Accounts/\(accountSID)/Messages.json")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Basic auth: base64(accountSID:authToken)
        let credentials = "\(accountSID):\(authToken)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")

        let body = "To=\(phone.urlQueryEncoded)&From=\(fromNumber.urlQueryEncoded)&Body=\(message.message.urlQueryEncoded)"
        request.httpBody = body.data(using: .utf8)

        return await performWithRetry(request: request, label: "SMS to \(phone)", messageID: message.id)
    }

    // MARK: - Email (SendGrid)

    private func deliverEmail(message: MeshGateway.GatewayMessage, to email: String) async -> DeliveryStatus {
        guard let apiKey = GatewayKeychain.retrieve(key: .sendGridAPIKey),
              let fromEmail = GatewayKeychain.retrieve(key: .sendGridFromEmail) else {
            logger.error("SendGrid credentials not configured in Keychain")
            return .failed
        }

        let url = URL(string: "https://api.sendgrid.com/v3/mail/send")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "personalizations": [
                ["to": [["email": email]]]
            ],
            "from": ["email": fromEmail, "name": "Chirp Gateway"],
            "subject": "Message from \(message.fromPeerName) via Chirp",
            "content": [
                ["type": "text/plain", "value": message.message]
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        return await performWithRetry(request: request, label: "Email to \(email)", messageID: message.id)
    }

    // MARK: - Retry Logic

    private func performWithRetry(request: URLRequest, label: String, messageID: UUID) async -> DeliveryStatus {
        for attempt in 1...Self.maxRetries {
            do {
                let (_, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    logger.info("[\(label)] delivered on attempt \(attempt)")
                    return .sent
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    logger.warning("[\(label)] HTTP \(code) on attempt \(attempt)")
                }
            } catch {
                logger.warning("[\(label)] attempt \(attempt) failed: \(error.localizedDescription)")
            }

            if attempt < Self.maxRetries {
                let delay = Self.baseDelay * pow(2.0, Double(attempt - 1))
                logger.info("[\(label)] retrying in \(delay)s")
                try? await Task.sleep(for: .seconds(delay))
            }
        }

        logger.error("[\(label)] all \(Self.maxRetries) attempts exhausted")
        return .failed
    }

    // MARK: - Delivery Receipt

    /// Encode a delivery receipt for mesh broadcast back to the sender.
    func encodeDeliveryReceipt(messageID: UUID, status: DeliveryStatus, detail: String? = nil) -> Data? {
        let receipt = DeliveryReceipt(
            messageID: messageID,
            status: status.rawValue,
            detail: detail,
            timestamp: Date()
        )

        guard let json = try? MeshCodable.encoder.encode(receipt) else { return nil }
        var payload = Data(Self.receiptMagic)
        payload.append(json)
        return payload
    }

    /// Decode and handle an incoming delivery receipt from the mesh.
    func handleDeliveryReceipt(_ data: Data) {
        let jsonData = data.dropFirst(Self.receiptMagic.count)

        do {
            let receipt = try MeshCodable.decoder.decode(DeliveryReceipt.self, from: Data(jsonData))
            let status: DeliveryStatus = receipt.status == "sent" ? .sent : .failed
            deliveryStatuses[receipt.messageID] = status
            logger.info("Delivery receipt: \(receipt.messageID) -> \(receipt.status)")
        } catch {
            logger.debug("Failed to decode delivery receipt: \(error.localizedDescription)")
        }
    }
}

// MARK: - Gateway Keychain

/// Secure storage for gateway API credentials, following the same Keychain
/// pattern as ``KeychainHelper``.
enum GatewayKeychain: Sendable {

    enum Key: String, Sendable {
        case twilioAccountSID   = "gateway.twilio.accountSID"
        case twilioAuthToken    = "gateway.twilio.authToken"
        case twilioFromNumber   = "gateway.twilio.fromNumber"
        case sendGridAPIKey     = "gateway.sendgrid.apiKey"
        case sendGridFromEmail  = "gateway.sendgrid.fromEmail"
    }

    private static let service = "com.chirpchirp.gateway"

    /// Store a credential value for the given key.
    @discardableResult
    static func store(key: Key, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Retrieve a credential value for the given key.
    static func retrieve(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete a credential for the given key.
    @discardableResult
    static func delete(key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// Check if credentials are configured for SMS delivery.
    static var hasTwilioCredentials: Bool {
        retrieve(key: .twilioAccountSID) != nil &&
        retrieve(key: .twilioAuthToken) != nil &&
        retrieve(key: .twilioFromNumber) != nil
    }

    /// Check if credentials are configured for email delivery.
    static var hasSendGridCredentials: Bool {
        retrieve(key: .sendGridAPIKey) != nil &&
        retrieve(key: .sendGridFromEmail) != nil
    }
}

// MARK: - URL Encoding Helper

private extension String {
    /// Percent-encode for use in form-urlencoded POST bodies.
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "&", with: "%26")
            .replacingOccurrences(of: "=", with: "%3D")
            ?? self
    }
}

import Foundation
import OSLog
import UIKit

/// Handles user reports of objectionable content or behavior.
///
/// ChirpChirp has no servers, so a report does two things: it is recorded
/// locally (so the evidence survives even if the reporter is offline), and
/// a prefilled email to the report address is opened so the report reaches
/// a human. The report address is published on the support site and in
/// Settings.
@MainActor
enum ReportService {

    /// Published contact for abuse reports. Also shown in Settings and on
    /// the website. This is the support mailbox — it is the one address on
    /// the domain that verifiably receives mail.
    static let reportEmail = "support@chirpchirps.com"

    struct Report: Codable {
        let reportedPeerID: String
        let reportedPeerName: String
        /// The reported device's identity fingerprint. This is the part that
        /// makes a report actionable: the routing ID can be regenerated and
        /// the display name is whatever they typed, but the fingerprint is
        /// derived from their identity keypair.
        let reportedFingerprint: String?
        let reason: String
        let messageID: String?
        let messageText: String?
        let channelID: String?
        let reporterPeerID: String
        let createdAt: Date
    }

    private static let logger = Logger(subsystem: Constants.subsystem, category: "ReportService")

    /// Where local report records are appended, one JSON object per line.
    static var reportLogURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("abuse-reports.jsonl")
    }

    /// Record a report locally and open a prefilled abuse email.
    /// Returns `false` only if the local record could not be written.
    @discardableResult
    static func fileReport(
        peerID: String,
        peerName: String,
        fingerprint: String? = nil,
        reason: ReportReason = .other,
        message: MeshTextMessage? = nil,
        includeMessageText: Bool = true,
        reporterPeerID: String
    ) -> Bool {
        let report = makeReport(
            peerID: peerID,
            peerName: peerName,
            fingerprint: fingerprint,
            reason: reason,
            message: message,
            includeMessageText: includeMessageText,
            reporterPeerID: reporterPeerID
        )

        let stored = appendToLog(report)
        openMailComposer(for: report)
        return stored
    }

    /// Assemble the record a report is made of, separately from writing or
    /// mailing it. Whether the reported message's text travels is a decision
    /// with privacy in it, so it is made in one place that can be tested.
    static func makeReport(
        peerID: String,
        peerName: String,
        fingerprint: String?,
        reason: ReportReason,
        message: MeshTextMessage?,
        includeMessageText: Bool,
        reporterPeerID: String
    ) -> Report {
        Report(
            reportedPeerID: peerID,
            reportedPeerName: peerName,
            reportedFingerprint: fingerprint,
            reason: reason.rawValue,
            messageID: message?.id.uuidString,
            // The reporter chooses whether the message text travels. Quoting
            // someone verbatim into an email is a disclosure, and a report
            // about a photo or a transmission has no text worth sending.
            messageText: includeMessageText ? message?.text : nil,
            channelID: message?.channelID,
            reporterPeerID: reporterPeerID,
            createdAt: Date()
        )
    }

    private static func appendToLog(_ report: Report) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(report)
            line.append(0x0A)
            let url = reportLogURL
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
            }
            logger.info("Report recorded for peer \(report.reportedPeerID, privacy: .public)")
            return true
        } catch {
            logger.error("Failed to record report: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func openMailComposer(for report: Report) {
        guard let url = mailComposeURL(for: report) else { return }
        UIApplication.shared.open(url)
    }

    /// The `mailto:` URL a report opens, built separately from opening it so
    /// the contents can be asserted. What the reviewer is promised — the
    /// support address, and an identity fingerprint that makes the report
    /// actionable — is only true if it is actually in these bytes.
    static func mailComposeURL(for report: Report) -> URL? {
        let formatter = ISO8601DateFormatter()
        var body = """
        Reported user: \(report.reportedPeerName)
        Identity fingerprint: \(report.reportedFingerprint ?? "unverified")
        Peer ID: \(report.reportedPeerID)
        Reason: \(report.reason)
        Reported at: \(formatter.string(from: report.createdAt))
        """
        if let messageID = report.messageID {
            body += "\nMessage ID: \(messageID)"
        }
        if let text = report.messageText, !text.isEmpty {
            body += "\nMessage content:\n\(text.prefix(500))"
        }
        body += "\n\nAnything else worth knowing:\n"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ChirpChirp abuse report"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

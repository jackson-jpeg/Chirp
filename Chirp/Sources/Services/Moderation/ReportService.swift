import Foundation
import OSLog
import UIKit

/// Handles user reports of objectionable content or behavior.
///
/// ChirpChirp has no servers, so a report does two things: it is recorded
/// locally (so the evidence survives even if the reporter is offline), and
/// a prefilled email to the abuse address is opened so the report reaches
/// a human. The abuse address is published on the support site and in
/// Settings.
@MainActor
enum ReportService {

    /// Published abuse contact. Also shown in Settings and on the website.
    static let abuseEmail = "abuse@chirpchirps.com"

    struct Report: Codable {
        let reportedPeerID: String
        let reportedPeerName: String
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
        message: MeshTextMessage? = nil,
        reporterPeerID: String
    ) -> Bool {
        let report = Report(
            reportedPeerID: peerID,
            reportedPeerName: peerName,
            messageID: message?.id.uuidString,
            messageText: message?.text,
            channelID: message?.channelID,
            reporterPeerID: reporterPeerID,
            createdAt: Date()
        )

        let stored = appendToLog(report)
        openMailComposer(for: report)
        return stored
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
        let formatter = ISO8601DateFormatter()
        var body = """
        Reported user: \(report.reportedPeerName)
        Peer ID: \(report.reportedPeerID)
        Reported at: \(formatter.string(from: report.createdAt))
        """
        if let messageID = report.messageID {
            body += "\nMessage ID: \(messageID)"
        }
        if let text = report.messageText, !text.isEmpty {
            body += "\nMessage content:\n\(text.prefix(500))"
        }
        body += "\n\nPlease describe what happened:\n"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = abuseEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ChirpChirp abuse report"),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

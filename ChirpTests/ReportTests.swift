import Foundation
import XCTest
@testable import Chirp

/// What the App Review notes and the Terms of Use promise about reporting,
/// asserted against the bytes the app actually produces.
///
/// A report has no server behind it: it is a `mailto:` URL and a local
/// record. So the only thing that makes a report actionable is what is
/// written into that URL, and the one field that survives a rename is the
/// reported device's identity fingerprint.
@MainActor
final class ReportComposeTests: XCTestCase {

    private let peerID = "9F1C7C2E-1B1A-4E2F-9A44-2C0A8D1F5B77"
    private let fingerprint = "a1b2c3d4e5f60718"

    private func message(text: String = "you are dead meat") -> MeshTextMessage {
        MeshTextMessage(
            id: UUID(),
            senderID: peerID,
            senderName: "Falcon",
            channelID: "chan-1",
            text: text,
            timestamp: Date()
        )
    }

    private func report(
        includeMessageText: Bool = true,
        message: MeshTextMessage? = nil,
        fingerprint: String? = "a1b2c3d4e5f60718"
    ) -> ReportService.Report {
        ReportService.makeReport(
            peerID: peerID,
            peerName: "Falcon",
            fingerprint: fingerprint,
            reason: .harassment,
            message: message,
            includeMessageText: includeMessageText,
            reporterPeerID: "11111111-1111-4111-8111-111111111111"
        )
    }

    /// The headline: the compose sheet opens at the published support address
    /// and carries the fingerprint.
    func testComposeURLGoesToSupportAndCarriesTheFingerprint() throws {
        let url = try XCTUnwrap(ReportService.mailComposeURL(for: report()))

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.path, "support@chirpchirps.com")
        XCTAssertEqual(ReportService.reportEmail, "support@chirpchirps.com",
                       "The address in the app must be the one the review notes and the site publish")

        let body = try XCTUnwrap(queryItem("body", in: url))
        XCTAssertTrue(body.contains(fingerprint),
                      "A report without the identity fingerprint cannot be acted on after a rename")
        XCTAssertTrue(body.contains("Identity fingerprint:"))
        XCTAssertTrue(body.contains("harassment"), "The reason the reporter picked must travel")
        XCTAssertTrue(body.contains(peerID))

        let subject = try XCTUnwrap(queryItem("subject", in: url))
        XCTAssertFalse(subject.isEmpty)
    }

    /// A peer this device has never heard a signed beacon from has no
    /// fingerprint to report. That must read as unverified rather than as a
    /// blank line the recipient could mistake for a real identity.
    func testAnUnverifiedPeerIsLabelledRatherThanLeftBlank() throws {
        let url = try XCTUnwrap(ReportService.mailComposeURL(for: report(fingerprint: nil)))
        let body = try XCTUnwrap(queryItem("body", in: url))
        XCTAssertTrue(body.contains("Identity fingerprint: unverified"))
    }

    /// Quoting someone verbatim is a disclosure, so it is the reporter's
    /// choice. Both directions are asserted, because a toggle that is ignored
    /// in either direction is worse than no toggle.
    func testMessageTextTravelsOnlyWhenTheReporterAsksForIt() throws {
        let offending = message()

        let included = report(includeMessageText: true, message: offending)
        XCTAssertEqual(included.messageText, offending.text)
        let withText = try XCTUnwrap(queryItem("body", in: XCTUnwrap(ReportService.mailComposeURL(for: included))))
        XCTAssertTrue(withText.contains(offending.text))

        let excluded = report(includeMessageText: false, message: offending)
        XCTAssertNil(excluded.messageText)
        let withoutText = try XCTUnwrap(queryItem("body", in: XCTUnwrap(ReportService.mailComposeURL(for: excluded))))
        XCTAssertFalse(withoutText.contains(offending.text),
                       "Declining to include the message must actually leave it out")
        XCTAssertEqual(excluded.messageID, offending.id.uuidString,
                       "The message is still identified, so a follow-up can find it")
    }

    /// A very long message must not be pasted wholesale into a URL.
    func testQuotedTextIsTruncated() throws {
        let long = String(repeating: "a", count: 2_000)
        let url = try XCTUnwrap(ReportService.mailComposeURL(
            for: report(includeMessageText: true, message: message(text: long))
        ))
        let body = try XCTUnwrap(queryItem("body", in: url))
        XCTAssertFalse(body.contains(long), "The full 2000 characters must not reach the URL")
        XCTAssertTrue(body.contains(String(repeating: "a", count: 500)))
    }

    private func queryItem(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

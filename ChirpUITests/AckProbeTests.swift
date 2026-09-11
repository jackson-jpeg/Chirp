import XCTest

/// Diagnostic, never part of the orchestrated schedule: sends one live
/// message and prints every deliveryStatus element the accessibility tree
/// exposes once the ACK lands. Exists because rehearsal #7 failed both
/// roles' scoped ACK waits while the messages demonstrably crossed — the
/// open question is what element (and what label) the DELIVERED indicator
/// actually presents, since the sent-state indicator was observed merged
/// into the message row but the delivered state renders a different glyph
/// structure and may not merge the same way. The peer app must be running
/// on the other simulator so a real ACK comes back.
final class AckProbeTests: XCTestCase {

    func testAckProbe() throws {
        let app = Harness.launchApp()
        XCTAssertTrue(Harness.reachChannel(app), "never reached the channel screen")
        Harness.allowSystemAlerts(for: 2)
        XCTAssertTrue(Harness.enterChannelChat(app), "could not enter chat")

        let token = "ACKPROBE-\(Int(Date().timeIntervalSince1970))"
        Harness.sendChatMessage(app, token)

        let unscoped = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["deliveryStatus_delivered", "deliveryStatus_read"])
        ).firstMatch
        let unscopedHit = unscoped.waitForExistence(timeout: 25)
        print("=== PROBE unscoped delivered/read exists: \(unscopedHit)")

        let scopedHit = Harness.waitForDeliveryACK(app, token: token, timeout: 5)
        print("=== PROBE scoped (label CONTAINS token) exists: \(scopedHit)")

        print("=== PROBE deliveryStatus elements ===")
        let all = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "deliveryStatus")
        )
        for i in 0..<min(all.count, 10) {
            let el = all.element(boundBy: i)
            print("  [\(i)] identifier='\(el.identifier)' label='\(el.label)'")
        }
    }
}

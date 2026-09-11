import XCTest

/// Part B of the device smoke test: messaging. Runs after Part A in the same
/// `xcodebuild test` invocation, on both phones, coordinated by the same wall
/// clock (see `Harness`).
///
/// Unlike Part A, the phones CAN observe most of what this part proves — a
/// received message is on the screen, a returned ACK flips the sender's
/// delivery indicator — so this file asserts directly and the orchestrator
/// reads the test verdict out of each device's log. The one thing a phone
/// still cannot see is whether *audio* from a blocked peer stayed silent; that
/// window is judged off-device from B's playback envelope, like all of Part A.
///
/// With exactly two phones in the default channel, one message serves as both
/// the "direct text" and the "channel message": the app's only texting surface
/// is channel chat, and a two-member open channel is the direct case.
/// Locked-channel fan-out (three nodes, invite codes) cannot be scripted
/// across devices that have no side channel to share a runtime-generated
/// invite code — that path is proven by
/// ChirpTests/LoopbackHarnessTests.testLockedChannelMessageReachesInvitedPeers.
final class PartBMessagingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Seconds from T0. Mirrored in lib/devicetest/run.py (SLOTS_B), which
    /// refuses to run on a mismatch — same contract as Part A's Slot.
    private enum Slot {
        static let enterChat: TimeInterval = 115
        static let aSendDirect: TimeInterval = 120
        static let bSendDirect: TimeInterval = 145
        static let bBackground: TimeInterval = 170
        static let aSendStale: TimeInterval = 175
        static let bForeground: TimeInterval = 185
        static let bBlock: TimeInterval = 215
        static let aSendBlocked: TimeInterval = 225
        static let blockedTransmit: TimeInterval = 230
        static let bVerifyBlocked: TimeInterval = 245
        static let flush: TimeInterval = 252
        static let blockedTransmitDuration: TimeInterval = 6
    }

    /// Tokens carry the run's T0 so they are unique per run yet identical on
    /// both roles (both get the same CHIRP_T0). Bare constant strings turned
    /// out to be a false-green machine: message history persists across runs,
    /// so B "received" a token that was really last run's bubble, and A's
    /// long-press on it died on two matching elements (rehearsal #6, where
    /// 'CHIRP-MSG-A2B' existed once from rehearsal #5 and once live).
    private enum Token {
        private static var tag: String { String(Int(Harness.startTime)) }
        static var aToB: String { "CHIRP-MSG-A2B-\(tag)" }
        static var bToA: String { "CHIRP-MSG-B2A-\(tag)" }
        static var stale: String { "CHIRP-MSG-SAF-\(tag)" }
        static var blocked: String { "CHIRP-MSG-BLOCKED-\(tag)" }
    }

    func testPartB() throws {
        let role = Harness.role
        let app = Harness.launchApp()

        XCTAssertTrue(
            Harness.reachChannel(app),
            "[\(role)] never reached a screen with a PTT button — Part B cannot continue"
        )

        // Part A answered the system alerts; a short sweep covers a device
        // that somehow skipped Part A (e.g. a filtered single-part run).
        Harness.allowSystemAlerts(for: 3)

        // Fresh launch means a fresh MC session; peers get until the first
        // send slot to re-find each other. Not asserted here — an undelivered
        // message fails loudly at its own assertion below.
        Harness.waitUntil(Slot.enterChat)
        XCTAssertTrue(
            Harness.enterChannelChat(app),
            "[\(role)] could not navigate Home → Messages → channel → chat input"
        )

        // ── Direct/channel text A -> B, receipt on B, ACK back to A ─────────
        Harness.waitUntil(Slot.aSendDirect)
        if role == "A" {
            Harness.sendChatMessage(app, Token.aToB)
            XCTAssertTrue(
                Harness.waitForDeliveryACK(app, token: Token.aToB, timeout: 22),
                "[A] delivery ACK for '\(Token.aToB)' never came back — indicator stayed at sent"
            )
        } else {
            XCTAssertTrue(
                app.staticTexts[Token.aToB].waitForExistence(timeout: 22),
                "[B] never received '\(Token.aToB)'"
            )
        }

        // ── Direct/channel text B -> A, receipt on A, ACK back to B ─────────
        Harness.waitUntil(Slot.bSendDirect)
        if role == "B" {
            Harness.sendChatMessage(app, Token.bToA)
            XCTAssertTrue(
                Harness.waitForDeliveryACK(app, token: Token.bToA, timeout: 22),
                "[B] delivery ACK for '\(Token.bToA)' never came back — indicator stayed at sent"
            )
        } else {
            XCTAssertTrue(
                app.staticTexts[Token.bToA].waitForExistence(timeout: 22),
                "[A] never received '\(Token.bToA)'"
            )
        }

        // ── Store-and-forward: A sends while B is away ───────────────────────
        //
        // B backgrounds; once MC notices, B is a stale peer and A's send goes
        // to the store-and-forward queue. If MC has not yet dropped the
        // session when A sends, the message crosses live instead — the
        // assertion holds either way, so this slot proves at minimum ordinary
        // delivery and, whenever backgrounding severed the link (the common
        // case), the actual store-and-forward path.
        Harness.waitUntil(Slot.bBackground)
        if role == "B" {
            XCUIDevice.shared.press(.home)
        }

        Harness.waitUntil(Slot.aSendStale)
        if role == "A" {
            Harness.sendChatMessage(app, Token.stale)
        }

        Harness.waitUntil(Slot.bForeground)
        if role == "B" {
            app.activate()
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 10),
                "[B] did not return to the foreground"
            )
            XCTAssertTrue(
                app.staticTexts[Token.stale].waitForExistence(timeout: 25),
                "[B] never received '\(Token.stale)' after returning — store-and-forward failed"
            )
        }

        // ── B blocks A, then A talks and texts into the void ─────────────────
        Harness.waitUntil(Slot.bBlock)
        if role == "B" {
            app.staticTexts[Token.aToB].press(forDuration: 1.2)
            let blockItem = app.buttons["Block User"]
            XCTAssertTrue(
                blockItem.waitForExistence(timeout: 8),
                "[B] context menu on A's message never offered Block User"
            )
            blockItem.tap()
            let confirm = app.buttons["Block"]
            XCTAssertTrue(
                confirm.waitForExistence(timeout: 8),
                "[B] block confirmation dialog never appeared"
            )
            confirm.tap()
            // Blocking hides the sender's existing history — the first
            // observable proof the block list actually engaged.
            XCTAssertTrue(
                Harness.waitGone(app.staticTexts[Token.aToB], timeout: 10),
                "[B] blocked sender's history is still visible"
            )
        }

        Harness.waitUntil(Slot.aSendBlocked)
        if role == "A" {
            Harness.sendChatMessage(app, Token.blocked)
            // Back to talk mode for the blocked PTT transmission.
            Harness.tapModeSegment(app, "Talk")
        }

        Harness.waitUntil(Slot.blockedTransmit)
        if role == "A" {
            Harness.transmit(app, for: Slot.blockedTransmitDuration)
        }

        // ── B: nothing from A may have arrived ───────────────────────────────
        // (Whether the blocked AUDIO stayed silent is judged off-device from
        // B's playback envelope over this window — a phone cannot hear itself
        // not playing.)
        Harness.waitUntil(Slot.bVerifyBlocked)
        if role == "B" {
            XCTAssertFalse(
                app.staticTexts[Token.blocked].exists,
                "[B] received '\(Token.blocked)' from a blocked sender"
            )
        }

        // ── Flush telemetry on both phones, as in Part A ─────────────────────
        Harness.waitUntil(Slot.flush)
        if role == "B" {
            Harness.tapModeSegment(app, "Talk")
        }
        Harness.transmit(app, for: 0.3)
        Thread.sleep(forTimeInterval: 2.0)
    }
}

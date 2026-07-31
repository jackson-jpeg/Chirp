import XCTest

/// Part A of the device smoke test, automated: launch, connect, talk, hear,
/// and survive a background/foreground cycle.
///
/// Both phones run this same test. Role A and role B do different things at
/// each moment, decided by `CHIRP_ROLE`, and stay in step by wall clock (see
/// `Harness`). The orchestrator (`ios devicetest chirp`) starts both, plays the
/// stimulus, collects the telemetry and decides pass or fail.
///
/// NOTE ON WHAT THIS FILE ASSERTS
///
/// Almost nothing. It asserts that the UI was reachable and the button was
/// pressable — the things a test process on the device can actually see. It
/// deliberately does NOT assert anything about audio, because neither phone can
/// observe the other. The audio verdict is computed off-device from both
/// phones' envelopes, which is the only place the question can be answered.
/// A green run here means "the script executed", not "the app works".
final class PartAAudioTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The schedule, in seconds from T0. Kept in one place so the orchestrator's
    /// stimulus playback and this file cannot drift apart silently — the same
    /// numbers appear in lib/devicetest/schedule.json and are checked against
    /// these by the orchestrator before either phone starts.
    private enum Slot {
        static let setupDeadline: TimeInterval = 30
        static let aTransmit: TimeInterval = 35
        static let bTransmit: TimeInterval = 50
        static let background: TimeInterval = 65
        static let foreground: TimeInterval = 75
        static let aTransmitAfterBackground: TimeInterval = 82
        static let flush: TimeInterval = 97
        static let transmitDuration: TimeInterval = 8
    }

    func testPartA() throws {
        let role = Harness.role
        let app = Harness.launchApp()

        XCTAssertTrue(
            Harness.reachChannel(app),
            "[\(role)] never reached a screen with a PTT button — the run cannot continue"
        )

        // Peers are given until the setup deadline to find each other. Not
        // asserted: whether they connected is visible in the telemetry and in
        // whether audio crossed, and failing here would mask the more
        // informative audio result.
        Harness.waitUntil(Slot.setupDeadline)

        // ── A talks, B listens ───────────────────────────────────────────────
        Harness.waitUntil(Slot.aTransmit)
        if role == "A" {
            Harness.transmit(app, for: Slot.transmitDuration)
        }

        // ── B talks, A listens ───────────────────────────────────────────────
        Harness.waitUntil(Slot.bTransmit)
        if role == "B" {
            Harness.transmit(app, for: Slot.transmitDuration)
        }

        // ── Background / foreground cycle on A only (defect #1) ──────────────
        //
        // The question this answers: does leaving the app and coming back
        // permanently kill audio until a force-quit? A background service
        // suspected of switching the audio session off was deleted in e1f38a3
        // and nothing has been near a phone since. B stays in the foreground so
        // that if the next transmission fails, the difference between the two
        // devices localises it.
        Harness.waitUntil(Slot.background)
        if role == "A" {
            XCUIDevice.shared.press(.home)
        }

        Harness.waitUntil(Slot.foreground)
        if role == "A" {
            app.activate()
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 10),
                "[A] did not return to the foreground after backgrounding"
            )
        }

        // ── A talks again — the actual defect #1 measurement ─────────────────
        Harness.waitUntil(Slot.aTransmitAfterBackground)
        if role == "A" {
            Harness.transmit(app, for: Slot.transmitDuration)
        }

        // ── Force a final telemetry flush on both phones ─────────────────────
        //
        // AudioTelemetry writes on every marker, and starting/stopping capture
        // emits one. A brief press is therefore the cheapest way to guarantee
        // everything recorded so far — including audio RECEIVED after this
        // device last spoke — is on disk before the orchestrator collects it.
        Harness.waitUntil(Slot.flush)
        Harness.transmit(app, for: 0.3)
        Thread.sleep(forTimeInterval: 2.0)
    }
}

import XCTest

/// Hold to talk end to end, the way Jackson crashed 2.0.0 (202611172139):
/// in by Welcome's demo link, then hold Talk. With the DEBUG sine mic the
/// microphone tap fires on the simulator, and the app must still be running
/// after the hold and after letting go. `VoiceEngineIsolationTests` (ChirpAppTests)
/// is the deterministic half; this one proves the real press path.
final class HoldToTalkTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    /// Answers whatever iOS asks on the first hold (microphone, Local
    /// Network, notifications, Bluetooth) with its allow button.
    @MainActor
    private func allowSystemAlerts(timeout: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 2) else { return }
            let allow = ["Allow", "OK", "Allow While Using App"].map { alert.buttons[$0] }.first { $0.exists }
            (allow ?? alert.buttons.element(boundBy: alert.buttons.count - 1)).tap()
        }
    }

    @MainActor
    func testHoldingTalkDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarded", "NO", "-ChirpSineMic", "YES"]
        app.launch()

        let link = app.buttons["welcome.demo"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Welcome has no demo link")
        link.tap()
        XCTAssertTrue(app.buttons["talk.leaveDemo"].waitForExistence(timeout: 10), "The demo did not open Talk")

        // DemoFlock's Maya holds the line from 4 s to 8 s; hold before or after.
        let hold = app.descendants(matching: .any)["Hold to talk"]
        XCTAssertTrue(hold.waitForExistence(timeout: 5), "Talk has no hold button")

        // The first hold may only raise the permission questions.
        hold.press(forDuration: 1.0)
        allowSystemAlerts(timeout: 20)
        XCTAssertEqual(app.state, .runningForeground, "The app died on the first hold")

        // Past Maya's turn, then a real 3 s hold with the microphone open.
        Thread.sleep(forTimeInterval: 8)
        app.activate()
        hold.press(forDuration: 3.0)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground, "The app died while holding Talk")
        XCTAssertTrue(app.buttons["talk.leaveDemo"].exists, "Talk is gone after the hold")
        app.terminate()
    }
}

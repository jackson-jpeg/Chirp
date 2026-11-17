import XCTest

/// Demo Mode's way in and way out (App Review 2.1(a), approved by Jackson,
/// Inbox chirp-2-0-demo-entry): Welcome's "Try it with pretend friends" link
/// lands on Talk with the demo banner, and the banner's "Leave demo" goes back.
final class DemoModeTests: XCTestCase {
    private static let emDash = "\u{2014}"

    @MainActor
    func testWelcomeLinkEntersDemoAndBannerLeavesIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Welcome"]
        app.launch()

        let link = app.buttons["welcome.demo"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Welcome has no demo link")
        XCTAssertEqual(link.label, "Try it with pretend friends")
        XCTAssertFalse(link.label.contains(Self.emDash))
        link.tap()

        let banner = app.staticTexts["Demo flock. Nothing leaves this phone."]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "Talk shows no demo banner")
        XCTAssertFalse(banner.label.contains(Self.emDash))

        let leave = app.buttons["talk.leaveDemo"]
        XCTAssertTrue(leave.exists, "The demo banner has no way out")
        XCTAssertEqual(leave.label, "Leave demo")
        leave.tap()

        // Came in from Welcome without making a bird, so it is Welcome again.
        XCTAssertTrue(app.buttons["Start a flock"].waitForExistence(timeout: 10), "Leaving the demo did not go back to Welcome")
        XCTAssertFalse(banner.exists)
        app.terminate()
    }

    @MainActor
    func testDemoLaunchArgumentShowsBanner() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Talk-Listen", "-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["talk.leaveDemo"].waitForExistence(timeout: 10))
        app.buttons["talk.leaveDemo"].tap()
        // Already onboarded: leaving stays on Talk, without the banner.
        XCTAssertTrue(app.buttons["talk.leaveDemo"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["You and settings"].exists, "Leaving the demo left Talk")
        app.terminate()
    }
}

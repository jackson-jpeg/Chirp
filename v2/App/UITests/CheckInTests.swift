import XCTest

/// Check-in's consent (App Review 5.1.1(iv) and 5.1.2(i); site/privacy
/// "Location sharing"): nothing is asked until Share is tapped, our own
/// question comes first and can be declined, and it is asked again every
/// time. Outside a locked flock there is nobody to share with.
///
/// The iOS location prompt itself is not driven here: it follows a yes on our
/// question, which this test never gives.
final class CheckInTests: XCTestCase {
    private static let emDash = "\u{2014}"

    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    func testShareAsksEveryTimeAndCanBeDeclined() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Nearby", "-demo"]   // the demo flock is a locked flock
        app.launch()
        let tab = app.buttons["Nearby"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()

        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Nearby has no Share button")
        XCTAssertTrue(element(app, containing: "Off · asks every time").exists)

        for _ in 0..<2 {
            share.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5), "Share did not ask first")
            XCTAssertTrue(alert.label.hasPrefix("Share where you are with"))
            XCTAssertTrue(alert.buttons["Share for 15 minutes"].exists)
            for text in alert.staticTexts.allElementsBoundByIndex.map(\.label) {
                XCTAssertFalse(text.contains(Self.emDash), "Em dash in: \(text)")
            }
            alert.buttons["Not now"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            // Declined: still off, and the next tap asks again.
            XCTAssertTrue(element(app, containing: "Off · asks every time").exists)
        }
        app.terminate()
    }

    @MainActor
    func testWithoutALockedFlockNothingIsAsked() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Nearby"]
        app.launch()
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        let alert = app.alerts["Share with a locked flock"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Share with no locked flock should explain, not ask")
        XCTAssertFalse(alert.buttons["Share for 15 minutes"].exists)
        alert.buttons["OK"].tap()
        app.terminate()
    }
}

import XCTest

/// Big Flock, the one purchase (Jackson, Inbox chirp-2-0-revenue-shape,
/// "softer"): three colors and one chirp carry a lock and open the sheet;
/// the sheet offers the purchase, Restore and Not now; owning it (`-bigFlock`)
/// takes the locks away. The purchase itself is not driven here.
final class BigFlockUITests: XCTestCase {
    private static let emDash = "\u{2014}"

    @MainActor
    func testLockedColorOpensBigFlockAndNotNowCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "MakeBird"]
        app.launch()

        XCTAssertTrue(app.buttons["Blue"].waitForExistence(timeout: 10), "Blue should be free")
        let teal = app.buttons["Teal, comes with Big Flock"]
        XCTAssertTrue(teal.exists, "Teal should carry a lock")
        XCTAssertTrue(app.buttons["Lilac, comes with Big Flock"].exists)
        XCTAssertTrue(app.buttons["Orange, comes with Big Flock"].exists)
        teal.tap()

        let buy = app.buttons["bigFlock.buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "No Big Flock sheet")
        XCTAssertTrue(buy.label.hasPrefix("Get Big Flock"))
        XCTAssertTrue(app.buttons["bigFlock.restore"].exists, "No Restore")
        for text in app.staticTexts.allElementsBoundByIndex.map(\.label) {
            XCTAssertFalse(text.contains(Self.emDash), "Em dash in: \(text)")
        }
        app.buttons["bigFlock.notNow"].tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 5))
        // Still the free color: a locked one is never put on without buying.
        XCTAssertTrue(app.buttons["Blue"].isSelected)
        app.terminate()
    }

    @MainActor
    func testOwningBigFlockTakesTheLocksAway() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "MakeBird", "-bigFlock"]
        app.launch()
        let teal = app.buttons["Teal"]
        XCTAssertTrue(teal.waitForExistence(timeout: 10), "Teal should be unlocked")
        teal.tap()
        XCTAssertTrue(teal.isSelected)
        XCTAssertFalse(app.buttons["bigFlock.buy"].exists)
        app.terminate()
    }
}

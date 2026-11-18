import XCTest

/// Big Birdhouse, the one purchase (Jackson, Inbox chirp-2-0-revenue-shape,
/// "softer"): three colors and one chirp carry a lock and open the sheet;
/// the sheet offers the purchase, Restore and Not now; owning it (`-bigBirdhouse`)
/// takes the locks away. The purchase itself is not driven here.
final class BigBirdhouseUITests: XCTestCase {
    private static let emDash = "\u{2014}"

    @MainActor
    func testLockedColorOpensBigBirdhouseAndNotNowCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "MakeBird"]
        app.launch()

        XCTAssertTrue(app.buttons["Blue"].waitForExistence(timeout: 10), "Blue should be free")
        let teal = app.buttons["Teal, comes with Big Birdhouse"]
        XCTAssertTrue(teal.exists, "Teal should carry a lock")
        XCTAssertTrue(app.buttons["Lilac, comes with Big Birdhouse"].exists)
        XCTAssertTrue(app.buttons["Orange, comes with Big Birdhouse"].exists)
        teal.tap()

        let buy = app.buttons["bigBirdhouse.buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "No Big Birdhouse sheet")
        XCTAssertTrue(buy.label.hasPrefix("Get Big Birdhouse"))
        XCTAssertTrue(app.buttons["bigBirdhouse.restore"].exists, "No Restore")
        for text in app.staticTexts.allElementsBoundByIndex.map(\.label) {
            XCTAssertFalse(text.contains(Self.emDash), "Em dash in: \(text)")
        }
        app.buttons["bigBirdhouse.notNow"].tap()
        XCTAssertTrue(buy.waitForNonExistence(timeout: 5))
        // Still the free color: a locked one is never put on without buying.
        XCTAssertTrue(app.buttons["Blue"].isSelected)
        app.terminate()
    }

    @MainActor
    func testOwningBigBirdhouseTakesTheLocksAway() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "MakeBird", "-bigBirdhouse"]
        app.launch()
        let teal = app.buttons["Teal"]
        XCTAssertTrue(teal.waitForExistence(timeout: 10), "Teal should be unlocked")
        teal.tap()
        XCTAssertTrue(teal.isSelected)
        XCTAssertFalse(app.buttons["bigBirdhouse.buy"].exists)
        app.terminate()
    }
}

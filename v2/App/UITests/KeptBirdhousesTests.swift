import XCTest

/// Big Birdhouse's kept birdhouses (ChirpCore `SavedBirdhouses`): with it, starting
/// another birdhouse keeps the first, and Talk's birdhouse menu switches back.
/// Free shows none of it. Runs from `-screen Welcome`, so nothing is saved.
final class KeptBirdhousesTests: XCTestCase {
    @MainActor
    private func startCamp(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Welcome"] + extra
        app.launch()
        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let name = app.textFields["birdhouse.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Camp")
        app.buttons["birdhouse.next"].tap()
        app.nameBirdIfEmpty("Sam")
        app.buttons["Hop on the line"].tap()
        XCTAssertTrue(app.buttons["talk.birdhouseMenu"].waitForExistence(timeout: 5), "Did not land on Talk")
        return app
    }

    @MainActor
    func testBigBirdhouseKeepsTheFirstAndSwitchesBack() throws {
        let app = startCamp(["-bigBirdhouse"])
        let menu = app.buttons["talk.birdhouseMenu"]
        menu.tap()
        let another = app.buttons["talk.startAnother"]
        XCTAssertTrue(another.waitForExistence(timeout: 5), "No Start another birdhouse with Big Birdhouse")
        another.tap()

        let name = app.textFields["birdhouse.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Lodge")
        app.buttons["birdhouse.next"].tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let onLodge = NSPredicate(format: "label CONTAINS 'Lodge'")
        expectation(for: onLodge, evaluatedWith: menu)
        waitForExpectations(timeout: 5)

        menu.tap()
        let back = app.buttons["Switch to Camp"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Camp was not kept")
        back.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Camp'"), evaluatedWith: menu)
        waitForExpectations(timeout: 5)

        // And Lodge is kept in its turn.
        menu.tap()
        XCTAssertTrue(app.buttons["Switch to Lodge"].waitForExistence(timeout: 5), "Lodge was not kept")
        app.terminate()
    }

    @MainActor
    func testFreeOffersNoSecondBirdhouse() throws {
        let app = startCamp([])
        app.buttons["talk.birdhouseMenu"].tap()
        XCTAssertTrue(app.buttons["Invite friends"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["talk.startAnother"].exists)
        XCTAssertFalse(app.buttons["talk.switchBirdhouse"].exists)
        app.terminate()
    }
}

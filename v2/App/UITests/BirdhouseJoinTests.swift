import XCTest

/// Starting and joining a birdhouse (Jackson, Inbox chirp-2-0-birdhouse-join): name
/// the birdhouse, or paste a friend's invite, then Make your bird, then Talk.
/// Runs from `-screen Welcome`, so nothing is saved to the Keychain.
final class BirdhouseJoinTests: XCTestCase {
    private static let emDash = "\u{2014}"
    /// A locked birdhouse's code built by hand: bytes 0 to 31 (ID, then key).
    private static let code = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"

    @MainActor
    private func launchOnWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Welcome"]
        app.launch()
        return app
    }

    @MainActor
    private func label(containing s: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
    }

    @MainActor
    func testStartABirdhouseNamesItAndLandsOnTalk() throws {
        let app = launchOnWelcome()
        let start = app.buttons["welcome.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let name = app.textFields["birdhouse.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "No Name your birdhouse screen")
        name.tap()
        name.typeText("Camp")
        app.buttons["birdhouse.next"].tap()

        XCTAssertTrue(label(containing: "Starting Camp", in: app).waitForExistence(timeout: 5), "Make your bird does not name the new birdhouse")
        app.nameBirdIfEmpty("Sam")
        app.buttons["Hop on the line"].tap()

        let menu = app.buttons["talk.birdhouseMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Did not land on Talk")
        XCTAssertTrue(menu.label.contains("Camp"), "Talk is not on the new birdhouse: \(menu.label)")
        menu.tap()
        XCTAssertTrue(app.buttons["Invite friends"].waitForExistence(timeout: 5), "The birdhouse menu has no invite")
        app.terminate()
    }

    @MainActor
    func testPastedInviteJoinsThenMakeYourBird() throws {
        let app = launchOnWelcome()
        app.buttons["welcome.join"].tap()

        let field = app.textFields["birdhouse.invite"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No Join a birdhouse screen")
        field.tap()
        field.typeText("Join my birdhouse: https://chirpchirps.com/join/#k=\(Self.code)&n=Lodge")
        app.buttons["birdhouse.join"].tap()

        XCTAssertTrue(label(containing: "Joining Lodge", in: app).waitForExistence(timeout: 5), "The invite did not open Make your bird")
        app.terminate()
    }

    @MainActor
    func testSomethingElsePastedIsRefusedPlainly() throws {
        let app = launchOnWelcome()
        app.buttons["welcome.join"].tap()
        let field = app.textFields["birdhouse.invite"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("hello")
        let join = app.buttons["birdhouse.join"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: join)
        waitForExpectations(timeout: 5)
        join.tap()

        let refused = app.staticTexts["birdhouse.refused"]
        XCTAssertTrue(refused.waitForExistence(timeout: 5), "Junk was not refused")
        XCTAssertFalse(refused.label.contains(Self.emDash))
        XCTAssertTrue(app.textFields["birdhouse.invite"].exists, "Junk left the join screen")
        app.terminate()
    }
}

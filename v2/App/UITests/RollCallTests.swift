import XCTest

/// Roll call in Demo Mode, the way App Review sees it with one phone: Talk's
/// birdhouse menu opens it, "Ask everyone" goes to the pretend birdhouse, and Maya
/// and Jon answer OK while Priya (out of range, as on the design) does not.
final class RollCallTests: XCTestCase {
    private static let emDash = "\u{2014}"

    @MainActor
    func testAskEveryoneInTheDemoGetsAnswers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "Welcome"]
        app.launch()

        let link = app.buttons["welcome.demo"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.buttons["talk.leaveDemo"].waitForExistence(timeout: 10))

        // Wait until the pretend friends have been heard (presence every 3 s).
        sleep(4)
        app.buttons["talk.birdhouseMenu"].tap()
        let entry = app.buttons["Roll call: everyone OK?"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Talk's birdhouse menu has no roll call")
        entry.tap()

        let ask = app.buttons["rollCall.primary"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()

        let mayaOK = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Maya' AND label CONTAINS 'OK'")).firstMatch
        XCTAssertTrue(mayaOK.waitForExistence(timeout: 5), "Maya did not answer the roll call")
        let priya = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Priya' AND label CONTAINS 'No answer yet'")).firstMatch
        XCTAssertTrue(priya.exists, "Priya should not have answered")

        let help = app.buttons["rollCall.help"]
        XCTAssertEqual(help.label, "I need help")
        help.tap()
        XCTAssertEqual(help.label, "Help asked. Tap to cancel")
        XCTAssertFalse(help.label.contains(Self.emDash))
        help.tap()
        XCTAssertEqual(help.label, "I need help")
        app.terminate()
    }
}

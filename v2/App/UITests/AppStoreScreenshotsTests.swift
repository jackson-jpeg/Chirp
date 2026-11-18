import XCTest

/// App Store screenshots from real use (HARD RULE part 3, docs/NEXT.md).
///
/// A plain launch, never `-screen`: screenshot runs show the design's fixture
/// flock and captions, which would make these mockups. Instead it walks Demo
/// Mode the way App Review does, in by Welcome's "Try it with pretend friends",
/// and keeps whatever the build really shows: Maya talking (DemoFlock's line
/// at 4 s), Chat with your own text heard by the flock, Nearby's Find and Block
/// on a person, the check-in question, roll call answered, and Find's honest
/// fallback (a simulator has no UWB).
///
/// Only runs when APPSTORE_SCREENSHOT_DIR is set, on the 6.9" "Shared iPhone
/// Pro Max A" (1320 x 2868):
/// `ios test chirp --only ChirpUITests/AppStoreScreenshotsTests --env APPSTORE_SCREENSHOT_DIR=<Mac path>`.
/// Each shot is written there as `NN-<name>.png` and attached to the result bundle.
final class AppStoreScreenshotsTests: XCTestCase {
    private static let emDash = "\u{2014}"
    private var dir: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set APPSTORE_SCREENSHOT_DIR to take the App Store screenshots")
        }
        dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        continueAfterFailure = false
    }

    private func any(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func shot(_ name: String) throws {
        // Let transitions and the scene's first-frame animations settle.
        Thread.sleep(forTimeInterval: 1.5)
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try image.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testDemoModeWalkthrough() throws {
        app = XCUIApplication()
        // A real launch on Welcome: `-onboarded NO` overrides the saved flag
        // through UserDefaults' argument domain; nothing else is faked.
        app.launchArguments = ["-onboarded", "NO", "-light"]
        app.launch()

        let link = app.buttons["welcome.demo"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Welcome has no demo link")
        try shot("01-Welcome")
        link.tap()
        let demoStart = Date()
        XCTAssertTrue(app.buttons["talk.leaveDemo"].waitForExistence(timeout: 10), "The demo did not open Talk")

        // 02: Talk while Maya talks (her line holds the floor from 4 s to 8 s).
        XCTAssertTrue(any(containing: "Maya").waitForExistence(timeout: 10))
        let mayaTalking = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'Maya is talking' OR label BEGINSWITH 'Live caption. Maya'")).firstMatch
        XCTAssertTrue(mayaTalking.waitForExistence(timeout: 10), "Maya never started talking")
        try shot("02-Talk-Maya-talking")

        // 03: Chat once Jon and Priya have written (16 s, 28 s), with my own
        // text heard by the pretend flock (real acks through the receive path).
        let wait = 30 - Date().timeIntervalSince(demoStart)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        app.buttons["Chat"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Chat has no message field")
        field.tap()
        field.typeText("On my way up. Save me a seat by the fire!")
        app.buttons["Send"].tap()
        XCTAssertTrue(any(containing: "Heard by").waitForExistence(timeout: 10), "My text got no ticks")
        // Put the keyboard away so the conversation fills the shot.
        app.swipeDown()
        try shot("03-Chat-heard-by")

        // 04: Nearby, a person's Find and Block.
        app.buttons["Nearby"].tap()
        let maya = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Maya'")).firstMatch
        XCTAssertTrue(maya.waitForExistence(timeout: 10), "Maya is not on Nearby")
        maya.tap()
        let block = app.buttons["Block Maya"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "No Block on Maya")
        XCTAssertTrue(app.buttons["Find Maya"].exists)
        try shot("04-Nearby-Find-and-Block")
        app.buttons["Cancel"].tap()

        // 05: The check-in question, asked every time (nothing is shared here).
        let share = app.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Share did not ask first")
        for text in alert.staticTexts.allElementsBoundByIndex.map(\.label) {
            XCTAssertFalse(text.contains(Self.emDash), "Em dash in: \(text)")
        }
        try shot("05-Check-in-asks")
        alert.buttons["Not now"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        // 06: Roll call, asked by me and answered by Maya and Jon.
        app.buttons["Talk"].tap()
        app.buttons["talk.flockMenu"].tap()
        let entry = app.buttons["Roll call: everyone OK?"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Talk's flock menu has no roll call")
        entry.tap()
        let ask = app.buttons["rollCall.primary"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        ask.tap()
        let mayaOK = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Maya' AND label CONTAINS 'OK'")).firstMatch
        XCTAssertTrue(mayaOK.waitForExistence(timeout: 5), "Maya did not answer the roll call")
        try shot("06-Roll-call")
        app.buttons["Close roll call"].tap()

        // 07: Find, as a simulator really shows it (no UWB: the fallback).
        app.buttons["Nearby"].tap()
        XCTAssertTrue(maya.waitForExistence(timeout: 10))
        maya.tap()
        let find = app.buttons["Find Maya"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        XCTAssertTrue(app.buttons["Stop finding"].waitForExistence(timeout: 10), "Find did not open")
        try shot("07-Find")
        app.buttons["Stop finding"].tap()

        app.terminate()
    }
}

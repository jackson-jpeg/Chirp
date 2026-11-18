import XCTest

/// The review screenshot App Store Connect asks for on the Big Birdhouse
/// purchase (6836146019): the real sheet, opened the way a person opens it
/// (a locked color in Make your bird), with the price the App Store gives
/// (the local StoreKit file on the simulator). Only runs when
/// IAP_SCREENSHOT_DIR is set:
/// `ios test chirp --only ChirpUITests/BigBirdhouseReviewShotTests --env IAP_SCREENSHOT_DIR=<Mac path>`.
final class BigBirdhouseReviewShotTests: XCTestCase {
    @MainActor
    func testTheBigBirdhouseSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["IAP_SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set IAP_SCREENSHOT_DIR to take the purchase's review screenshot")
        }
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let app = XCUIApplication()
        app.launchArguments = ["-screen", "MakeBird"]
        app.launch()
        let teal = app.buttons["Teal, comes with Big Birdhouse"]
        XCTAssertTrue(teal.waitForExistence(timeout: 10), "Teal should carry a lock")
        teal.tap()

        let buy = app.buttons["bigBirdhouse.buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "No Big Birdhouse sheet")
        // Wait for the price, so the shot shows what a person sees.
        expectation(for: NSPredicate(format: "label CONTAINS '$'"), evaluatedWith: buy)
        waitForExpectations(timeout: 15)

        Thread.sleep(forTimeInterval: 1.5)
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = "big-birdhouse-review"
        attachment.lifetime = .keepAlways
        add(attachment)
        try image.pngRepresentation.write(to: dir.appendingPathComponent("big-birdhouse-review.png"))
        app.terminate()
    }
}

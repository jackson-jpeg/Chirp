import XCTest

final class ChirpScreenshots: XCTestCase {

    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["-skipOnboarding"]
        app.launch()
    }

    func testCaptureScreenshots() {
        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? "/tmp"
        sleep(2)

        // 1. PTT Home (Talk tab - default)
        saveScreenshot(name: "01-ptt-home", dir: dir)

        // 2. Channels tab
        app.buttons["Channels"].tap()
        sleep(1)
        saveScreenshot(name: "02-channels", dir: dir)

        // 3. Babel tab
        app.buttons["Babel"].tap()
        sleep(1)
        saveScreenshot(name: "03-babel", dir: dir)

        // 4. Protect tab
        app.buttons["Protect"].tap()
        sleep(1)
        saveScreenshot(name: "04-protect", dir: dir)

        // 5. Settings tab
        app.buttons["Settings"].tap()
        sleep(1)
        saveScreenshot(name: "05-settings", dir: dir)
    }

    private func saveScreenshot(name: String, dir: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

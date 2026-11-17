import XCTest

/// Build-vs-design screenshots: launches the app on each screen of the
/// approved design (`-screen <Name>`, plus `-dark`) and keeps a screenshot.
///
/// Run with `ios test chirp --only ChirpUITests --env SCREENSHOT_DIR=<Mac path>`.
/// Each shot is attached to the result bundle and, when SCREENSHOT_DIR is set,
/// also written there as `<Name>-light-build.png` / `<Name>-dark-build.png`
/// (the simulator's test runner can write to the Mac's file system).
final class BuildVsDesignTests: XCTestCase {
    static let screens = [
        "Welcome", "MakeBird", "Talk-Listen", "Talk-Hold", "Chat",
        "Nearby", "Find", "Meetup", "RollCall", "CatchUp",
    ]

    @MainActor
    func testEveryScreenLightAndDark() throws {
        continueAfterFailure = true
        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let dir { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

        let app = XCUIApplication()
        for name in Self.screens {
            for mode in ["light", "dark"] {
                app.terminate()
                app.launchArguments = ["-screen", name] + (mode == "dark" ? ["-dark"] : [])
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(name) \(mode) did not start")
                // Let first-frame animations (ripples, the bird's entrance) settle.
                Thread.sleep(forTimeInterval: 2.5)

                let shot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "\(name)-\(mode)-build"
                attachment.lifetime = .keepAlways
                add(attachment)
                if let dir {
                    try shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name)-\(mode)-build.png"))
                }
            }
        }
        app.terminate()
    }
}

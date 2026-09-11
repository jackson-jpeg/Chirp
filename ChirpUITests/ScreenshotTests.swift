import XCTest

/// App Store screenshot capture. Simulator only, never in the device
/// schedule: it launches the app with `--screenshot-seed` (a DEBUG-only
/// launch argument, see ScreenshotSeed.swift) and photographs six real
/// screens. Raw PNGs land in /tmp/chirp-shots on the host Mac and are
/// duplicated as attachments in the xcresult as a fallback.
///
/// Run via screenshots/capture.sh, which boots the simulator, pins the
/// status bar to 9:41 / full battery, grants microphone + location, and
/// sets the simulated GPS fix the map shot depends on.
final class ScreenshotTests: XCTestCase {

    private static let outputDir = "/tmp/chirp-shots"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(
            atPath: Self.outputDir, withIntermediateDirectories: true)
    }

    // MARK: - Shots

    func test01TalkTransmitting() {
        let app = launchSeeded(transmit: true)
        // The seed starts a real transmission 4s after launch and holds it
        // for 60s; wait past the start plus the ring animation ramp.
        Thread.sleep(forTimeInterval: 9)
        capture(app, "01-talk")
    }

    func test02MeshPeers() {
        let app = launchSeeded()
        // Let the peer bubbles and signal ring settle.
        Thread.sleep(forTimeInterval: 5)
        capture(app, "02-mesh")
    }

    func test03ChannelChat() {
        // "--screenshot-chat" makes ChannelView default to chat mode, so no
        // hierarchy query ever runs inside ChannelView: its continuously
        // animating background stalls XCUITest snapshots until they time out
        // ("Failed to get matching snapshots"), observed on the first capture
        // run. All queries stay on the home/channel-list screens.
        let app = launchSeeded(extraArgs: ["--screenshot-chat"])
        XCTAssertTrue(openBasecamp(app), "never reached the Basecamp card")
        Thread.sleep(forTimeInterval: 4)
        capture(app, "03-messages")
    }

    func test04VoiceMessages() {
        let app = launchSeeded()
        let link = app.buttons["Voice Messages"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "voice messages toolbar link missing")
        link.tap()
        Thread.sleep(forTimeInterval: 2)
        capture(app, "04-voice")
    }

    func test05Map() {
        let app = launchSeeded()
        tapTab(app, "Map")
        // Map tiles stream in; give them time to render fully.
        Thread.sleep(forTimeInterval: 8)
        capture(app, "05-map")
    }

    func test06PrivacySettings() {
        let app = launchSeeded()
        let settings = Harness.element(app, "settingsButton")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "settings button missing")
        settings.tap()

        // Scroll until the Privacy & Security section fills the frame.
        let anchor = app.staticTexts["Zero Servers"]
        for _ in 0..<6 where !(anchor.exists && anchor.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(anchor.exists, "never scrolled to the Privacy & Security section")
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "06-privacy")
    }

    // MARK: - Plumbing

    private func launchSeeded(transmit: Bool = false, extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--screenshot-seed",
            "-com.chirpchirp.onboardingComplete", "YES",
            "-com.chirpchirp.callsign", "Falcon-58",
        ]
        if transmit {
            app.launchArguments.append("--screenshot-transmit")
        }
        app.launchArguments.append(contentsOf: extraArgs)
        app.launch()
        // Notification / local-network / mic alerts must never sit above a
        // capture; sweep them the way the device harness does.
        Harness.allowSystemAlerts(for: 3)
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let url = URL(fileURLWithPath: Self.outputDir)
            .appendingPathComponent("\(name).png")
        do {
            try shot.pngRepresentation.write(to: url)
        } catch {
            // Attachment in the xcresult is the fallback path.
            NSLog("[Screenshots] direct write failed (%@); use the xcresult", "\(error)")
        }
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.buttons[label]
        if tab.waitForExistence(timeout: 10) {
            tab.tap()
        } else {
            app.staticTexts[label].firstMatch.tap()
        }
    }

    /// Messages tab → tap the seeded "Basecamp" card. Same verified
    /// tap-escalation as Harness.enterChannelChat, but pinned to Basecamp:
    /// this simulator carries channels left behind by earlier harness runs,
    /// and only Basecamp holds the seeded conversation. Deliberately ends at
    /// the card tap — ChannelView itself is a no-query zone (see test03).
    private func openBasecamp(_ app: XCUIApplication) -> Bool {
        let messagesTab = app.buttons["Messages"]
        guard messagesTab.waitForExistence(timeout: 10) else { return false }

        var switched = false
        let fab = app.buttons["New Channel"]
        for attempt in 0..<4 where !switched {
            Harness.allowSystemAlerts(for: 1)
            switch attempt {
            case 0: messagesTab.tap()
            case 1: messagesTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            case 2: app.staticTexts["Messages"].firstMatch.tap()
            default: messagesTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            switched = Harness.element(app, AXID.channelCard).waitForExistence(timeout: 4) || fab.exists
        }
        guard switched else { return false }

        let card = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label BEGINSWITH %@",
                AXID.channelCard, "Basecamp"
            )
        ).firstMatch
        guard card.waitForExistence(timeout: 5) else { return false }
        card.tap()
        return true
    }
}

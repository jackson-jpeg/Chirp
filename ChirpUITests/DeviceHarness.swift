import XCTest

/// Shared machinery for the two-phone tests.
///
/// COORDINATION, AND WHY IT IS DONE WITH A CLOCK
///
/// Two phones must take turns: one talks while the other listens, then they
/// swap. The two test processes cannot talk to each other — they are separate
/// `xcodebuild test` runs on separate hardware, and the only channel between
/// them is the mesh, which is the thing under test. Coordinating over it would
/// mean the harness passes when the app works and hangs when it does not,
/// which is not a test.
///
/// So the schedule is absolute wall-clock time, handed to both runs by the
/// orchestrator before either starts. Both phones are NTP-synced; the slots are
/// seconds long, so residual skew is irrelevant. Each role knows what it should
/// be doing at any moment without needing to be told.
///
/// This also means a phone that crashes does not hang its partner — the
/// partner simply finds nothing at the far end and the analysis says so.
enum Harness {

    /// Absolute unix time the schedule starts, passed in by the orchestrator.
    static var startTime: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["CHIRP_T0"],
              let value = TimeInterval(raw) else {
            // Not a `try?`-style swallow: without a schedule the run is
            // meaningless and must not silently proceed with a guess.
            fatalError("CHIRP_T0 not set — the orchestrator must supply the schedule origin")
        }
        return value
    }

    static var role: String {
        ProcessInfo.processInfo.environment["CHIRP_ROLE"] ?? "A"
    }

    /// Block until `startTime + offset`. Returns immediately if that moment has
    /// already passed, which is itself worth knowing — the caller reports it.
    @discardableResult
    static func waitUntil(_ offset: TimeInterval) -> Bool {
        let target = startTime + offset
        let remaining = target - Date().timeIntervalSince1970
        guard remaining > 0 else { return false }
        Thread.sleep(forTimeInterval: remaining)
        return true
    }

    static func elapsed() -> TimeInterval {
        Date().timeIntervalSince1970 - startTime
    }

    /// Launch the app with telemetry recording switched on.
    ///
    /// `-ChirpAudioTelemetry YES` lands in UserDefaults' argument domain, which
    /// is how AudioTelemetry decides whether to exist at runtime. Nothing else
    /// sets it, so no user build ever records anything.
    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ChirpAudioTelemetry", "YES",
            "-ChirpRole", role,
            // Argument-domain default: start in the state every real run has —
            // an onboarded app. UserDefaults reads NSArgumentDomain before the
            // persistent domain, so nothing is written to disk and a manual
            // launch still onboards normally. Without this, a fresh install
            // stalls on page 0 of the five-page onboarding flow, whose gated
            // Continue/callsign/rules walk this harness deliberately does not
            // script — onboarding UI is not what these tests measure.
            "-com.chirpchirp.onboardingComplete", "YES",
        ]
        app.launch()
        return app
    }

    /// Answer any system permission alert (notifications, location, local
    /// network) affirmatively. These arrive shortly after launch and sit above
    /// the app; local network in particular blocks peer discovery until
    /// answered, so the harness sweeps them before the schedule starts.
    /// Runs for the full duration even when no alert shows — alerts can
    /// arrive seconds after the services that trigger them start.
    static func allowSystemAlerts(for duration: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let affirmative = ["Allow While Using App", "Allow Once", "Allow", "OK", "Continue"]
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            var tapped = false
            for label in affirmative where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                tapped = true
                break
            }
            if !tapped {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    /// Look an identifier up across ALL element types. The app's controls do
    /// not map to `.button` the way the identifiers suggest: the channel card
    /// carries `.isButton` (so XCUITest files it under buttons, not
    /// otherElements), while the PTT control carries `.startsMediaSession`
    /// only (so it is NOT under buttons). Typed queries here failed both ways
    /// at once — every run died as "never reached a screen with a PTT button"
    /// while sitting on the home screen.
    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Get to a screen with a PTT button, from whatever state the app was left
    /// in. Deliberately tolerant: the harness must not fail because a device
    /// happened to still be showing a settings sheet from a previous run.
    static func reachChannel(_ app: XCUIApplication, timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element(app, AXID.pttButton).exists { return true }

            // Onboarding, if this device has never run the app.
            if element(app, AXID.getStartedButton).exists {
                element(app, AXID.getStartedButton).tap()
                continue
            }
            // Home screen — open the first channel.
            if element(app, AXID.channelCard).exists {
                element(app, AXID.channelCard).tap()
                continue
            }
            if element(app, AXID.createFirstChannel).exists {
                element(app, AXID.createFirstChannel).tap()
                continue
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element(app, AXID.pttButton).exists
    }

    /// Press and hold the real PTT button for `duration`.
    ///
    /// Uses the actual control, not a test-only entry point into PTTEngine:
    /// the gesture recogniser, the view state and the floor request are all
    /// part of what can break, and a harness that bypassed them would go green
    /// while the button did nothing.
    static func transmit(_ app: XCUIApplication, for duration: TimeInterval) {
        element(app, AXID.pttButton).press(forDuration: duration)
    }
}

/// Mirrors Chirp/Sources/Utilities/AccessibilityIdentifiers.swift.
///
/// Duplicated rather than shared because the UI-test bundle is a separate
/// module from the app and cannot import it. Kept to the handful the harness
/// actually drives, so the duplication stays small enough to notice when it
/// drifts — and a drifted identifier fails loudly here as "element not found",
/// never silently.
enum AXID {
    static let pttButton = "pttButton"
    static let channelCard = "channelCard"
    static let createFirstChannel = "createFirstChannel"
    static let getStartedButton = "getStartedButton"
    static let peerCountPill = "peerCountPill"
}

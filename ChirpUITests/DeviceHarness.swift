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
        // Simulator role of the phone+sim run: the orchestrator sets this so
        // the app substitutes a deterministic pulsed sine for the sim's host
        // microphone (see AudioEngine.sineMicEnabled). Never set for phones.
        if ProcessInfo.processInfo.environment["CHIRP_SINE_MIC"] == "1" {
            app.launchArguments += ["-ChirpSineMic", "YES"]
        }
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
            // Scoped to alerts: on a real phone springboard also exposes
            // non-alert buttons (a stashed picture-in-picture player's
            // controls, live-observed), which an unscoped label match could
            // hit. And the alert can vanish between resolution and tap —
            // XCTest's own interruption handling races this sweep for the
            // same alert; that stale tap aborted an entire phone run. A lost
            // race must cost one pass of this loop, never the test.
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                for label in affirmative {
                    let button = alert.buttons[label].firstMatch
                    guard button.exists, button.isHittable else { continue }
                    let options = XCTExpectedFailure.Options()
                    options.isStrict = false
                    XCTExpectFailure(
                        "alert dismissed mid-tap by the system's own handler",
                        options: options
                    ) {
                        button.tap()
                    }
                    tapped = true
                    break
                }
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

    /// Navigate from wherever the app launched to the active channel's chat.
    ///
    /// The app opens onto HomeView's Talk tab, which has its own PTT button —
    /// that surface is where Part A runs, and why `reachChannel` succeeds
    /// without ever leaving home. Chat, though, lives one level deeper, inside
    /// ChannelView: bottom-nav "Messages" → the channel card → chat mode.
    /// Both roles must land in the SAME room. Neither "currently active" nor
    /// a channel's display name identifies one: active is whatever a previous
    /// run left behind (the two sims were observed active on different
    /// channels), and names collide — one sim carried TWO locked channels
    /// both called "Private Channel", and picking by that name sent role A's
    /// messages into a room role B had no key for. The only channel with a
    /// fixed, identical ID on every install is "General" (the migration pins
    /// it to 00000000-…-0001), so that is the deterministic pick; the active
    /// card and then any lone card are fallbacks for exotic state.
    static func enterChannelChat(_ app: XCUIApplication) -> Bool {
        let messagesTab = app.buttons["Messages"]
        guard messagesTab.waitForExistence(timeout: 10) else { return false }

        // A plain tap on this tab button has been observed to land without
        // any effect (hierarchy identical two seconds later), so the switch
        // is verified — a channel card or the messages-tab-only "New Channel"
        // FAB must appear — and the tap escalates through different points of
        // the control until it does. Each attempt is preceded by an alert
        // sweep: the Part B relaunch restarts the Multipeer session, which
        // can re-raise the local-network permission alert AFTER the post-
        // launch sweep ended, and an alert above the app eats every tap
        // while leaving the hierarchy query results looking normal.
        var switched = false
        let fab = app.buttons["New Channel"]
        for attempt in 0..<4 where !switched {
            allowSystemAlerts(for: 1)
            switch attempt {
            case 0: messagesTab.tap()
            case 1: messagesTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            case 2: app.staticTexts["Messages"].firstMatch.tap()
            default: messagesTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            switched = element(app, AXID.channelCard).waitForExistence(timeout: 4) || fab.exists
        }
        guard switched else {
            NSLog("[Harness] Messages tab never switched. Hierarchy:\n%@", app.debugDescription)
            return false
        }

        let sharedCard = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label BEGINSWITH %@",
                AXID.channelCard, "General"
            )
        ).firstMatch
        let activeCard = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                AXID.channelCard, "currently active"
            )
        ).firstMatch
        let card: XCUIElement
        if sharedCard.waitForExistence(timeout: 4) {
            card = sharedCard
        } else if activeCard.waitForExistence(timeout: 2) {
            card = activeCard
        } else {
            card = element(app, AXID.channelCard)
        }
        guard card.waitForExistence(timeout: 5) else { return false }
        card.tap()

        // Inside ChannelView, talk mode by default. Either the chat quick
        // action or the mode picker's Chat segment switches over.
        let quick = element(app, AXID.quickActionChat)
        if quick.waitForExistence(timeout: 8) {
            quick.tap()
        } else {
            tapModeSegment(app, "Chat")
        }
        return element(app, AXID.chatInputField).waitForExistence(timeout: 10)
    }

    /// Wait for ONE outgoing message's ACK to land: the delivery indicator at
    /// "delivered" — or already at "read", which a fast read receipt can
    /// upgrade it to before this poll ever sees the intermediate state. Both
    /// prove the ACK round-trip.
    ///
    /// Scoped to the message carrying `token`, because history persists
    /// across runs — an unscoped query returns true instantly off any old
    /// delivered message, which would let this pass with the mesh unplugged.
    ///
    /// The element that carries BOTH the status identifier and the message
    /// text is the merged row ("You: <text>") — and for delivered/read its
    /// identifier is DOUBLED: the indicator is two checkmark Images, and
    /// SwiftUI's merge concatenates their identifiers, producing
    /// "deliveryStatus_delivered-deliveryStatus_delivered" (AckProbeTests,
    /// live-observed). Hence BEGINSWITH, never equality: an equality match
    /// here is structurally impossible and failed rehearsal #7 on both
    /// roles while the ACKs had actually arrived.
    static func waitForDeliveryACK(_ app: XCUIApplication, token: String, timeout: TimeInterval) -> Bool {
        let match = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "(identifier BEGINSWITH %@ OR identifier BEGINSWITH %@) AND label CONTAINS %@",
                "deliveryStatus_delivered", "deliveryStatus_read", token
            )
        ).firstMatch
        return match.waitForExistence(timeout: timeout)
    }

    /// Type `text` into the chat input and send it. Assumes chat mode is
    /// already showing (Part B enters it once, at its first slot).
    static func sendChatMessage(_ app: XCUIApplication, _ text: String) {
        let field = element(app, AXID.chatInputField)
        field.tap()
        field.typeText(text)
        element(app, AXID.chatSendButton).tap()
    }

    /// Wait until `el` stops existing. XCUITest has waitForExistence but no
    /// inverse, so this polls the same way reachChannel does.
    static func waitGone(_ el: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !el.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return !el.exists
    }

    /// Tap a segment of the Talk/Chat mode picker by its visible name. The
    /// segments carry accessibility labels of the form "Talk mode" /
    /// "Chat mode, selected" rather than identifiers.
    static func tapModeSegment(_ app: XCUIApplication, _ name: String) {
        let match = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "\(name) mode")
        ).firstMatch
        if match.waitForExistence(timeout: 5) {
            match.tap()
        }
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
    static let quickActionChat = "quickActionChat"
    static let chatInputField = "chatInputField"
    static let chatSendButton = "chatSendButton"
    static let statusPill = "statusPill"

    // Review-compliance run (ReviewComplianceTests).
    static let homeView = "homeView"
    static let settingsButton = "settingsButton"
    static let onboardingView = "onboardingView"
    static let onboardingContinue = "onboardingContinue"
    static let onboardingMicPage = "onboardingMicPage"
    static let micDeniedNotice = "micDeniedNotice"
    static let locationDeniedNotice = "locationDeniedNotice"
    static let openSettingsButton = "openSettingsButton"
    static let locationConsentSheet = "locationConsentSheet"
    static let locationShareButton = "locationShareButton"
    static let locationDontShareButton = "locationDontShareButton"
    static let locationAboutLink = "locationAboutLink"
    static let locationAboutSettingsRow = "locationAboutSettingsRow"
    static let peerActionSheet = "peerActionSheet"
    static let peerSheetBlockButton = "peerSheetBlockButton"
    static let peerSheetReportButton = "peerSheetReportButton"
    static let blockedUsersRow = "blockedUsersRow"
    static let messageFilterToggle = "messageFilterToggle"
    static let hiddenMessageDisclosure = "hiddenMessageDisclosure"
    static let messageBlockOrReport = "messageBlockOrReport"
    static let mapCheckInButton = "mapCheckInButton"
    static let mapStopSharingButton = "mapStopSharingButton"
    static let mapSharingIndicator = "mapSharingIndicator"
    static let demoModeToggle = "demoModeToggle"
    static let tryDemoModeButton = "tryDemoModeButton"
    static let demoBadge = "demoBadge"
    static let demoExitButton = "demoExitButton"
    static let meshStatusLabel = "meshStatusLabel"
    static let peerCountBadge = "peerCountBadge"
    static let voiceMessagePlayButton = "voiceMessagePlayButton"
    static let voiceNotePlayButton = "voiceNotePlayButton"
    static let mapPeerPin = "mapPeerPin"
    static let peerMap = "peerMap"
}

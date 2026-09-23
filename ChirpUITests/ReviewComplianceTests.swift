import XCTest

/// The two App Review findings, driven through the real UI.
///
/// 5.1.1(iv): a screen shown before a system permission prompt may offer
/// exactly one action, and that action must produce the prompt. These tests
/// assert on the *buttons that exist* rather than on the one we intend to tap,
/// because the violation Apple found was an extra way out, not a missing one.
///
/// 2.1(a): the reviewer had no second device, so every feature has to be
/// reachable on one. Demo Mode is driven end to end here — peers, history,
/// voice messages, a push-to-talk reply, map pins — and switched off again.
///
/// Every test assumes a FRESH install with permissions reset; the runner
/// (scripts/testing/run-review-tests.sh) uninstalls and resets before each.
final class ReviewComplianceTests: XCTestCase {

    /// Anything that would let someone leave a pre-prompt screen without the
    /// system prompt appearing. "Continue" and "Next" are the only allowed
    /// labels on such a screen.
    static let forbiddenExits = [
        "Skip", "Not Now", "Later", "Maybe Later", "Maybe", "Done", "Close",
        "Cancel", "Dismiss", "No Thanks", "Keep It Off", "Enable Microphone",
        "Allow Microphone", "Enable Location", "Enable"
    ]

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Launch

    private func launch(onboarded: Bool, demo: Bool? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ChirpUITest", "YES"]
        if onboarded {
            app.launchArguments += ["-com.chirpchirp.onboardingComplete", "YES"]
        }
        if let demo {
            app.launchArguments += ["-com.chirpchirp.demoMode", demo ? "YES" : "NO"]
        }
        app.launch()
        self.app = app
        if onboarded { sweepIncidentalAlerts() }
        return app
    }

    // MARK: - Helpers

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Wait for the system permission alert.
    ///
    /// Usually it belongs to springboard rather than the app, so `app.alerts`
    /// alone misses it. On iPad, where this iPhone-only app runs in
    /// compatibility mode, it was observed the other way round, so both are
    /// polled and whichever appears is returned.
    @discardableResult
    private func waitForSystemAlert(timeout: TimeInterval = 25) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for candidate in [springboard.alerts.firstMatch, app.alerts.firstMatch] where candidate.exists {
                return candidate
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// Any permission alert on screen, from either owner.
    private var anySystemAlert: XCUIElement? {
        for candidate in [springboard.alerts.firstMatch, app.alerts.firstMatch] where candidate.exists {
            return candidate
        }
        return nil
    }

    private func answerSystemAlert(_ alert: XCUIElement, allow: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let labels = allow
            ? ["Allow While Using App", "Allow", "Allow Once", "OK"]
            : ["Don't Allow", "Don’t Allow", "Don't allow"]
        for label in labels {
            let button = alert.buttons[label].firstMatch
            if button.exists {
                button.tap()
                return
            }
        }
        XCTFail("no \(allow ? "affirmative" : "declining") button on the system alert: \(alert.debugDescription)",
                file: file, line: line)
    }

    /// Answer the permission alerts that are not what a test is about: the
    /// notification prompt fires at launch on an onboarded install, and
    /// MultipeerConnectivity can raise the local-network one. Both sit above
    /// the app and eat taps. Microphone and location alerts are deliberately
    /// left alone — they are the subject of these tests.
    private func sweepIncidentalAlerts(seconds: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let alert = anySystemAlert {
                let text = alert.staticTexts.allElementsBoundByIndex
                    .map { $0.label }.joined(separator: " ").lowercased()
                if text.contains("microphone") || text.contains("location") { return }
                var tapped = false
                for label in ["Allow", "OK", "Don't Allow"] {
                    let button = alert.buttons[label].firstMatch
                    if button.exists, button.isHittable {
                        button.tap()
                        tapped = true
                        break
                    }
                }
                if tapped { continue }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Every button label currently on screen.
    private func visibleButtonLabels() -> [String] {
        app.buttons.allElementsBoundByIndex
            .filter { $0.exists }
            .map { $0.label }
    }

    /// The heart of 5.1.1(iv): this screen may not offer a way out.
    private func assertNoExits(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let labels = visibleButtonLabels()
        for forbidden in Self.forbiddenExits {
            XCTAssertFalse(
                labels.contains { $0.caseInsensitiveCompare(forbidden) == .orderedSame },
                "\(screen) offers \"\(forbidden)\" — a pre-prompt screen may only lead to the prompt. Buttons: \(labels)",
                file: file, line: line
            )
        }
    }

    /// Leave the current pushed screen. ChannelView hides the system back
    /// button and supplies its own ("Back"); everything else uses the
    /// navigation bar's leading button, whose label is the previous title.
    private func goBack() {
        let named = app.buttons["Back"].firstMatch
        if named.exists, named.isHittable {
            named.tap()
            return
        }
        let bar = app.navigationBars.buttons.element(boundBy: 0)
        if bar.exists { bar.tap() }
    }

    /// Go back until `condition` holds. Same lost-tap problem as everywhere
    /// else in this file; a back tap that does nothing leaves the next
    /// assertion failing about the wrong screen.
    @discardableResult
    private func goBack(until condition: () -> Bool, tries: Int = 3) -> Bool {
        for _ in 0..<tries {
            if condition() { return true }
            goBack()
            if waitUntil(timeout: 8, condition) { return true }
        }
        return condition()
    }

    /// The home screen is up.
    ///
    /// Identified by the talk button and the mesh status line rather than by
    /// an identifier on the screen's root: SwiftUI propagates a container
    /// identifier to every descendant, so tagging the root would overwrite
    /// the identifier of every control inside it (live-observed: every
    /// element on the home screen came back as "homeView").
    private func waitForHome(timeout: TimeInterval = 30) -> Bool {
        waitUntil(timeout: timeout) {
            // Not the talk button: ChannelView has one too, so waiting on it
            // reported "home" while the test was still inside a channel, and
            // the next tab tap then had no tab bar to hit. The mesh status
            // line and the bottom tab bar exist only on the home screen.
            el(AXID.meshStatusLabel).exists
                || (app.buttons["Map"].exists && app.buttons["Messages"].exists)
        }
    }

    /// The inline notice for a permission the user declined: its title and the
    /// one action that can change the answer.
    private func permissionNoticeIsUp(_ title: String, timeout: TimeInterval = 20) -> Bool {
        waitUntil(timeout: timeout) {
            app.staticTexts[title].firstMatch.exists && el(AXID.openSettingsButton).exists
        }
    }

    /// Switch bottom-nav tab and prove it switched.
    ///
    /// A plain tap on these has been observed to land with no effect (the same
    /// defect DeviceHarness documents for the Messages tab), so the tap is
    /// verified and retried at different points of the control.
    @discardableResult
    private func switchToTab(_ name: String, until condition: () -> Bool, timeout: TimeInterval = 8) -> Bool {
        if condition() { return true }
        let tab = app.buttons[name].firstMatch
        guard tab.waitForExistence(timeout: 15) else { return false }
        for attempt in 0..<4 {
            switch attempt {
            case 0: tab.tap()
            case 1: tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            case 2: app.staticTexts[name].firstMatch.tap()
            default: tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            }
            if waitUntil(timeout: timeout, condition) { return true }
        }
        return condition()
    }

    /// Messages tab, then the demo General channel, then chat mode.
    ///
    /// Written here rather than reused from DeviceHarness so a failure can
    /// attach the hierarchy: on iPad these taps land inconsistently, and
    /// "could not reach chat" says nothing about which step lost the tap.
    private func enterChannelChat() -> Bool {
        guard switchToTab("Messages", until: { self.el(AXID.channelCard).exists }, timeout: 12) else {
            attachHierarchy("messages-tab-never-opened")
            return false
        }
        // Re-queried on every attempt rather than held: the channel list
        // rebuilds as peers appear, and a reference taken before that goes
        // stale, which surfaces as "Failed to tap channelCard" rather than as
        // anything to do with the test.
        func channelCard() -> XCUIElement {
            let general = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", AXID.channelCard, "General")
            ).firstMatch
            return general.exists ? general : el(AXID.channelCard)
        }
        guard channelCard().waitForExistence(timeout: 15) else {
            attachHierarchy("no-channel-card")
            return false
        }
        for attempt in 0..<3 {
            if el(AXID.chatInputField).exists { return true }
            let card = channelCard()
            if card.exists, (attempt > 0 || !el(AXID.quickActionChat).exists) { card.tap() }
            if el(AXID.quickActionChat).waitForExistence(timeout: 10) {
                el(AXID.quickActionChat).tap()
            } else {
                Harness.tapModeSegment(app, "Chat")
            }
            if el(AXID.chatInputField).waitForExistence(timeout: 12) { return true }
        }
        attachHierarchy("chat-never-opened")
        return false
    }

    /// The simulated peers, by callsign, so a reply from one of them can be
    /// told apart from the seeded history.
    private static let demoPeerNames = ["Ridge-7", "Nova-12", "Ghost-21", "Wolf-3"]

    /// How many messages from simulated peers are on screen.
    private func peerMessageCount() -> Int {
        let clauses = Self.demoPeerNames.map { _ in "label BEGINSWITH %@" }.joined(separator: " OR ")
        let predicate = NSPredicate(format: clauses, argumentArray: Self.demoPeerNames)
        return app.descendants(matching: .staticText).matching(predicate).count
    }

    /// Type into the chat field and send, verifying the text actually landed:
    /// a tap that does not focus the field leaves `typeText` writing nowhere,
    /// which then looks exactly like "the peer never answered".
    private func sendChatMessage(_ text: String) -> Bool {
        let field = el(AXID.chatInputField)
        guard field.waitForExistence(timeout: 15) else {
            attachHierarchy("no-chat-input")
            return false
        }
        var typed = false
        for _ in 0..<3 where !typed {
            field.tap()
            field.typeText(text)
            typed = (field.value as? String)?.contains(text) ?? false
        }
        guard typed else {
            attachHierarchy("chat-text-never-entered")
            return false
        }
        el(AXID.chatSendButton).tap()
        let sent = waitUntil(timeout: 15) {
            self.app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists
        }
        if !sent { attachHierarchy("chat-message-never-sent") }
        return sent
    }

    /// Open Settings from the home screen, verified.
    ///
    /// Taps on this toolbar button have been observed to do nothing on iPad,
    /// which then reads as "Settings has no Demo Mode toggle".
    private func openSettings() -> Bool {
        for _ in 0..<3 {
            if el(AXID.demoModeToggle).exists { return true }
            let button = el(AXID.settingsButton)
            guard button.waitForExistence(timeout: 15) else { break }
            button.tap()
            if el(AXID.demoModeToggle).waitForExistence(timeout: 10) { return true }
        }
        attachHierarchy("settings-never-opened")
        return false
    }

    /// Scroll `element` into view and tap it.
    ///
    /// XCUITest does not scroll for you: tapping an element that exists in the
    /// hierarchy but is off the bottom of a long screen sends the tap to a
    /// coordinate nobody is looking at, and the failure reads as if the
    /// feature were broken. Settings is long enough that Blocked Users is
    /// below the fold on both devices.
    @discardableResult
    private func scrollToAndTap(_ element: XCUIElement, tries: Int = 6) -> Bool {
        guard element.waitForExistence(timeout: 15) else { return false }
        if element.isHittable {
            element.tap()
            return true
        }
        // Which way it lies is not known, so try down and then back up. A
        // one-directional search walked past the row to the end of Settings
        // and then tapped a coordinate that was no longer on screen.
        for _ in 0..<tries {
            app.swipeUp()
            if element.isHittable { element.tap(); return true }
        }
        for _ in 0..<(tries * 2) {
            app.swipeDown()
            if element.isHittable { element.tap(); return true }
        }
        return false
    }

    /// The button carrying `id`.
    ///
    /// `el(_:)` returns the first element of any type with that identifier,
    /// and SwiftUI propagates an identifier to the wrappers around a control,
    /// so the first match is usually a container that reports
    /// `isHittable == false`. Anything that has to be tapped after scrolling
    /// needs the control itself.
    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func attachHierarchy(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        shot(name)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let element = el(id)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(id) never appeared", file: file, line: line)
        element.tap()
    }

    /// Tap the final onboarding Continue until the microphone prompt shows.
    ///
    /// A single tap has been observed to land with no effect on iPad, which
    /// looks identical to "the button does not ask for the microphone" and is
    /// exactly the thing under test, so it is retried before failing.
    /// Tap a pre-prompt screen's single button until the system alert shows.
    ///
    /// These buttons disable themselves once the request is in flight, so a
    /// retry only happens when the button is still enabled, which is exactly
    /// the case where the previous tap was lost. Both the lost tap and the
    /// slow first alert on a freshly erased simulator look like "no prompt".
    private func tapForSystemPrompt(_ identifier: String, label: String) -> XCUIElement? {
        for attempt in 0..<3 {
            let button = el(identifier)
            if button.exists, button.isEnabled { button.tap() }
            if let alert = waitForSystemAlert(timeout: attempt == 0 ? 40 : 20) { return alert }
        }
        attachHierarchy("no-\(label)-prompt")
        return nil
    }

    private func tapFinalContinueForMicrophonePrompt() -> XCUIElement? {
        // The button disables itself while the request is in flight, so a
        // retry is only useful once that has cleared; most of the budget goes
        // to simply waiting, which is what a freshly erased simulator needs.
        for attempt in 0..<3 {
            let button = el(AXID.getStartedButton)
            if button.exists, button.isEnabled { button.tap() }
            if let alert = waitForSystemAlert(timeout: attempt == 0 ? 45 : 20) { return alert }
            if waitForHome(timeout: 1) {
                attachHierarchy("no-microphone-prompt-app-continued")
                return nil
            }
        }
        attachHierarchy("no-microphone-prompt")
        return nil
    }

    /// Walk onboarding up to (not through) the final Continue, asserting that
    /// no page offers an exit.
    private func walkOnboardingToMicrophonePage() {
        XCTAssertTrue(el(AXID.onboardingView).waitForExistence(timeout: 30), "onboarding never appeared")

        let finalButton = el(AXID.getStartedButton)
        var page = 0
        while !finalButton.exists && page < 10 {
            assertNoExits("onboarding page \(page)")
            shot("onboarding-page-\(page)")

            // The rules page gates its Continue behind acceptance. Accepting
            // is not an exit: it does not leave the flow.
            let agree = app.buttons["I agree to the terms and community rules"].firstMatch
            if agree.exists, !el(AXID.onboardingContinue).isEnabled {
                agree.tap()
            }
            let next = el(AXID.onboardingContinue)
            guard next.waitForExistence(timeout: 10) else { break }
            next.tap()
            page += 1
        }

        XCTAssertTrue(finalButton.waitForExistence(timeout: 20), "never reached the microphone page")
        XCTAssertTrue(el(AXID.onboardingMicPage).exists, "the last page is not the microphone explainer")
        assertNoExits("onboarding microphone page")
        XCTAssertEqual(finalButton.label, "Continue", "the final onboarding button must read Continue")
        shot("onboarding-microphone-page")
    }

    // MARK: - 5.1.1(iv) Microphone

    /// Declining is a supported outcome: the app opens anyway and says where
    /// to change it.
    func testOnboardingMicrophonePromptThenDenyKeepsAppUsable() {
        _ = launch(onboarded: false)
        walkOnboardingToMicrophonePage()

        guard let alert = tapFinalContinueForMicrophonePrompt() else {
            return XCTFail("tapping Continue did not produce the system microphone prompt")
        }
        XCTAssertTrue(
            alert.staticTexts.allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("microphone") },
            "the alert that appeared is not the microphone prompt: \(alert.debugDescription)"
        )
        shot("system-microphone-prompt")
        answerSystemAlert(alert, allow: false)

        XCTAssertTrue(waitForHome(timeout: 30), "the app did not open after declining")
        XCTAssertTrue(permissionNoticeIsUp("Microphone is off"),
                      "no inline microphone notice with Open Settings")
        XCTAssertTrue(el(AXID.pttButton).exists, "the Talk screen is gone after declining")
        shot("microphone-denied-notice")
    }

    /// Granting: same flow, no notice, and the talk button works.
    func testOnboardingMicrophonePromptThenAllow() {
        _ = launch(onboarded: false)
        walkOnboardingToMicrophonePage()

        guard let alert = tapFinalContinueForMicrophonePrompt() else {
            return XCTFail("tapping Continue did not produce the system microphone prompt")
        }
        answerSystemAlert(alert, allow: true)

        XCTAssertTrue(waitForHome(timeout: 30), "the app did not open after granting")
        XCTAssertFalse(app.staticTexts["Microphone is off"].firstMatch.exists,
                       "microphone notice shown although access was granted")
        shot("microphone-granted-home")
    }

    // MARK: - 5.1.2(i) Location

    // These five tests replace `testLocationExplainerOnlyLeadsToThePrompt`,
    // which asserted that a custom screen stood in front of the system
    // location prompt with a single Continue button. That screen satisfied
    // 5.1.1(iv) in round 2 and was the thing Apple rejected in round 3: a
    // pre-prompt screen may only lead to the prompt, so it cannot also carry
    // the app's own sharing consent, and that consent has to be refusable.
    //
    // The two questions are now separate, and so are the assertions. Nothing
    // here is a relaxed version of the old test: the old one required the
    // explainer to exist, and `testCheckInAsksTheSystemDirectly` requires it
    // not to.

    /// Tapping Check In on a fresh install produces the iOS prompt and
    /// nothing else first.
    func testCheckInAsksTheSystemDirectly() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(
            switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }),
            "the Map tab never came up: \(self.visibleButtonLabels())"
        )

        let consent = el(AXID.locationConsentSheet)
        XCTAssertFalse(consent.exists, "the consent sheet was up before Check In was tapped")

        // Watch for our own sheet and the system alert at the same time. The
        // alert winning is the pass; our sheet appearing first is the exact
        // violation, so it is checked on every poll rather than once at the
        // end, when it would already have been dismissed.
        var sawOwnScreenFirst = false
        var alert: XCUIElement?
        for attempt in 0..<3 where alert == nil {
            let button = el(AXID.mapCheckInButton)
            if button.exists, button.isEnabled { button.tap() }
            let deadline = Date().addingTimeInterval(attempt == 0 ? 40 : 20)
            while Date() < deadline {
                if let found = anySystemAlert { alert = found; break }
                if consent.exists { sawOwnScreenFirst = true; break }
                Thread.sleep(forTimeInterval: 0.3)
            }
            if sawOwnScreenFirst { break }
        }

        if sawOwnScreenFirst { attachHierarchy("consent-sheet-before-system-prompt") }
        XCTAssertFalse(
            sawOwnScreenFirst,
            "a ChirpChirps screen appeared before the system location prompt; 5.1.2(i) allows none"
        )
        guard let alert else {
            attachHierarchy("no-location-prompt")
            return XCTFail("Check In did not produce the system location prompt")
        }
        shot("system-location-prompt")

        // Allowing the OS permission must NOT by itself put the user on the
        // map: the app still has to ask.
        answerSystemAlert(alert, allow: true)
        // A tap that is swallowed while the system alert is dismissing looks
        // exactly like a missing sheet, so Check In is offered again before
        // this is called a failure. What is being asserted is that granting
        // the OS permission is not by itself enough to share — a second tap
        // still has to be answered.
        var asked = consent.waitForExistence(timeout: 40)
        for _ in 0..<2 where !asked {
            let button = el(AXID.mapCheckInButton)
            if button.exists, button.isEnabled { button.tap() }
            asked = consent.waitForExistence(timeout: 20)
        }
        if !asked { attachHierarchy("no-consent-after-granting") }
        XCTAssertTrue(asked, "granting location did not bring up the app's sharing consent")
        XCTAssertFalse(
            el(AXID.mapSharingIndicator).exists,
            "granting the OS permission put the user on the map without them agreeing"
        )
        assertConsentSheetIsRefusable()
        shot("location-consent-sheet")
    }

    /// Declining the system prompt leads to an inline notice, never to a
    /// custom screen that offers to ask again.
    func testCheckInDeclinedShowsSettingsNoticeNotAScreen() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }))

        guard let alert = tapForSystemPrompt(AXID.mapCheckInButton, label: "location") else {
            return XCTFail("Check In did not produce the system location prompt")
        }
        answerSystemAlert(alert, allow: false)

        XCTAssertTrue(permissionNoticeIsUp("Location is off"),
                      "no inline location notice with Open Settings")
        XCTAssertFalse(el(AXID.locationConsentSheet).exists,
                       "the consent sheet came up although location was refused")
        shot("location-denied-notice")

        // A second tap must not conjure a screen either: iOS will not show
        // the prompt again, so a screen leading to one would lead nowhere.
        tap(AXID.mapCheckInButton)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(el(AXID.locationConsentSheet).exists,
                       "a second Check In raised the consent sheet without permission")
        XCTAssertTrue(permissionNoticeIsUp("Location is off"),
                      "the inline notice went away on a second Check In")
    }

    /// Don't Share leaves the user off the map, and so does swiping the sheet
    /// away. Both are refusals; neither is a deferral.
    func testConsentRefusalLeavesUserOffTheMap() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }))
        guard reachConsentSheet() else { return }

        assertConsentSheetIsRefusable()
        el(AXID.locationDontShareButton).tap()
        XCTAssertTrue(Harness.waitGone(el(AXID.locationConsentSheet), timeout: 15),
                      "the consent sheet stayed up after Don't Share")
        assertNotSharing(after: "Don't Share")
        shot("location-not-shared")

        // Now the same question answered by dismissing it rather than
        // answering it.
        guard reachConsentSheet() else { return }
        XCTAssertTrue(dismissConsentByGesture(),
                      "the consent sheet could not be dismissed by gesture; dismissal must count as a refusal")
        assertNotSharing(after: "dismissing the sheet")
    }

    /// The consent is asked again on the next Check In in the same launch,
    /// and again after a relaunch, which never resumes a session.
    func testConsentIsAskedEveryTimeAndNeverResumes() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }))

        guard reachConsentSheet() else { return }
        el(AXID.locationShareButton).tap()
        XCTAssertTrue(el(AXID.mapSharingIndicator).waitForExistence(timeout: 20),
                      "Share did not start a session")
        shot("location-sharing")

        // Stop, then check in again: the question must be put a second time.
        tap(AXID.mapStopSharingButton)
        XCTAssertTrue(Harness.waitGone(el(AXID.mapSharingIndicator), timeout: 15),
                      "Stop did not end the session")
        XCTAssertTrue(reachConsentSheet(),
                      "the second Check In in one launch did not ask for consent again")
        el(AXID.locationDontShareButton).tap()

        // Share, then relaunch mid-session. The app must come back checked out.
        guard reachConsentSheet() else { return }
        el(AXID.locationShareButton).tap()
        XCTAssertTrue(el(AXID.mapSharingIndicator).waitForExistence(timeout: 20))

        app.terminate()
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }))
        assertNotSharing(after: "relaunch")
        XCTAssertTrue(reachConsentSheet(),
                      "after a relaunch, Check In did not ask for consent again")
        shot("location-consent-after-relaunch")
    }

    /// Nothing anywhere offers to share automatically, always, or to remember
    /// the answer. Asserted by reading Settings rather than by trusting it.
    func testNoSettingOffersAutomaticSharing() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(openSettings(), "Settings never came up")

        // Scroll the whole screen and collect every label on the way.
        var seen = Set<String>()
        for _ in 0..<8 {
            for element in app.descendants(matching: .any).allElementsBoundByIndex where element.exists {
                let label = element.label
                if !label.isEmpty { seen.insert(label) }
            }
            app.swipeUp()
        }

        // "Automatic", "Always" and "Remember" next to anything about sharing
        // or location is the shape of the setting Apple forbids here.
        let forbidden = ["automatic", "automatically", "always share", "always on",
                         "remember", "don't ask again", "dont ask again", "keep sharing",
                         "share continuously", "background location"]
        let offenders = seen.filter { label in
            let lower = label.lowercased()
            return forbidden.contains { lower.contains($0) }
        }
        if !offenders.isEmpty { attachHierarchy("automatic-sharing-setting") }
        XCTAssertTrue(
            offenders.isEmpty,
            "Settings offers what looks like automatic or remembered sharing: \(offenders.sorted())"
        )
        shot("settings-no-automatic-sharing")
    }

    // MARK: - Location helpers

    /// Get to the consent sheet from the Map tab, answering the system prompt
    /// on the way if this install has not been asked yet. Returns false and
    /// fails the test if the sheet never arrives.
    @discardableResult
    private func reachConsentSheet(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let consent = el(AXID.locationConsentSheet)
        for _ in 0..<3 {
            let button = el(AXID.mapCheckInButton)
            if button.exists, button.isEnabled { button.tap() }
            if consent.waitForExistence(timeout: 12) { return true }
            // Never asked on this install: answer iOS and let the app ask next.
            if let alert = anySystemAlert {
                answerSystemAlert(alert, allow: true)
                if consent.waitForExistence(timeout: 20) { return true }
            }
        }
        attachHierarchy("no-consent-sheet")
        XCTFail("the sharing consent sheet never appeared", file: file, line: line)
        return false
    }

    /// The consent sheet must offer a plainly visible refusal. This is the
    /// mirror image of `assertNoExits`: a pre-prompt screen may not offer a
    /// way out, and this screen must.
    private func assertConsentSheetIsRefusable(file: StaticString = #filePath, line: UInt = #line) {
        let decline = el(AXID.locationDontShareButton)
        let share = el(AXID.locationShareButton)
        XCTAssertTrue(decline.exists, "the consent sheet has no Don't Share", file: file, line: line)
        XCTAssertTrue(share.exists, "the consent sheet has no Share", file: file, line: line)
        XCTAssertTrue(decline.isHittable, "Don't Share is not tappable", file: file, line: line)
        // Equal prominence, as far as a UI test can see it: comparable width,
        // so a refusal cannot be shrunk into a footnote.
        if decline.frame.width > 0, share.frame.width > 0 {
            let ratio = decline.frame.width / share.frame.width
            XCTAssertTrue(
                ratio > 0.8 && ratio < 1.25,
                "Don't Share is not as prominent as Share (width ratio \(ratio))",
                file: file, line: line
            )
        }
    }

    /// Get rid of the consent sheet without answering it, the way a user
    /// flicks a sheet away. `app.swipeDown()` alone is not enough: it drives
    /// the whole app element, and on iPad the sheet is a card floating over a
    /// dimmed app, so the swipe lands behind it. Each of these is a real
    /// dismissal a user can perform, and every one of them has to leave them
    /// off the map — which the caller asserts next.
    private func dismissConsentByGesture() -> Bool {
        let sheet = el(AXID.locationConsentSheet)
        for attempt in 0..<4 {
            if !sheet.exists { return true }
            switch attempt {
            case 0, 1:
                // Drag the sheet itself down and off the screen.
                let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
                let end = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 3.0))
                start.press(forDuration: 0.1, thenDragTo: end)
            case 2:
                app.swipeDown()
            default:
                // Tapping the dimmed area outside the card, which is how iPad
                // dismisses one.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
            }
            if Harness.waitGone(sheet, timeout: 8) { return true }
        }
        attachHierarchy("consent-sheet-would-not-dismiss")
        return !sheet.exists
    }

    private func assertNotSharing(after step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(
            el(AXID.mapSharingIndicator).exists,
            "the user is on the map after \(step)",
            file: file, line: line
        )
        XCTAssertTrue(
            el(AXID.mapCheckInButton).exists,
            "the Map lost its Check In button after \(step)",
            file: file, line: line
        )
    }

    /// Tap a map pin.
    ///
    /// `MLNMapView` is an accessibility container that synthesises an element
    /// per annotation, and the frames it publishes are in the map's own
    /// coordinate space, not the screen's. On an iPhone 16 Pro Max with the
    /// map inset 180pt from the top, Wolf-3's element reported a frame
    /// centred at y=417 while the pin was drawn at y=585 — exactly the map's
    /// origin apart, confirmed against a screenshot. So the element reports
    /// `isHittable == false` and tapping it, or any point derived from it in
    /// screen space, lands on empty map.
    ///
    /// Reading the frame as map-local, which is what it is, gives the point a
    /// finger would hit. See the known-issues note in the report: the wrong
    /// frames are MapLibre's, and they also mean VoiceOver aims at the wrong
    /// place.
    private func tapPin(_ pin: XCUIElement, in map: XCUIElement) {
        guard map.frame.width > 0, map.frame.height > 0 else {
            pin.tap()
            return
        }
        map.coordinate(withNormalizedOffset: CGVector(
            dx: pin.frame.midX / map.frame.width,
            dy: pin.frame.midY / map.frame.height
        )).tap()
    }

    // MARK: - 5.1.2(i) Blocking

    /// Apple's first requirement, driven the way a reviewer would drive it:
    /// in Demo Mode, on one device, from a map pin.
    ///
    /// Demo Mode is the case that mattered and the case that was broken.
    /// `DemoMode.deliver()` hands simulated packets straight to
    /// `AppState.deliverLocally`, which skips `MeshRouter` and therefore skips
    /// the router's blocked-origin filter. Text and pins were still filtered
    /// because those services check the block list themselves; push-to-talk
    /// audio was not, so a blocked peer kept talking.
    func testBlockingADemoPeerRemovesThemAndUnblockRestores() {
        _ = launch(onboarded: true, demo: true)
        XCTAssertTrue(waitForHome(timeout: 30))

        XCTAssertTrue(
            switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }),
            "the Map tab never came up"
        )

        let map = el(AXID.peerMap)
        XCTAssertTrue(map.waitForExistence(timeout: 30), "the demo map never appeared")

        // MapLibre is its own accessibility container, so a pin is found by
        // the peer's name inside the map subtree. Narrowed to the pin
        // identifier rather than every descendant: enumerating the whole
        // subtree by index while the map is changing throws "No matches found
        // for Element at index 5" as elements come and go underneath it, and
        // the map is changing precisely when a pin is being removed, which is
        // what this test is about.
        let names = Self.demoPeerNames
        func pinnedNames() -> Set<String> {
            let pins = map.descendants(matching: .any).matching(identifier: AXID.mapPeerPin)
            var found: Set<String> = []
            for element in pins.allElementsBoundByIndex {
                let label = element.label
                if let name = names.first(where: { label.hasPrefix($0) }) { found.insert(name) }
            }
            return found
        }
        // One query rather than an enumeration, for use while pins are
        // disappearing.
        func isPinned(_ name: String) -> Bool {
            map.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", AXID.mapPeerPin, name)
            ).firstMatch.exists
        }

        guard waitUntil(timeout: 30, { !pinnedNames().isEmpty }) else {
            attachHierarchy("no-demo-pins-to-block")
            return XCTFail("no demo pins on the map to block")
        }
        let before = pinnedNames()
        guard let victim = before.sorted().first else { return XCTFail("no pin name") }
        shot("block-map-before")

        let pin = map.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", victim)).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))

        // MapLibre annotations are drawn, not laid out, so a tap can land
        // beside the pin rather than on it. Retry before calling the sheet
        // missing; the assertion is still that a pin opens it.
        let sheet = el(AXID.peerActionSheet)
        var sheetOpen = false
        for _ in 0..<3 where !sheetOpen {
            tapPin(pin, in: map)
            sheetOpen = sheet.waitForExistence(timeout: 12)
        }
        if !sheetOpen { attachHierarchy("pin-did-not-open-peer-sheet") }
        XCTAssertTrue(sheetOpen, "tapping a pin did not open the peer sheet")
        XCTAssertTrue(el(AXID.peerSheetReportButton).exists, "the peer sheet has no Report")
        shot("block-peer-sheet")

        tap(AXID.peerSheetBlockButton)
        // One confirmation, as the guideline asks.
        let confirm = app.buttons["Block"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "blocking asked for no confirmation")
        confirm.tap()

        XCTAssertTrue(
            waitUntil(timeout: 25, { !isPinned(victim) }),
            "\(victim) is still pinned on the map after being blocked"
        )
        shot("block-map-after")

        // Settings lists them, and unblocking gives them back.
        XCTAssertTrue(goBack(until: { self.waitForHome(timeout: 1) }) || waitForHome(timeout: 5))
        XCTAssertTrue(openSettings(), "Settings never opened")
        let blockedRow = button(AXID.blockedUsersRow)
        XCTAssertTrue(blockedRow.waitForExistence(timeout: 15), "Settings has no Blocked Users row")

        // SwiftUI merges a row's texts into its Button, so the blocked peer
        // appears as part of a label rather than as a static text of its own:
        // matched by containment, not by an exact `staticTexts[name]`.
        func isListed() -> Bool {
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", victim))
                .firstMatch.exists
        }

        // Blocked Users is a disclosure. Tapping the merged Button did not
        // toggle it, so the row's own text is tapped, which is unambiguously
        // the control.
        var listed = false
        for attempt in 0..<4 where !listed {
            switch attempt {
            case 0: scrollToAndTap(blockedRow)
            case 1: scrollToAndTap(app.staticTexts["Blocked Users"].firstMatch)
            default: scrollToAndTap(blockedRow)
            }
            for _ in 0..<4 where !listed {
                listed = waitUntil(timeout: 3, { isListed() })
                if !listed { app.swipeUp() }
            }
        }
        if !listed { attachHierarchy("blocked-user-not-listed") }
        XCTAssertTrue(listed, "\(victim) is not listed under Blocked Users")
        shot("blocked-users-list")

        let unblock = app.buttons["Unblock"].firstMatch
        XCTAssertTrue(unblock.waitForExistence(timeout: 10), "no Unblock button")
        XCTAssertTrue(scrollToAndTap(unblock), "could not reach Unblock")
        // Unblocking removes the row, so wait on the name going rather than
        // on the button.
        XCTAssertTrue(
            waitUntil(timeout: 15, { !isListed() }),
            "\(victim) stayed in the blocked list after Unblock"
        )
        shot("blocked-users-after-unblock")
    }

    /// The second entry point Apple's requirement names: the sender of a text
    /// message. It has to reach the *same* sheet the map pin reaches, because
    /// that is where Report lives, and reporting from a message used to skip
    /// it entirely — which meant reporting without a reason and without the
    /// sender's identity fingerprint.
    ///
    /// The effect asserted is the one a user would check: their history goes.
    func testBlockingFromAMessageHidesTheirHistory() {
        _ = launch(onboarded: true, demo: true)
        XCTAssertTrue(waitForHome(timeout: 30))
        XCTAssertTrue(enterChannelChat(), "could not reach the demo channel's chat")

        // Wait for seeded history, then pick whoever is actually on screen.
        guard waitUntil(timeout: 30, { self.peerMessageCount() > 0 }) else {
            attachHierarchy("no-demo-history-to-block")
            return XCTFail("the demo channel has no peer messages to block")
        }
        let clauses = Self.demoPeerNames.map { _ in "label BEGINSWITH %@" }.joined(separator: " OR ")
        let predicate = NSPredicate(format: clauses, argumentArray: Self.demoPeerNames)
        let senderLabel = app.descendants(matching: .staticText).matching(predicate).firstMatch
        XCTAssertTrue(senderLabel.waitForExistence(timeout: 15))
        guard let victim = Self.demoPeerNames.first(where: { senderLabel.label.hasPrefix($0) }) else {
            attachHierarchy("sender-label-unrecognised")
            return XCTFail("could not read a sender name off the chat")
        }
        func messagesFrom(_ name: String) -> Int {
            app.descendants(matching: .staticText)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name)).count
        }
        XCTAssertGreaterThan(messagesFrom(victim), 0, "precondition: \(victim) has history on screen")
        shot("block-from-message-before")

        // Long press opens the message's context menu.
        var menuOpen = false
        for _ in 0..<3 where !menuOpen {
            senderLabel.press(forDuration: 1.2)
            menuOpen = el(AXID.messageBlockOrReport).waitForExistence(timeout: 8)
                || app.buttons["Block or Report"].firstMatch.waitForExistence(timeout: 2)
        }
        if !menuOpen { attachHierarchy("message-context-menu-never-opened") }
        XCTAssertTrue(menuOpen, "long pressing a message did not offer Block or Report")
        shot("message-context-menu")

        let entry = el(AXID.messageBlockOrReport).exists
            ? el(AXID.messageBlockOrReport)
            : app.buttons["Block or Report"].firstMatch
        entry.tap()

        let sheet = el(AXID.peerActionSheet)
        XCTAssertTrue(sheet.waitForExistence(timeout: 15),
                      "blocking from a message did not open the peer sheet")
        XCTAssertTrue(el(AXID.peerSheetReportButton).exists,
                      "the sheet reached from a message has no Report")
        shot("block-from-message-sheet")

        tap(AXID.peerSheetBlockButton)
        let confirm = app.buttons["Block"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "blocking asked for no confirmation")
        confirm.tap()

        XCTAssertTrue(
            waitUntil(timeout: 25, { messagesFrom(victim) == 0 }),
            "\(victim)'s messages are still on screen after being blocked"
        )
        shot("block-from-message-after")
    }

    // MARK: - 2.1(a) Demo Mode

    /// One device, every feature. Enables Demo Mode in Settings and exercises
    /// peers, channel history, a played voice note, a text reply with its
    /// ACK, a push-to-talk answer, map pins and the voice-message inbox, then
    /// relaunches to prove it persists and switches it off again.
    func testDemoModeGivesASingleDeviceEverything() {
        _ = launch(onboarded: true, demo: false)
        XCTAssertTrue(waitForHome(timeout: 30))

        let meshStatus = el(AXID.meshStatusLabel)
        XCTAssertTrue(meshStatus.waitForExistence(timeout: 15))
        XCTAssertEqual(meshStatus.label, "No mesh", "the mesh should be empty before Demo Mode")
        shot("demo-off-home")

        // On: Settings > Demo Mode.
        XCTAssertTrue(openSettings(), "Settings never opened, or it has no Demo Mode toggle")
        let toggle = el(AXID.demoModeToggle)
        shot("settings-demo-toggle")

        // A tap on the row has been observed to land without flipping the
        // switch (iPad), so the switch itself and then its right-hand side are
        // tried, and the DEMO badge is what decides whether it worked.
        let badge = el(AXID.demoBadge)
        let switchElement = app.switches[AXID.demoModeToggle].firstMatch
        let target = switchElement.exists ? switchElement : toggle
        var switchedOn = false
        for attempt in 0..<4 where !switchedOn {
            switch attempt {
            case 0: target.tap()
            // The switch sits at the right-hand end of the row; a tap in the
            // middle lands on the label, which does not flip it.
            case 1: target.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            case 2: app.swipeUp(); target.tap()
            default: toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
            }
            switchedOn = badge.waitForExistence(timeout: 8)
        }
        if !switchedOn { attachHierarchy("demo-toggle-did-not-switch") }
        XCTAssertTrue(switchedOn, "no DEMO badge after switching Demo Mode on in Settings")
        XCTAssertTrue(goBack(until: { self.waitForHome(timeout: 1) }), "never got back to the home screen from Settings")

        // Peers.
        XCTAssertTrue(
            waitUntil(timeout: 20) { meshStatus.exists && meshStatus.label != "No mesh" },
            "the header still reads \"No mesh\" in Demo Mode: \(meshStatus.label)"
        )
        XCTAssertTrue(el(AXID.demoBadge).exists, "the DEMO badge is not on the home screen")
        shot("demo-on-home")

        // Channel history, with received voice notes that play.
        XCTAssertTrue(enterChannelChat(), "could not reach the demo channel's chat")
        XCTAssertTrue(
            waitUntil(timeout: 20) { app.staticTexts.allElementsBoundByIndex.count > 3 },
            "the demo channel has no history"
        )
        shot("demo-chat-history")

        let voiceNote = el(AXID.voiceNotePlayButton)
        XCTAssertTrue(voiceNote.waitForExistence(timeout: 15), "no voice note in the demo history")
        voiceNote.tap()
        XCTAssertTrue(
            waitUntil(timeout: 10) { el(AXID.voiceNotePlayButton).value as? String == "Playing" },
            "the demo voice note did not start playing"
        )
        shot("demo-voice-note-playing")

        // A text gets an ACK and an answer.
        let token = "ping-\(Int(Date().timeIntervalSince1970) % 100000)"
        let repliesBefore = peerMessageCount()
        XCTAssertTrue(sendChatMessage(token), "could not send a message in the demo channel")
        XCTAssertTrue(
            Harness.waitForDeliveryACK(app, token: token, timeout: 30),
            "the simulated peer never acknowledged the message"
        )
        XCTAssertTrue(
            waitUntil(timeout: 30) { self.peerMessageCount() > repliesBefore },
            "the simulated peer never replied"
        )
        shot("demo-text-reply")

        // Push-to-talk gets an answer, on the air, from a named peer.
        var inTalkMode = false
        for _ in 0..<3 where !inTalkMode {
            Harness.tapModeSegment(app, "Talk")
            inTalkMode = el(AXID.pttButton).waitForExistence(timeout: 10)
        }
        if !inTalkMode { attachHierarchy("talk-mode-never-opened") }
        XCTAssertTrue(inTalkMode, "the channel's Talk mode never came up")
        let receiving = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", AXID.statusPill, "Receiving from")
        ).firstMatch
        // A press that does not register looks exactly like a peer that never
        // answers, so the press is repeated. The answer itself is still what
        // is asserted: a status pill naming who is speaking.
        var answered = false
        for _ in 0..<3 where !answered {
            Harness.transmit(app, for: 2.0)
            // If this device has never been asked, the press asks instead of
            // transmitting. Answer and press again.
            if let alert = anySystemAlert {
                answerSystemAlert(alert, allow: true)
                Harness.transmit(app, for: 2.0)
            }
            answered = receiving.waitForExistence(timeout: 15)
        }
        if !answered { attachHierarchy("no-ptt-answer") }
        XCTAssertTrue(answered, "nobody answered the push-to-talk")
        shot("demo-ptt-reply")

        // Back home for the map and the inbox.
        XCTAssertTrue(goBack(until: { self.waitForHome(timeout: 1) }), "never got back to the home screen from the channel")
        XCTAssertTrue(
            switchToTab("Map", until: { self.el(AXID.mapPeerPin).exists || self.el(AXID.mapCheckInButton).exists }, timeout: 20),
            "the Map tab never came up"
        )
        let map = el(AXID.peerMap)
        XCTAssertTrue(map.waitForExistence(timeout: 20), "the map view never appeared")
        // MapLibre's map view is an accessibility container: it publishes one
        // element per annotation it is currently showing, labelled with the
        // annotation's title, and hides the annotation views underneath. So a
        // pin is found by the peer's name, inside the map, and finding one
        // means that peer is pinned and on screen.
        func pinnedNames() -> Set<String> {
            let names = ["Ridge-7", "Nova-12", "Ghost-21", "Wolf-3"]
            let found = map.descendants(matching: .any).allElementsBoundByIndex.compactMap { element -> String? in
                names.first { element.label.hasPrefix($0) }
            }
            return Set(found)
        }
        // Two distinct peers, so a single marker standing in for the whole
        // group would not pass.
        if !waitUntil(timeout: 30, { pinnedNames().count >= 2 }) {
            attachHierarchy("no-map-pins")
            add({ let a = XCTAttachment(string: map.debugDescription)
                  a.name = "map-subtree"; a.lifetime = .keepAlways; return a }())
        }
        XCTAssertGreaterThanOrEqual(pinnedNames().count, 2, "no pins on the demo map")
        shot("demo-map-pins")

        // Same lost-tap pattern as the tabs and Settings: the button is tapped
        // until the inbox it opens is actually on screen.
        let play = el(AXID.voiceMessagePlayButton)
        var inboxOpen = false
        for _ in 0..<3 where !inboxOpen {
            let entry = app.buttons["Voice Messages"].firstMatch
            if entry.waitForExistence(timeout: 10) { entry.tap() }
            inboxOpen = play.waitForExistence(timeout: 15)
        }
        if !inboxOpen { attachHierarchy("voice-inbox-never-opened") }
        XCTAssertTrue(inboxOpen, "the demo voice-message inbox is empty")
        play.tap()
        XCTAssertTrue(
            waitUntil(timeout: 10) { el(AXID.voiceMessagePlayButton).label.localizedCaseInsensitiveContains("stop") },
            "the demo voice message did not start playing"
        )
        shot("demo-voice-message-playing")
        goBack(until: { self.waitForHome(timeout: 1) })

        // It survives a relaunch.
        app.terminate()
        app.launchArguments = ["-ChirpUITest", "YES", "-com.chirpchirp.onboardingComplete", "YES"]
        app.launch()
        sweepIncidentalAlerts()
        XCTAssertTrue(el(AXID.demoBadge).waitForExistence(timeout: 30), "Demo Mode did not survive a relaunch")
        shot("demo-after-relaunch")

        // Off again, from the badge, back to the real empty state.
        tap(AXID.demoExitButton)
        XCTAssertTrue(Harness.waitGone(el(AXID.demoBadge), timeout: 20), "the DEMO badge stayed after exiting")
        let status = el(AXID.meshStatusLabel)
        XCTAssertTrue(
            waitUntil(timeout: 20) { status.exists && status.label == "No mesh" },
            "the real empty state did not come back: \(status.label)"
        )
        XCTAssertTrue(el(AXID.tryDemoModeButton).waitForExistence(timeout: 20), "the empty state offers no way back into Demo Mode")
        shot("demo-off-again")
    }

    /// The other entry point: the empty state's own button.
    func testEmptyStateOffersDemoMode() {
        _ = launch(onboarded: true, demo: false)
        XCTAssertTrue(waitForHome(timeout: 30))

        let tryButton = el(AXID.tryDemoModeButton)
        XCTAssertTrue(tryButton.waitForExistence(timeout: 25), "the Talk empty state has no Try Demo Mode button")
        shot("empty-state-try-demo")
        tryButton.tap()
        XCTAssertTrue(el(AXID.demoBadge).waitForExistence(timeout: 20), "Try Demo Mode did not switch it on")
        shot("empty-state-demo-on")
        tap(AXID.demoExitButton)
        XCTAssertTrue(Harness.waitGone(el(AXID.demoBadge), timeout: 20))
    }

    // MARK: - Polling

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return condition()
    }
}

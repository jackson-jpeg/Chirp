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
        let general = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", AXID.channelCard, "General")
        ).firstMatch
        let card = general.waitForExistence(timeout: 5) ? general : el(AXID.channelCard)
        guard card.waitForExistence(timeout: 10) else {
            attachHierarchy("no-channel-card")
            return false
        }
        for attempt in 0..<3 {
            if el(AXID.chatInputField).exists { return true }
            if attempt > 0 || !el(AXID.quickActionChat).exists { card.tap() }
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

    // MARK: - 5.1.1(iv) Location

    /// The check-in explainer: one button, no swipe out, and the prompt.
    func testLocationExplainerOnlyLeadsToThePrompt() {
        _ = launch(onboarded: true)
        XCTAssertTrue(waitForHome(timeout: 30))

        XCTAssertTrue(
            switchToTab("Map", until: { self.el(AXID.mapCheckInButton).exists }),
            "the Map tab never came up: \(self.visibleButtonLabels())"
        )
        tap(AXID.mapCheckInButton)

        let explainer = el(AXID.locationExplainer)
        XCTAssertTrue(explainer.waitForExistence(timeout: 15), "the check-in explainer never appeared")
        assertNoExits("location check-in explainer")
        let labels = visibleButtonLabels()
        XCTAssertTrue(labels.contains("Continue"), "the explainer has no Continue: \(labels)")
        shot("location-explainer")

        // Swipe-to-dismiss must not work (interactiveDismissDisabled).
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(explainer.exists, "the explainer was dismissed by a swipe, with no prompt shown")
        XCTAssertNil(anySystemAlert, "a system alert appeared before Continue was tapped")

        // The swipe attempts above may have scrolled the sheet's content.
        app.swipeUp()
        guard let alert = tapForSystemPrompt(AXID.locationContinue, label: "location") else {
            return XCTFail("Continue did not produce the system location prompt")
        }
        shot("system-location-prompt")
        answerSystemAlert(alert, allow: false)

        XCTAssertTrue(Harness.waitGone(explainer, timeout: 20), "the explainer stayed up after the prompt was answered")
        XCTAssertTrue(permissionNoticeIsUp("Location is off"),
                      "no inline location notice with Open Settings")
        XCTAssertTrue(el(AXID.mapCheckInButton).exists || waitForHome(timeout: 5), "the Map screen broke after declining")
        shot("location-denied-notice")
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
        Harness.transmit(app, for: 2.0)
        // If this device has never been asked, the press asks instead of
        // transmitting. Answer and press again.
        if let alert = anySystemAlert {
            answerSystemAlert(alert, allow: true)
            Harness.transmit(app, for: 2.0)
        }
        let receiving = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", AXID.statusPill, "Receiving from")
        ).firstMatch
        XCTAssertTrue(receiving.waitForExistence(timeout: 30), "nobody answered the push-to-talk")
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
        let pin = map.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Ridge-7' OR label BEGINSWITH 'Nova-12' "
                        + "OR label BEGINSWITH 'Ghost-21' OR label BEGINSWITH 'Wolf-3'")
        ).firstMatch
        if !pin.waitForExistence(timeout: 30) {
            attachHierarchy("no-map-pins")
            add({ let a = XCTAttachment(string: map.debugDescription)
                  a.name = "map-subtree"; a.lifetime = .keepAlways; return a }())
        }
        XCTAssertTrue(pin.exists, "no pins on the demo map")
        shot("demo-map-pins")

        app.buttons["Voice Messages"].firstMatch.tap()
        let play = el(AXID.voiceMessagePlayButton)
        XCTAssertTrue(play.waitForExistence(timeout: 20), "the demo voice-message inbox is empty")
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

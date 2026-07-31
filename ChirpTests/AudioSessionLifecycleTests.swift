import AVFoundation
import XCTest
@testable import Chirp

/// Tests for the audio-session events that take the floor away from the user
/// without the user letting go of the button: phone calls, Siri, and headsets
/// being unplugged mid-sentence.
///
/// `PTTEngine.setupCallbacks()` hangs three behaviours off `AudioSessionManager`
/// — stop transmitting on interruption, restart the engine afterwards, stop
/// transmitting when the microphone disappears. Nothing verified that those
/// hooks are ever reached, and all three are on the path where the app is
/// holding a live microphone.
///
/// These tests need no seam in `AudioSessionManager`, because the events are
/// system notifications and a test can post them. That is the whole reason
/// this file exists ahead of the audio-session ownership work: it is real
/// coverage of the interruption paths that costs no change to shipping code.
///
/// What this does **not** cover: whether iOS actually posts these notifications
/// in the situations we think it does, whether the session survives being
/// reactivated, or anything about the audio engine. Those are device
/// questions — see `REPRO-BACKGROUND-AUDIO.md`.
@MainActor
final class AudioSessionLifecycleTests: XCTestCase {

    /// `AudioSessionManager.registerForNotifications()` keeps no observer
    /// tokens and offers no way to unregister, so registering per-test would
    /// pile up observers for the life of the test process. Register once.
    private static var didRegister = false

    private var savedInterruptionBegan: (() -> Void)?
    private var savedInterruptionEnded: (() -> Void)?
    private var savedInputDeviceLost: (() -> Void)?

    override func setUp() async throws {
        try await super.setUp()

        if !Self.didRegister {
            AudioSessionManager.registerForNotifications()
            Self.didRegister = true
        }

        // The test host is the app, which wires these to a live PTTEngine at
        // launch. Put them back afterwards rather than leaving the app's audio
        // interruption handling disconnected for every later test.
        savedInterruptionBegan = AudioSessionManager.onInterruptionBegan
        savedInterruptionEnded = AudioSessionManager.onInterruptionEnded
        savedInputDeviceLost = AudioSessionManager.onInputDeviceLost

        AudioSessionManager.onInterruptionBegan = nil
        AudioSessionManager.onInterruptionEnded = nil
        AudioSessionManager.onInputDeviceLost = nil
    }

    override func tearDown() async throws {
        AudioSessionManager.onInterruptionBegan = savedInterruptionBegan
        AudioSessionManager.onInterruptionEnded = savedInterruptionEnded
        AudioSessionManager.onInputDeviceLost = savedInputDeviceLost
        try await super.tearDown()
    }

    // MARK: - Posting helpers

    /// Observers are registered with `queue: .main`, so delivery is asynchronous
    /// even when posting from the main thread. Every assertion here waits on an
    /// expectation rather than sleeping.
    private func postInterruption(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions? = nil
    ) {
        var userInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: type.rawValue
        ]
        if let options {
            userInfo[AVAudioSessionInterruptionOptionKey] = options.rawValue
        }
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: userInfo
        )
    }

    private func postRouteChange(reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }

    private func makeExpectation(_ description: String, inverted: Bool = false) -> XCTestExpectation {
        let expectation = expectation(description: description)
        expectation.isInverted = inverted
        // The app may also have registered observers, so a handler can run more
        // than once per notification. Fulfilment count is not the assertion.
        expectation.assertForOverFulfill = false
        return expectation
    }

    // MARK: - Interruption began

    func testInterruptionBeganNotifiesTheFloorHolder() async {
        let fired = makeExpectation("onInterruptionBegan called")
        AudioSessionManager.onInterruptionBegan = { fired.fulfill() }

        postInterruption(type: .began)

        await fulfillment(of: [fired], timeout: 2.0)
    }

    func testInterruptionBeganDoesNotReportAnEndedInterruption() async {
        let wrongCallback = makeExpectation("onInterruptionEnded must not fire", inverted: true)
        AudioSessionManager.onInterruptionEnded = { wrongCallback.fulfill() }
        let fired = makeExpectation("onInterruptionBegan called")
        AudioSessionManager.onInterruptionBegan = { fired.fulfill() }

        postInterruption(type: .began)

        await fulfillment(of: [fired], timeout: 2.0)
        await fulfillment(of: [wrongCallback], timeout: 0.3)
    }

    // MARK: - Interruption ended

    /// iOS sets `shouldResume` when it believes the app may take the audio
    /// hardware back. `AudioSessionManager` reactivates the session and calls
    /// back only in that case, and `PTTEngine` uses the callback to restart the
    /// engine — so this is the path that decides whether audio still works
    /// after a phone call.
    func testInterruptionEndedWithShouldResumeNotifiesTheEngine() async {
        let fired = makeExpectation("onInterruptionEnded called")
        AudioSessionManager.onInterruptionEnded = { fired.fulfill() }

        postInterruption(type: .ended, options: .shouldResume)

        await fulfillment(of: [fired], timeout: 2.0)
    }

    /// Without `shouldResume`, iOS is telling the app not to take the hardware
    /// back on its own. Calling back here would restart capture behind the
    /// user's back.
    func testInterruptionEndedWithoutShouldResumeStaysSilent() async {
        let fired = makeExpectation("onInterruptionEnded must not fire", inverted: true)
        AudioSessionManager.onInterruptionEnded = { fired.fulfill() }

        postInterruption(type: .ended, options: [])

        await fulfillment(of: [fired], timeout: 0.5)
    }

    func testInterruptionNotificationWithoutATypeIsIgnored() async {
        let began = makeExpectation("onInterruptionBegan must not fire", inverted: true)
        let ended = makeExpectation("onInterruptionEnded must not fire", inverted: true)
        AudioSessionManager.onInterruptionBegan = { began.fulfill() }
        AudioSessionManager.onInterruptionEnded = { ended.fulfill() }

        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [:]
        )

        await fulfillment(of: [began, ended], timeout: 0.5)
    }

    // MARK: - Route changes

    /// A Bluetooth headset disconnecting mid-transmission takes the microphone
    /// with it. `oldDeviceUnavailable` is the only route-change reason the app
    /// treats as losing the input.
    func testUnpluggingTheInputDeviceNotifiesTheEngine() async {
        let fired = makeExpectation("onInputDeviceLost called")
        AudioSessionManager.onInputDeviceLost = { fired.fulfill() }

        postRouteChange(reason: .oldDeviceUnavailable)

        await fulfillment(of: [fired], timeout: 2.0)
    }

    /// Plugging something in does not take the microphone away, so treating it
    /// as a loss would cut the user off mid-sentence for connecting a headset.
    func testPluggingInANewDeviceIsNotTreatedAsLosingTheInput() async {
        let fired = makeExpectation("onInputDeviceLost must not fire", inverted: true)
        AudioSessionManager.onInputDeviceLost = { fired.fulfill() }

        postRouteChange(reason: .newDeviceAvailable)

        await fulfillment(of: [fired], timeout: 0.5)
    }

    func testRoutineRouteChangesAreNotTreatedAsLosingTheInput() async {
        let fired = makeExpectation("onInputDeviceLost must not fire", inverted: true)
        AudioSessionManager.onInputDeviceLost = { fired.fulfill() }

        postRouteChange(reason: .categoryChange)
        postRouteChange(reason: .routeConfigurationChange)
        postRouteChange(reason: .override)

        await fulfillment(of: [fired], timeout: 0.5)
    }

    func testRouteChangeNotificationWithoutAReasonIsIgnored() async {
        let fired = makeExpectation("onInputDeviceLost must not fire", inverted: true)
        AudioSessionManager.onInputDeviceLost = { fired.fulfill() }

        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [:]
        )

        await fulfillment(of: [fired], timeout: 0.5)
    }
}

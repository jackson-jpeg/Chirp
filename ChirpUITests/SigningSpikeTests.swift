import XCTest

/// The cheapest possible UI test. It exists to answer one question before any
/// automation is built on top of it: can the XCTRunner app be signed and
/// installed on a physical device, given that the app itself is Manual-signed
/// against a match-managed profile?
///
/// If this fails, no amount of test-writing above it will run, so it is the
/// first thing to go green and the first thing to check when the harness
/// mysteriously stops working.
final class SigningSpikeTests: XCTestCase {

    func testAppLaunchesOnDevice() {
        let app = XCUIApplication()
        app.launch()

        // `.runningForeground` is the weakest useful assertion: the app was
        // signed, installed, launched, and did not immediately crash. Anything
        // about what is ON the screen belongs in the real tests, not here.
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "App did not reach the foreground within 30s. State: \(app.state.rawValue)"
        )
    }
}

import XCTest

/// Diagnostic, never part of the orchestrated schedule: exercises the exact
/// navigation Part B uses (Home → Messages → active channel → chat) and dumps
/// the accessibility tree wherever it ends up. Exists because SwiftUI's
/// mapping from modifiers to the AX tree keeps diverging from what the source
/// implies, and the only trustworthy answer is a runtime dump.
final class HierarchyDumpTests: XCTestCase {

    func testDumpChannelHierarchy() throws {
        let app = Harness.launchApp()
        XCTAssertTrue(Harness.reachChannel(app), "never reached the channel screen")
        Harness.allowSystemAlerts(for: 2)

        let ok = Harness.enterChannelChat(app)
        print("=== enterChannelChat:", ok)

        print("=== FINAL TREE ===")
        print(app.debugDescription)

        XCTAssertTrue(ok, "enterChannelChat failed — see tree above")
    }
}

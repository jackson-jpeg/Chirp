import XCTest

extension XCUIApplication {
    /// Make your bird's name field, found by its identifier. On iOS 27 the
    /// field no longer carries its title ("Name") as a label, only the
    /// placeholder "Your name", so `textFields["Name"]` finds nothing (run 15).
    @MainActor
    var makeBirdName: XCUIElement { textFields["makeBird.name"] }

    /// Gives the bird a name only when the field is empty. On a shared
    /// simulator the field can arrive filled (an earlier demo run saved
    /// "You"), and typing would only append.
    @MainActor
    func nameBirdIfEmpty(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let field = makeBirdName
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No name field on Make your bird", file: file, line: line)
        let value = field.value as? String ?? ""
        if value.isEmpty || value == field.placeholderValue {
            field.tap()
            field.typeText(name)
        }
    }
}

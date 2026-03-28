import XCTest
@testable import Chirp

final class PTTStateTests: XCTestCase {

    // MARK: - Equality

    func testIdleEqualsIdle() {
        XCTAssertEqual(PTTState.idle, PTTState.idle)
    }

    func testTransmittingEqualsTransmitting() {
        XCTAssertEqual(PTTState.transmitting, PTTState.transmitting)
    }

    func testDeniedEqualsDenied() {
        XCTAssertEqual(PTTState.denied, PTTState.denied)
    }

    func testReceivingWithSameValuesAreEqual() {
        let a = PTTState.receiving(speakerName: "Alice", speakerID: "alice-1")
        let b = PTTState.receiving(speakerName: "Alice", speakerID: "alice-1")
        XCTAssertEqual(a, b)
    }

    func testReceivingWithDifferentNameAreNotEqual() {
        let a = PTTState.receiving(speakerName: "Alice", speakerID: "peer-1")
        let b = PTTState.receiving(speakerName: "Bob", speakerID: "peer-1")
        XCTAssertNotEqual(a, b)
    }

    func testReceivingWithDifferentIDAreNotEqual() {
        let a = PTTState.receiving(speakerName: "Alice", speakerID: "peer-1")
        let b = PTTState.receiving(speakerName: "Alice", speakerID: "peer-2")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Cross-case inequality

    func testIdleNotEqualToTransmitting() {
        XCTAssertNotEqual(PTTState.idle, PTTState.transmitting)
    }

    func testIdleNotEqualToDenied() {
        XCTAssertNotEqual(PTTState.idle, PTTState.denied)
    }

    func testIdleNotEqualToReceiving() {
        XCTAssertNotEqual(PTTState.idle, PTTState.receiving(speakerName: "X", speakerID: "x"))
    }

    func testTransmittingNotEqualToReceiving() {
        XCTAssertNotEqual(PTTState.transmitting, PTTState.receiving(speakerName: "X", speakerID: "x"))
    }

    func testTransmittingNotEqualToDenied() {
        XCTAssertNotEqual(PTTState.transmitting, PTTState.denied)
    }

    // MARK: - Associated values

    func testReceivingExposesAssociatedValues() {
        let state = PTTState.receiving(speakerName: "Charlie", speakerID: "charlie-99")
        if case .receiving(let name, let id) = state {
            XCTAssertEqual(name, "Charlie")
            XCTAssertEqual(id, "charlie-99")
        } else {
            XCTFail("Expected .receiving state")
        }
    }
}

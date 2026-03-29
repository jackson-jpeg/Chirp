import XCTest
@testable import Chirp

final class FloorControlMessageTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Codable round-trips

    func testFloorRequestRoundTrip() throws {
        let message = FloorControlMessage.floorRequest(
            senderID: "peer-1",
            senderName: "Alice",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testFloorGrantedRoundTrip() throws {
        let message = FloorControlMessage.floorGranted(speakerID: "peer-2")
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testFloorReleaseRoundTrip() throws {
        let message = FloorControlMessage.floorRelease(senderID: "peer-3")
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testPeerJoinRoundTrip() throws {
        let message = FloorControlMessage.peerJoin(peerID: "peer-4", peerName: "Bob")
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testPeerLeaveRoundTrip() throws {
        let message = FloorControlMessage.peerLeave(peerID: "peer-5")
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    func testHeartbeatRoundTrip() throws {
        let message = FloorControlMessage.heartbeat(peerID: "peer-6", timestamp: Date(timeIntervalSince1970: 9_999_999))
        let data = try encoder.encode(message)
        let decoded = try decoder.decode(FloorControlMessage.self, from: data)
        XCTAssertEqual(decoded, message)
    }

    // MARK: - JSON encoding produces valid JSON

    func testFloorRequestEncodesToValidJSON() throws {
        let message = FloorControlMessage.floorRequest(
            senderID: "id-1",
            senderName: "Tester",
            timestamp: Date(timeIntervalSince1970: 12345)
        )
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Encoded data should be valid JSON object")
    }

    func testHeartbeatEncodesToValidJSON() throws {
        let message = FloorControlMessage.heartbeat(peerID: "hb-1", timestamp: Date(timeIntervalSince1970: 42))
        let data = try encoder.encode(message)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json, "Encoded data should be valid JSON")
    }

    // MARK: - Decode invalid JSON

    func testDecodeGarbageDataThrows() {
        let garbage = Data("not json".utf8)
        XCTAssertThrowsError(try decoder.decode(FloorControlMessage.self, from: garbage))
    }

    func testDecodeEmptyObjectThrows() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        XCTAssertThrowsError(try decoder.decode(FloorControlMessage.self, from: data))
    }

    // MARK: - Cross-case inequality

    func testDifferentCasesAreNotEqual() {
        let request = FloorControlMessage.floorRequest(senderID: "p", senderName: "P", timestamp: Date(timeIntervalSince1970: 0))
        let release = FloorControlMessage.floorRelease(senderID: "p")
        XCTAssertNotEqual(request, release)
    }
}

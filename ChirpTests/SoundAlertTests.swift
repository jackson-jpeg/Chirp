import XCTest
@testable import Chirp

final class SoundAlertTests: XCTestCase {

    // MARK: - Helpers

    private func makeAlert(
        soundClass: SoundAlert.SoundClass = .gunshot,
        latitude: Double? = 40.7128,
        longitude: Double? = -74.0060
    ) -> SoundAlert {
        SoundAlert(
            id: UUID(),
            senderID: "peer-123",
            senderName: "TestUser",
            soundClass: soundClass,
            confidence: 0.95,
            latitude: latitude,
            longitude: longitude,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - SoundAlert Creation

    func testSoundAlertCreationAllClasses() {
        for soundClass in SoundAlert.SoundClass.allCases {
            let alert = makeAlert(soundClass: soundClass)
            XCTAssertEqual(alert.soundClass, soundClass)
            XCTAssertFalse(soundClass.displayName.isEmpty, "\(soundClass) has empty displayName")
            XCTAssertFalse(soundClass.icon.isEmpty, "\(soundClass) has empty icon")
        }
    }

    // MARK: - Wire Round-Trip

    func testSoundAlertWireRoundTrip() throws {
        let alert = makeAlert(soundClass: .fireAlarm, latitude: 34.0522, longitude: -118.2437)
        let wireData = try alert.wirePayload()

        // Verify SND! prefix
        let prefix = Data(SoundAlert.magicPrefix)
        XCTAssertEqual(wireData.prefix(prefix.count), prefix)

        // Decode back
        let decoded = SoundAlert.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.senderID, "peer-123")
        XCTAssertEqual(decoded?.senderName, "TestUser")
        XCTAssertEqual(decoded?.soundClass, .fireAlarm)
        XCTAssertEqual(decoded?.confidence, 0.95)
        XCTAssertEqual(decoded?.latitude, 34.0522)
        XCTAssertEqual(decoded?.longitude, -118.2437)
    }

    func testSoundAlertWireNilCoordinates() throws {
        let alert = makeAlert(soundClass: .scream, latitude: nil, longitude: nil)
        let wireData = try alert.wirePayload()

        let decoded = SoundAlert.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertNil(decoded?.latitude)
        XCTAssertNil(decoded?.longitude)
        XCTAssertEqual(decoded?.soundClass, .scream)
    }

    // MARK: - SoundClass Raw Values

    func testSoundClassRawValues() {
        XCTAssertEqual(SoundAlert.SoundClass.glassBreaking.rawValue, "glass_breaking")
        XCTAssertEqual(SoundAlert.SoundClass.fireAlarm.rawValue, "fire_alarm")
        XCTAssertEqual(SoundAlert.SoundClass.smokeDetector.rawValue, "smoke_detector")
        // Verify the simple ones too
        XCTAssertEqual(SoundAlert.SoundClass.gunshot.rawValue, "gunshot")
        XCTAssertEqual(SoundAlert.SoundClass.scream.rawValue, "scream")
        XCTAssertEqual(SoundAlert.SoundClass.siren.rawValue, "siren")
        XCTAssertEqual(SoundAlert.SoundClass.explosion.rawValue, "explosion")
    }

    // MARK: - SND Magic Priority

    func testSNDMagicPriority() {
        let payload = Data([0x53, 0x4E, 0x44, 0x21, 0x00, 0x00])
        let priority = MeshPacket.inferPriority(type: .control, payload: payload)
        XCTAssertEqual(priority, .high)
    }

    // MARK: - All SoundClass Cases Have Icons

    func testAllSoundClassCasesHaveIcons() {
        for soundClass in SoundAlert.SoundClass.allCases {
            let icon = soundClass.icon
            XCTAssertFalse(icon.isEmpty, "\(soundClass) has empty icon")
            // Verify it looks like an SF Symbol name (contains a dot or known pattern)
            XCTAssertTrue(
                icon.contains(".") || icon.count > 2,
                "\(soundClass) icon '\(icon)' does not look like a valid SF Symbol name"
            )
        }
    }

    // MARK: - All SoundClass Cases Have Display Names

    func testAllSoundClassCasesHaveDisplayNames() {
        for soundClass in SoundAlert.SoundClass.allCases {
            let name = soundClass.displayName
            XCTAssertFalse(name.isEmpty, "\(soundClass) has empty displayName")
        }
    }
}

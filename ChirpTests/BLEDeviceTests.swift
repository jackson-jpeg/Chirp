import XCTest
@testable import Chirp

final class BLEDeviceTests: XCTestCase {

    // MARK: - Helpers

    private func makeDevice(
        name: String? = nil,
        rssi: Int = -60,
        manufacturerID: UInt16? = nil,
        category: BLEDevice.DeviceCategory = .unknown,
        threatLevel: BLEDevice.ThreatLevel = .none
    ) -> BLEDevice {
        BLEDevice(
            id: UUID(),
            peripheralID: "peripheral-\(UUID().uuidString.prefix(8))",
            name: name,
            rssi: rssi,
            manufacturerID: manufacturerID,
            manufacturerName: nil,
            category: category,
            threatLevel: threatLevel,
            firstSeen: Date(),
            lastSeen: Date(),
            advertisedServices: []
        )
    }

    // MARK: - BLEDevice Creation

    func testBLEDeviceCreation() {
        let id = UUID()
        let now = Date()
        let device = BLEDevice(
            id: id,
            peripheralID: "test-peripheral",
            name: "My Device",
            rssi: -55,
            manufacturerID: 0x004C,
            manufacturerName: "Apple",
            category: .phone,
            threatLevel: .none,
            firstSeen: now,
            lastSeen: now,
            advertisedServices: ["180A", "180F"]
        )

        XCTAssertEqual(device.id, id)
        XCTAssertEqual(device.peripheralID, "test-peripheral")
        XCTAssertEqual(device.name, "My Device")
        XCTAssertEqual(device.rssi, -55)
        XCTAssertEqual(device.manufacturerID, 0x004C)
        XCTAssertEqual(device.manufacturerName, "Apple")
        XCTAssertEqual(device.category, .phone)
        XCTAssertEqual(device.threatLevel, .none)
        XCTAssertEqual(device.firstSeen, now)
        XCTAssertEqual(device.lastSeen, now)
        XCTAssertEqual(device.advertisedServices, ["180A", "180F"])
    }

    // MARK: - ThreatLevel Ordering

    func testThreatLevelOrdering() {
        XCTAssertTrue(BLEDevice.ThreatLevel.none < .low)
        XCTAssertTrue(BLEDevice.ThreatLevel.low < .medium)
        XCTAssertTrue(BLEDevice.ThreatLevel.medium < .high)
        XCTAssertTrue(BLEDevice.ThreatLevel.none < .high)
    }

    // MARK: - DeviceCategory Raw Values

    func testDeviceCategoryRawValues() {
        XCTAssertEqual(BLEDevice.DeviceCategory.phone.rawValue, "phone")
        XCTAssertEqual(BLEDevice.DeviceCategory.tablet.rawValue, "tablet")
        XCTAssertEqual(BLEDevice.DeviceCategory.computer.rawValue, "computer")
        XCTAssertEqual(BLEDevice.DeviceCategory.wearable.rawValue, "wearable")
        XCTAssertEqual(BLEDevice.DeviceCategory.headphones.rawValue, "headphones")
        XCTAssertEqual(BLEDevice.DeviceCategory.speaker.rawValue, "speaker")
        XCTAssertEqual(BLEDevice.DeviceCategory.tracker.rawValue, "tracker")
        XCTAssertEqual(BLEDevice.DeviceCategory.camera.rawValue, "camera")
        XCTAssertEqual(BLEDevice.DeviceCategory.tv.rawValue, "tv")
        XCTAssertEqual(BLEDevice.DeviceCategory.iot.rawValue, "iot")
        XCTAssertEqual(BLEDevice.DeviceCategory.infrastructure.rawValue, "infrastructure")
        XCTAssertEqual(BLEDevice.DeviceCategory.unknown.rawValue, "unknown")

        // Verify all cases have non-empty raw values for Codable
        for category in BLEDevice.DeviceCategory.allCases {
            XCTAssertFalse(category.rawValue.isEmpty, "\(category) has empty raw value")
        }
    }

    // MARK: - BLEManufacturerDB Lookups

    func testManufacturerDBLookupApple() {
        let entry = BLEManufacturerDB.lookup(0x004C)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "Apple")
        XCTAssertEqual(entry?.defaultCategory, .phone)
        XCTAssertEqual(entry?.isSurveillance, false)
    }

    func testManufacturerDBLookupHikvision() {
        let entry = BLEManufacturerDB.lookup(0x0969)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "Hikvision")
        XCTAssertEqual(entry?.defaultCategory, .camera)
        XCTAssertTrue(entry?.isSurveillance == true)
    }

    func testManufacturerDBLookupTile() {
        let entry = BLEManufacturerDB.lookup(0x0215)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "Tile")
        XCTAssertEqual(entry?.defaultCategory, .tracker)
    }

    func testManufacturerDBLookupUnknown() {
        let entry = BLEManufacturerDB.lookup(0xFFFF)
        XCTAssertNil(entry)
    }

    // MARK: - Threat Assessment

    func testThreatAssessmentSurveillanceCamera() {
        let device = makeDevice(manufacturerID: 0x0969, category: .camera)
        let threat = BLEManufacturerDB.assessThreat(device: device)
        XCTAssertEqual(threat, .high)
    }

    func testThreatAssessmentInfrastructure() {
        let device = makeDevice(manufacturerID: 0x015D, category: .infrastructure)
        let threat = BLEManufacturerDB.assessThreat(device: device)
        XCTAssertEqual(threat, .medium)
    }

    func testThreatAssessmentKnownBrand() {
        let device = makeDevice(manufacturerID: 0x004C, category: .phone)
        let threat = BLEManufacturerDB.assessThreat(device: device)
        XCTAssertEqual(threat, .none)
    }

    func testThreatAssessmentUnknownStrongSignal() {
        let device = makeDevice(name: nil, rssi: -30, manufacturerID: 0xAAAA)
        let threat = BLEManufacturerDB.assessThreat(device: device)
        XCTAssertEqual(threat, .medium)
    }

    func testThreatAssessmentUnknownWeakSignal() {
        let device = makeDevice(name: nil, rssi: -85, manufacturerID: nil)
        let threat = BLEManufacturerDB.assessThreat(device: device)
        XCTAssertEqual(threat, .low)
    }

    // MARK: - MeshScanReport Round-Trip

    func testMeshScanReportWireRoundTrip() throws {
        let device = makeDevice(name: "Test Phone", rssi: -50, manufacturerID: 0x004C, category: .phone)
        let report = MeshScanReport(
            senderID: "peer-abc",
            senderName: "Alice",
            devices: [device],
            latitude: 40.7128,
            longitude: -74.0060,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let wireData = try report.wirePayload()

        // Verify SCN! prefix
        let prefix = Data(MeshScanReport.magicPrefix)
        XCTAssertEqual(wireData.prefix(prefix.count), prefix)

        // Decode back
        let decoded = MeshScanReport.from(payload: wireData)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.senderID, "peer-abc")
        XCTAssertEqual(decoded?.senderName, "Alice")
        XCTAssertEqual(decoded?.devices.count, 1)
        XCTAssertEqual(decoded?.devices.first?.name, "Test Phone")
        XCTAssertEqual(decoded?.latitude, 40.7128)
        XCTAssertEqual(decoded?.longitude, -74.0060)
    }

    // MARK: - SCN Magic Priority

    func testSCNMagicPriority() {
        // SCN! prefix: 0x53 0x43 0x4E 0x21
        let payload = Data([0x53, 0x43, 0x4E, 0x21, 0x00, 0x00])
        let priority = MeshPacket.inferPriority(type: .control, payload: payload)
        // SCN! is not explicitly handled in inferPriority, so it falls through to generic control = .high
        XCTAssertEqual(priority, .high)
    }
}

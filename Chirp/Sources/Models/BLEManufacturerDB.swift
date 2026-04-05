import Foundation

/// Static database of Bluetooth SIG company identifiers and device awareness logic.
enum BLEManufacturerDB {

    // MARK: - Manufacturer Entry

    struct Entry: Sendable {
        let name: String
        let defaultCategory: BLEDevice.DeviceCategory
        let isSurveillance: Bool

        init(_ name: String, _ category: BLEDevice.DeviceCategory, surveillance: Bool = false) {
            self.name = name
            self.defaultCategory = category
            self.isSurveillance = surveillance
        }
    }

    // MARK: - Company ID Table (~60 entries)

    /// Bluetooth SIG company identifiers (little-endian UInt16).
    static let manufacturers: [UInt16: Entry] = [
        // Apple ecosystem
        0x004C: Entry("Apple", .phone),

        // Google / Android
        0x00E0: Entry("Google", .phone),

        // Samsung
        0x0075: Entry("Samsung", .phone),

        // Microsoft
        0x0006: Entry("Microsoft", .computer),

        // Sony
        0x012D: Entry("Sony", .headphones),

        // Bose
        0x009E: Entry("Bose", .headphones),

        // Harman / JBL
        0x0087: Entry("Harman/JBL", .speaker),

        // LG Electronics
        0x00E7: Entry("LG Electronics", .phone),

        // Huawei
        0x027D: Entry("Huawei", .phone),

        // Xiaomi
        0x038F: Entry("Xiaomi", .phone),

        // OnePlus / BBK
        0x0489: Entry("OnePlus", .phone),

        // Motorola
        0x0080: Entry("Motorola", .phone),

        // Nokia
        0x0001: Entry("Nokia", .phone),

        // Intel
        0x0002: Entry("Intel", .computer),

        // Qualcomm
        0x000A: Entry("Qualcomm", .unknown),

        // Broadcom
        0x000F: Entry("Broadcom", .unknown),

        // Texas Instruments
        0x000D: Entry("Texas Instruments", .iot),

        // Nordic Semiconductor
        0x0059: Entry("Nordic Semiconductor", .iot),

        // Realtek
        0x005D: Entry("Realtek", .unknown),

        // MediaTek
        0x0046: Entry("MediaTek", .unknown),

        // --- Audio ---

        // Beats (Apple subsidiary)
        0x0154: Entry("Beats", .headphones),

        // Jabra / GN Audio
        0x0067: Entry("Jabra", .headphones),

        // Sennheiser
        0x00D2: Entry("Sennheiser", .headphones),

        // Bang & Olufsen
        0x0057: Entry("Bang & Olufsen", .speaker),

        // Sonos
        0x028A: Entry("Sonos", .speaker),

        // Skullcandy
        0x0239: Entry("Skullcandy", .headphones),

        // Plantronics / Poly
        0x0055: Entry("Plantronics", .headphones),

        // Audio-Technica
        0x0315: Entry("Audio-Technica", .headphones),

        // --- Wearables ---

        // Fitbit
        0x0251: Entry("Fitbit", .wearable),

        // Garmin
        0x0078: Entry("Garmin", .wearable),

        // Amazfit / Zepp
        0x0424: Entry("Amazfit", .wearable),

        // Oura
        0x04F7: Entry("Oura", .wearable),

        // Whoop
        0x0553: Entry("Whoop", .wearable),

        // --- Trackers ---

        // Tile
        0x0215: Entry("Tile", .tracker),

        // Chipolo
        0x0317: Entry("Chipolo", .tracker),

        // --- TV / Streaming ---

        // Roku
        0x0232: Entry("Roku", .tv),

        // Amazon (Fire TV, Ring, etc.)
        0x0171: Entry("Amazon", .tv),

        // --- IoT / Smart Home ---

        // Nest / Google Home
        0x02E5: Entry("Google Nest", .iot),

        // Philips / Signify (Hue)
        0x0025: Entry("Philips", .iot),

        // IKEA
        0x02A3: Entry("IKEA", .iot),

        // Dyson
        0x034E: Entry("Dyson", .iot),

        // iRobot
        0x0312: Entry("iRobot", .iot),

        // Tuya
        0x07D0: Entry("Tuya", .iot),

        // --- Security Cameras ---

        // Hikvision
        0x0969: Entry("Hikvision", .camera, surveillance: true),

        // Dahua
        0x0835: Entry("Dahua", .camera, surveillance: true),

        // Axis Communications
        0x0131: Entry("Axis Communications", .camera, surveillance: true),

        // Hanwha Techwin (formerly Samsung Techwin)
        0x0780: Entry("Hanwha Techwin", .camera, surveillance: true),

        // Vivotek
        0x0891: Entry("Vivotek", .camera, surveillance: true),

        // Lorex
        0x0A10: Entry("Lorex", .camera, surveillance: true),

        // --- Infrastructure / Beacons (medium concern) ---

        // RetailNext (retail analytics)
        0x0672: Entry("RetailNext", .infrastructure, surveillance: true),

        // Estimote (beacons)
        0x015D: Entry("Estimote", .infrastructure),

        // Kontakt.io (beacons)
        0x01AE: Entry("Kontakt.io", .infrastructure),

        // Radius Networks
        0x0177: Entry("Radius Networks", .infrastructure),

        // Cisco
        0x000B: Entry("Cisco", .infrastructure),

        // Aruba / HPE
        0x0139: Entry("Aruba Networks", .infrastructure),

        // Ruckus / CommScope
        0x020F: Entry("Ruckus", .infrastructure),
    ]

    // MARK: - Lookup

    /// Look up a manufacturer by Bluetooth SIG company identifier.
    static func lookup(_ companyID: UInt16) -> Entry? {
        manufacturers[companyID]
    }

    // MARK: - Awareness Assessment

    /// Assess the awareness level of a detected BLE device.
    static func assessThreat(device: BLEDevice) -> BLEDevice.ThreatLevel {
        // Known security camera manufacturer → high
        if let mfgID = device.manufacturerID, let entry = manufacturers[mfgID] {
            if entry.isSurveillance {
                return .high
            }
            // Infrastructure beacons → medium
            if entry.defaultCategory == .infrastructure {
                return .medium
            }
            // Known consumer brand → safe
            return .none
        }

        // Unknown manufacturer with strong signal and no name → notable
        if device.manufacturerID != nil && device.name == nil && device.rssi > -40 {
            return .medium
        }

        // Completely unknown device nearby with strong RSSI
        if device.manufacturerID == nil && device.name == nil && device.rssi > -40 {
            return .medium
        }

        // Everything else → low (unknown but not alarming)
        return .low
    }
}

import CoreBluetooth
import Foundation
import Observation
import OSLog

/// Scans for nearby Bluetooth Low Energy devices and categorizes them.
///
/// Uses ``CBCentralManager`` to discover BLE peripherals, resolves manufacturer
/// data via ``BLEManufacturerDB``, and exposes a sorted list of detected devices.
/// Scan results can be shared across the mesh via ``MeshScanReport``.
@Observable
@MainActor
final class BLEScanner: NSObject {

    // MARK: - Public State

    private(set) var isScanning: Bool = false
    private(set) var discoveredDevices: [BLEDevice] = []
    private(set) var meshReports: [MeshScanReport] = []

    /// Current Bluetooth state for UI feedback.
    enum BluetoothState: String, Sendable {
        case unknown = "Checking Bluetooth..."
        case poweredOn = "Bluetooth ready"
        case poweredOff = "Bluetooth is off"
        case unauthorized = "Bluetooth permission denied"
        case unsupported = "Bluetooth not available"
    }

    private(set) var bluetoothState: BluetoothState = .unknown

    /// Devices with medium or high awareness level.
    var threatDevices: [BLEDevice] {
        discoveredDevices.filter { $0.threatLevel >= .medium }
    }

    // MARK: - Callbacks

    /// Transport hook: `(payload, channelID)`.
    /// The caller wraps the payload in a ``MeshPacket`` and sends it to peers.
    var onSendPacket: ((Data, String) -> Void)?

    // MARK: - Private State

    private var centralManager: CBCentralManager?
    private var scanTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var sortDebounceTask: Task<Void, Never>?
    private var deviceMap: [String: BLEDevice] = [:]

    private let logger = Logger(subsystem: Constants.subsystem, category: "BLEScanner")

    /// Scan window duration in seconds.
    private let scanDuration: TimeInterval = 10
    /// Rest period between scan windows in seconds.
    private let restDuration: TimeInterval = 5

    // MARK: - Init

    override init() {
        super.init()
    }

    // MARK: - Scanning Control

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true

        // Create central manager if needed — triggers Bluetooth permission prompt
        if centralManager == nil {
            // CBCentralManager delegate callbacks are nonisolated;
            // we dispatch to MainActor inside each callback.
            centralManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: true]
            )
        } else {
            beginScanWindow()
        }

        logger.info("BLE scanning started")
    }

    func stopScanning() {
        guard isScanning else { return }
        isScanning = false

        centralManager?.stopScan()
        scanTask?.cancel()
        scanTask = nil
        restTask?.cancel()
        restTask = nil

        logger.info("BLE scanning stopped")
    }

    func clearDevices() {
        deviceMap.removeAll()
        discoveredDevices.removeAll()
        meshReports.removeAll()
    }

    // MARK: - Scan Window Management

    private func beginScanWindow() {
        guard isScanning, centralManager?.state == .poweredOn else { return }

        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.scanDuration ?? 5))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.endScanWindow()
            }
        }
    }

    private func endScanWindow() {
        centralManager?.stopScan()
        scanTask?.cancel()
        scanTask = nil

        guard isScanning else { return }

        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.restDuration ?? 10))
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.beginScanWindow()
            }
        }
    }

    // MARK: - Device Processing

    private func processDiscoveryParsed(
        peripheralID: String,
        name: String?,
        rssi: Int,
        companyID: UInt16?,
        serviceUUIDs: [String]
    ) {
        let now = Date()
        let mfgEntry = companyID.flatMap { BLEManufacturerDB.lookup($0) }

        if var existing = deviceMap[peripheralID] {
            // Update existing device
            existing.rssi = rssi
            existing.lastSeen = now
            if let name, existing.name == nil {
                existing.name = name
            }
            if let companyID, existing.manufacturerID == nil {
                existing.manufacturerID = companyID
                existing.manufacturerName = mfgEntry?.name
                existing.category = mfgEntry?.defaultCategory ?? .unknown
            }
            // Re-assess threat with updated info
            existing.threatLevel = BLEManufacturerDB.assessThreat(device: existing)
            deviceMap[peripheralID] = existing
        } else {
            // New device
            let category = mfgEntry?.defaultCategory ?? .unknown
            var device = BLEDevice(
                id: UUID(),
                peripheralID: peripheralID,
                name: name,
                rssi: rssi,
                manufacturerID: companyID,
                manufacturerName: mfgEntry?.name,
                category: category,
                threatLevel: .low,
                firstSeen: now,
                lastSeen: now,
                advertisedServices: serviceUUIDs
            )
            device.threatLevel = BLEManufacturerDB.assessThreat(device: device)
            deviceMap[peripheralID] = device
        }

        // Debounce sort — BLE callbacks fire rapidly, sorting every time is wasteful
        scheduleSortUpdate()
    }

    /// Debounced sort — coalesces rapid BLE discovery callbacks into one sort per 0.5s.
    private func scheduleSortUpdate() {
        sortDebounceTask?.cancel()
        sortDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.discoveredDevices = self.deviceMap.values.sorted { a, b in
                if a.threatLevel != b.threatLevel { return a.threatLevel > b.threatLevel }
                return a.rssi > b.rssi
            }
        }
    }

    // MARK: - Mesh Sharing

    /// Share current scan results with other mesh nodes.
    func shareScanWithMesh(
        senderID: String,
        senderName: String,
        latitude: Double?,
        longitude: Double?
    ) {
        let report = MeshScanReport(
            senderID: senderID,
            senderName: senderName,
            devices: discoveredDevices,
            latitude: latitude,
            longitude: longitude,
            timestamp: Date()
        )

        do {
            let payload = try report.wirePayload()
            onSendPacket?(payload, "") // Broadcast to all channels
            logger.info("Shared scan report with mesh — \(self.discoveredDevices.count) devices")
        } catch {
            logger.error("Failed to encode scan report: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handle an incoming mesh scan report from another node.
    func handleMeshScanReport(_ payload: Data) {
        guard let report = MeshScanReport.from(payload: payload) else { return }

        // Deduplicate by sender — keep latest report per sender
        meshReports.removeAll { $0.senderID == report.senderID }
        meshReports.append(report)

        // Merge remote devices into our discovered list (mark as remote)
        for device in report.devices where device.threatLevel >= .medium {
            if deviceMap[device.peripheralID] == nil {
                deviceMap[device.peripheralID] = device
            }
        }

        // Debounced sort
        scheduleSortUpdate()

        logger.info("Received mesh scan report from \(report.senderName, privacy: .public) — \(report.devices.count) devices")
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScanner: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .poweredOn:
                self.bluetoothState = .poweredOn
                self.logger.info("Bluetooth powered on")
                if self.isScanning {
                    self.beginScanWindow()
                }
            case .poweredOff:
                self.bluetoothState = .poweredOff
                self.logger.warning("Bluetooth powered off")
                self.stopScanning()
            case .unauthorized:
                self.bluetoothState = .unauthorized
                self.logger.warning("Bluetooth unauthorized")
                self.stopScanning()
            case .unsupported:
                self.bluetoothState = .unsupported
                self.logger.error("Bluetooth unsupported on this device")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let peripheralID = peripheral.identifier.uuidString
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let rssi = RSSI.intValue

        // Ignore extremely weak signals
        guard rssi > -100 && rssi < 0 else { return }

        // Extract manufacturer data before crossing isolation boundary
        var companyID: UInt16?
        if let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           mfgData.count >= 2 {
            companyID = UInt16(mfgData[0]) | (UInt16(mfgData[1]) << 8)
        }
        var serviceUUIDs: [String] = []
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUUIDs = uuids.map { $0.uuidString }
        }

        Task { @MainActor [weak self] in
            self?.processDiscoveryParsed(
                peripheralID: peripheralID,
                name: name,
                rssi: rssi,
                companyID: companyID,
                serviceUUIDs: serviceUUIDs
            )
        }
    }
}

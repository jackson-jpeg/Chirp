import ChirpCore
@preconcurrency import CoreBluetooth
import Foundation

/// The locked-phone link (Jackson's option 1, docs/audit/BACKGROUND.md):
/// Bluetooth LE, which iOS keeps running in the background with the
/// `bluetooth-central` and `bluetooth-peripheral` modes. It carries only what
/// `Bluetooth.carries` allows (texts, acks, roll call, help, meet-ups, pings,
/// floor requests, presence and membership), never voice.
///
/// Every phone is both sides: a peripheral advertising one service with one
/// characteristic, and a central scanning for that service by UUID (the only
/// way iOS finds a backgrounded peripheral). Two phones can therefore be
/// linked twice; the router drops the duplicate copy.
///
/// - Started by `Transport.start()`, so Bluetooth is asked on the same first
///   tap as Local Network (5.1.1(iv)), never at launch.
/// - Not stopped on background: that is its whole job. `stop()` is for Demo
///   Mode and for turning the radio off.
/// - Packets pass `SendGate` both ways, like the Network transport.
/// - State restoration IDs, so iOS can relaunch the app for a packet after it
///   ended it in the background.
///
/// Proving it needs two iPhones (BACKGROUND.md section 4, B3 to B5): the
/// simulator has no Bluetooth.
@MainActor
final class BluetoothLink: NSObject {
    /// Every packet that arrives. The link is named by the packet's origin:
    /// Bluetooth gives no PeerID for the phone on the other end.
    var onPacket: ((Packet, PeerID) -> Void)?
    var sandboxed = false
    private(set) var running = false

    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var characteristic: CBMutableCharacteristic?

    /// Peripherals we found or are connected to, and their packet characteristic.
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var remoteCharacteristic: [UUID: CBCharacteristic] = [:]
    /// Centrals subscribed to our characteristic.
    private var subscribers: [UUID: CBCentral] = [:]

    private var reassemblers: [UUID: Reassembler] = [:]
    private var nextID: UInt16 = 0
    /// Fragments waiting because the radio said "not now".
    private var toCentrals: [Data] = []
    private var toPeripherals: [UUID: [Data]] = [:]
    /// Caps on what waits, so a link that never drains cannot grow memory.
    private static let maxWaiting = 256

    private var serviceUUID: CBUUID { CBUUID(string: Bluetooth.serviceUUID) }
    private var packetUUID: CBUUID { CBUUID(string: Bluetooth.packetUUID) }

    // MARK: Start and stop

    func start() {
        guard !running, !sandboxed else { return }
        running = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionRestoreIdentifierKey: Bluetooth.centralRestoreID])
        }
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: .main,
                                                    options: [CBPeripheralManagerOptionRestoreIdentifierKey: Bluetooth.peripheralRestoreID])
        }
        // Already powered on (a restart): go now; otherwise the state callbacks do.
        if central?.state == .poweredOn { scan() }
        if peripheralManager?.state == .poweredOn { advertise() }
    }

    func stop() {
        guard running else { return }
        running = false
        central?.stopScan()
        for p in peripherals.values { central?.cancelPeripheralConnection(p) }
        peripherals.removeAll()
        remoteCharacteristic.removeAll()
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        characteristic = nil
        subscribers.removeAll()
        reassemblers.removeAll()
        toCentrals.removeAll()
        toPeripherals.removeAll()
    }

    // MARK: Sending

    /// To every phone on Bluetooth, if the packet is one Bluetooth carries.
    func send(_ packet: Packet) {
        guard running, Bluetooth.carries(packet), SendGate.allowsSend(packet, sandboxed: sandboxed) else { return }
        let wire = packet.encode()
        let id = nextID
        nextID &+= 1

        if let characteristic, let manager = peripheralManager, !subscribers.isEmpty {
            let mtu = subscribers.values.map(\.maximumUpdateValueLength).min() ?? Fragments.minWrite
            let parts = Fragments.split(wire, id: id, maxWrite: mtu)
            if toCentrals.isEmpty {
                var sent = 0
                for part in parts {
                    guard manager.updateValue(part, for: characteristic, onSubscribedCentrals: nil) else { break }
                    sent += 1
                }
                enqueue(Array(parts.dropFirst(sent)), into: &toCentrals)
            } else {
                enqueue(parts, into: &toCentrals)
            }
        }

        for (uuid, peripheral) in peripherals {
            guard let c = remoteCharacteristic[uuid], peripheral.state == .connected else { continue }
            let parts = Fragments.split(wire, id: id, maxWrite: peripheral.maximumWriteValueLength(for: .withoutResponse))
            var waiting = toPeripherals[uuid, default: []]
            enqueue(parts, into: &waiting)
            toPeripherals[uuid] = waiting
            drain(peripheral, characteristic: c)
        }
    }

    private func enqueue(_ parts: [Data], into queue: inout [Data]) {
        queue.append(contentsOf: parts)
        if queue.count > Self.maxWaiting { queue.removeFirst(queue.count - Self.maxWaiting) }
    }

    private func drainCentrals() {
        guard let characteristic, let manager = peripheralManager else { return }
        while let next = toCentrals.first {
            guard manager.updateValue(next, for: characteristic, onSubscribedCentrals: nil) else { return }
            toCentrals.removeFirst()
        }
    }

    private func drain(_ peripheral: CBPeripheral, characteristic c: CBCharacteristic) {
        let uuid = peripheral.identifier
        while var waiting = toPeripherals[uuid], let next = waiting.first, peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(next, for: c, type: .withoutResponse)
            waiting.removeFirst()
            toPeripherals[uuid] = waiting
        }
    }

    // MARK: Receiving

    private func received(_ fragment: Data, from link: UUID) {
        var r = reassemblers[link, default: Reassembler()]
        let whole = r.add(fragment, now: .now)
        reassemblers[link] = r
        guard let whole, let packet = Packet.decode(whole), Bluetooth.carries(packet),
              SendGate.allowsReceive(packet, sandboxed: sandboxed) else { return }
        onPacket?(packet, packet.origin)
    }

    // MARK: Peripheral side

    private func advertise() {
        guard running, let manager = peripheralManager else { return }
        if characteristic == nil {
            let c = CBMutableCharacteristic(type: packetUUID, properties: [.writeWithoutResponse, .notify],
                                            value: nil, permissions: [.writeable])
            let service = CBMutableService(type: serviceUUID, primary: true)
            service.characteristics = [c]
            manager.add(service)
            characteristic = c
        }
        if !manager.isAdvertising {
            manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
        }
    }

    // MARK: Central side

    private func scan() {
        guard running, let central else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func adopt(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
    }

    private func dropPeripheral(_ peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        remoteCharacteristic[uuid] = nil
        toPeripherals[uuid] = nil
        reassemblers[uuid] = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn { scan() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        MainActor.assumeIsolated {
            // iOS relaunched the app for Bluetooth: it was running before.
            running = true
            for p in restored { adopt(p) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard running, peripherals[peripheral.identifier] == nil else { return }
            adopt(peripheral)
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            dropPeripheral(peripheral)
            peripherals[peripheral.identifier] = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            dropPeripheral(peripheral)
            // A pending connect does not time out, in the background too: the
            // link comes back by itself when the phone is in range again.
            if running { central.connect(peripheral) } else { peripherals[peripheral.identifier] = nil }
        }
    }
}

// MARK: - CBPeripheralDelegate (we are the central)

extension BluetoothLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
            peripheral.discoverCharacteristics([packetUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let c = service.characteristics?.first(where: { $0.uuid == packetUUID }) else { return }
            remoteCharacteristic[peripheral.identifier] = c
            peripheral.setNotifyValue(true, for: c)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let value = characteristic.value
        MainActor.assumeIsolated {
            guard error == nil, let value else { return }
            received(value, from: peripheral.identifier)
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard let c = remoteCharacteristic[peripheral.identifier] else { return }
            drain(peripheral, characteristic: c)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        MainActor.assumeIsolated {
            dropPeripheral(peripheral)
            peripheral.discoverServices([serviceUUID])
        }
    }
}

// MARK: - CBPeripheralManagerDelegate (we are the peripheral)

extension BluetoothLink: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            if peripheral.state == .poweredOn { advertise() } else { characteristic = nil; subscribers.removeAll() }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
        MainActor.assumeIsolated {
            running = true
            characteristic = services.first { $0.uuid == serviceUUID }?
                .characteristics?.first { $0.uuid == packetUUID } as? CBMutableCharacteristic
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscribers[central.identifier] = central
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            subscribers[central.identifier] = nil
            reassemblers[central.identifier] = nil
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let writes = requests.compactMap { r in r.value.map { (r.central.identifier, $0) } }
        MainActor.assumeIsolated {
            for (central, value) in writes { received(value, from: central) }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { drainCentrals() }
    }
}

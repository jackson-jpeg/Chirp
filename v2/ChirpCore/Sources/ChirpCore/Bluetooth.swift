import Foundation

// The locked-phone link (Jackson's option 1, docs/audit/BACKGROUND.md):
// talking runs on the Network framework transport with the app open; texts,
// roll call, help, pings and "someone is talking" reach a locked phone over
// Bluetooth LE, which iOS keeps running in the background with the
// `bluetooth-central` and `bluetooth-peripheral` modes. Never `audio` (2.5.4).
//
// Held here so each rule has a test:
// - Only small, signed, text-like kinds go over Bluetooth. Voice and photos
//   never do: a BLE link moves a few kilobytes a second at best.
// - A packet is cut into fragments that fit one write (the link's MTU) and put
//   back together on the other side, with every limit bounded: packet size,
//   fragments per packet, packets in flight per link, and time.
// - What arrives while the phone is locked becomes a notification in plain
//   words (`LockedAlert`), at most one "is talking" per person a minute.

public enum Bluetooth {
    /// The GATT service every ChirpChirps phone advertises and scans for. iOS
    /// only finds a backgrounded peripheral when the central scans for its
    /// service UUID by name, so this one never changes.
    public static let serviceUUID = "8B7E2C40-4A1D-4C55-9C1E-6A0B2D3C1F01"
    /// One characteristic: the central writes packets to it, the peripheral
    /// sends packets as notifications on it.
    public static let packetUUID = "8B7E2C40-4A1D-4C55-9C1E-6A0B2D3C1F02"
    /// For iOS to bring the managers back after it ends the app in the background.
    public static let centralRestoreID = "chirpchirps.central"
    public static let peripheralRestoreID = "chirpchirps.peripheral"

    /// What goes over Bluetooth. Presence and member, so a phone that wakes
    /// knows whose signature it is checking and who its friends are; the rest
    /// is what a locked phone should hear about.
    public static let carried: Set<PacketKind> = [.presence, .member, .text, .ack, .rollCall, .help, .meetup, .ping, .floor]
    /// The largest packet sent over Bluetooth, header included.
    public static let maxPacket = 1024

    public static func carries(_ packet: Packet) -> Bool {
        carried.contains(packet.kind) && Packet.headerSize + packet.payload.count <= maxPacket
    }
}

// MARK: - Fragments

/// One fragment: [packet id:2][index:1][count:1][bytes]. The id is the
/// sender's, per link; it wraps.
public enum Fragments {
    public static let headerSize = 4
    /// The smallest write iOS guarantees (23-byte ATT MTU minus 3) leaves 16
    /// bytes after our header; anything smaller cannot carry a packet.
    public static let minWrite = 20

    /// The packet's bytes in fragments of at most `maxWrite` bytes each. Empty
    /// when the packet is too big for Bluetooth or the write too small.
    public static func split(_ bytes: Data, id: UInt16, maxWrite: Int) -> [Data] {
        guard maxWrite >= minWrite, !bytes.isEmpty, bytes.count <= Bluetooth.maxPacket else { return [] }
        let room = maxWrite - headerSize
        let count = (bytes.count + room - 1) / room
        guard count <= Int(UInt8.max) else { return [] }
        return (0..<count).map { i in
            var d = Data(capacity: maxWrite)
            d.appendBigEndian(id)
            d.append(UInt8(i))
            d.append(UInt8(count))
            let start = bytes.startIndex + i * room
            d.append(bytes[start..<min(start + room, bytes.endIndex)])
            return d
        }
    }
}

/// Puts fragments from one link back into packets. Bounded: a packet that is
/// not whole within `timeout` is dropped, at most `maxPending` are in flight,
/// and nothing over `Bluetooth.maxPacket` is assembled.
public struct Reassembler: Sendable {
    public static let timeout: TimeInterval = 10
    public static let maxPending = 8

    private struct Pending: Sendable {
        let count: Int
        var parts: [Int: Data]
        var size: Int
        let started: Date
    }
    private var pending: [UInt16: Pending] = [:]

    public init() {}

    public var inFlight: Int { pending.count }

    /// The whole packet's bytes when this fragment completes one.
    public mutating func add(_ fragment: Data, now: Date) -> Data? {
        expire(now: now)
        var r = ByteReader(fragment)
        guard let hi = r.u8(), let lo = r.u8(), let index = r.u8(), let count = r.u8(),
              count > 0, index < count else { return nil }
        let id = UInt16(hi) << 8 | UInt16(lo)
        let body = Data(fragment.dropFirst(Fragments.headerSize))
        guard !body.isEmpty else { return nil }
        if count == 1 {
            pending[id] = nil
            return body.count <= Bluetooth.maxPacket ? body : nil
        }

        var p: Pending
        if let existing = pending[id], existing.count == Int(count) {
            p = existing
        } else {
            // A new packet under this id (or a different count: the old one
            // was abandoned). Make room by dropping the oldest.
            if pending[id] == nil, pending.count >= Self.maxPending,
               let oldest = pending.min(by: { $0.value.started < $1.value.started })?.key {
                pending[oldest] = nil
            }
            p = Pending(count: Int(count), parts: [:], size: 0, started: now)
        }
        if p.parts[Int(index)] == nil {
            p.parts[Int(index)] = body
            p.size += body.count
        }
        guard p.size <= Bluetooth.maxPacket else {
            pending[id] = nil
            return nil
        }
        guard p.parts.count == p.count else {
            pending[id] = p
            return nil
        }
        pending[id] = nil
        return (0..<p.count).reduce(into: Data()) { $0.append(p.parts[$1]!) }
    }

    private mutating func expire(now: Date) {
        pending = pending.filter { now.timeIntervalSince($0.value.started) <= Self.timeout }
    }
}

// MARK: - What a locked phone shows

/// A notification for something that arrived while the app was not open.
/// Plain words, never mesh jargon and never an em dash.
public struct LockedAlert: Equatable, Sendable {
    public enum Urgency: Equatable, Sendable {
        /// A text, a ping, a meet-up, someone talking.
        case normal
        /// Help and roll call: shown even in a Focus (time sensitive).
        case timeSensitive
    }

    public let title: String
    public let body: String
    public let urgency: Urgency
    /// Notifications with the same thread are grouped (one per person or call).
    public let thread: String

    public init(title: String, body: String, urgency: Urgency, thread: String) {
        self.title = title
        self.body = body
        self.urgency = urgency
        self.thread = thread
    }
}

/// Turns dispatch events into notifications while the app is in the
/// background. "Is talking" at most once a minute per person: a speaker sends
/// a floor request each time they press.
public struct LockedAlerts: Sendable {
    public static let talkingInterval: TimeInterval = 60
    private var talking = RateLimiter(interval: LockedAlerts.talkingInterval)

    public init() {}

    /// `name` gives a person's name from the roster; nil when unknown.
    public mutating func alert(for event: Dispatch.Event, now: Date, name: (PeerID) -> String?) -> LockedAlert? {
        func who(_ p: PeerID) -> String { name(p) ?? "A friend" }
        switch event {
        case .text(let t) where !t.outgoing:
            return LockedAlert(title: t.senderName, body: t.text, urgency: .normal, thread: "text-\(t.channel.uuidString)")
        case .help(let h, let from, _):
            let body = h.note.isEmpty ? "Open ChirpChirps to see who is near them." : h.note
            return LockedAlert(title: "\(who(from)) needs help", body: body, urgency: .timeSensitive, thread: "help-\(h.id.uuidString)")
        case .rollCall(.ask(let id, _), let from, _):
            return LockedAlert(title: "Roll call: everyone OK?", body: "\(who(from)) asked. Open ChirpChirps to answer.",
                               urgency: .timeSensitive, thread: "rollcall-\(id.uuidString)")
        case .ping(let from):
            return LockedAlert(title: "\(who(from)) is looking for you", body: "Open ChirpChirps to chirp back.",
                               urgency: .normal, thread: "ping-\(from.hex)")
        case .meetup(.spot(let id, let place, _, _, _), let from, _):
            return LockedAlert(title: "\(who(from)) set a meet-up spot", body: "\(place). Open ChirpChirps to see when.",
                               urgency: .normal, thread: "meetup-\(id.uuidString)")
        case .floor(.request(let sender, let spoken, _), _):
            guard talking.allow(sender, now: now) else { return nil }
            let n = name(sender) ?? (spoken.isEmpty ? "A friend" : spoken)
            return LockedAlert(title: "\(n) is talking", body: "Open ChirpChirps to listen.", urgency: .normal,
                               thread: "talk-\(sender.hex)")
        default:
            return nil
        }
    }
}

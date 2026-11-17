import Foundation

// Message kinds added by the 2.0 scope (item 5, and Ping from item 4): roll
// call, help, meet-up spot, ping, battery. Each is a small typed body, signed
// by the sender over body and packet header (the same rule as texts), so a
// relay cannot forge one and a signature cannot be moved to another packet.

/// Sign and check any body: payload is `body ‖ signature(header ‖ body)`.
public enum Signed {
    public static func payload(_ body: Data, by identity: LocalIdentity, header: Data) throws -> Data {
        body + (try identity.sign(header + body))
    }

    /// The body, if the last 64 bytes are a valid signature by `signingKey`.
    public static func open(_ payload: Data, header: Data, signingKey: Data) -> Data? {
        guard payload.count >= 64 else { return nil }
        let body = Data(payload.dropLast(64)), sig = Data(payload.suffix(64))
        return LocalIdentity.verify(signature: sig, of: header + body, signingPublicKey: signingKey) ? body : nil
    }
}

private func uuidBytes(_ id: UUID) -> Data { withUnsafeBytes(of: id.uuid) { Data($0) } }
private func readUUID(_ r: inout ByteReader) -> UUID? {
    guard let b = r.bytes(16).map([UInt8].init) else { return nil }
    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
}
private func millis(_ d: Date) -> UInt64 { UInt64(max(0, d.timeIntervalSince1970 * 1000)) }
private func date(_ ms: UInt64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

// MARK: - Roll call

public enum RollCall: Equatable, Sendable {
    /// "Is everyone OK?"
    case ask(id: UUID, at: Date)
    /// An answer to `ask(id)`.
    case answer(id: UUID, ok: Bool)

    public func encode() -> Data {
        switch self {
        case .ask(let id, let at):
            var d = Data([1]); d.append(uuidBytes(id)); d.appendBigEndian(millis(at)); return d
        case .answer(let id, let ok):
            var d = Data([2]); d.append(uuidBytes(id)); d.append(ok ? 1 : 0); return d
        }
    }

    public static func decode(_ data: Data) -> RollCall? {
        var r = ByteReader(data)
        guard let tag = r.u8(), let id = readUUID(&r) else { return nil }
        switch tag {
        case 1: guard let ms = r.u64(), r.isAtEnd else { return nil }; return .ask(id: id, at: date(ms))
        case 2: guard let ok = r.u8(), ok <= 1, r.isAtEnd else { return nil }; return .answer(id: id, ok: ok == 1)
        default: return nil
        }
    }
}

/// The answers to one roll call, by person. Anyone who said "not OK" sorts first.
public struct RollCallTally: Equatable, Sendable {
    public let id: UUID
    public private(set) var answers: [PeerID: Bool] = [:]
    public init(id: UUID) { self.id = id }

    public mutating func record(_ answer: RollCall, from: PeerID) {
        guard case .answer(let id, let ok) = answer, id == self.id else { return }
        answers[from] = ok
    }

    public var needHelp: [PeerID] { answers.filter { !$0.value }.map(\.key).sorted() }
    public var okCount: Int { answers.values.filter { $0 }.count }

    /// Who on `expected` has not answered yet.
    public func missing(from expected: Set<PeerID>) -> [PeerID] {
        expected.subtracting(answers.keys).sorted()
    }
}

// MARK: - Help

public struct HelpCall: Equatable, Sendable {
    public static let maxNoteBytes = 140
    public let id: UUID
    public let at: Date
    public let note: String

    public init(id: UUID = UUID(), at: Date, note: String) {
        self.id = id
        self.at = at
        self.note = note
    }

    public func encode() -> Data {
        var d = uuidBytes(id); d.appendBigEndian(millis(at)); d.appendString(note, maxBytes: Self.maxNoteBytes); return d
    }

    public static func decode(_ data: Data) -> HelpCall? {
        var r = ByteReader(data)
        guard let id = readUUID(&r), let ms = r.u64(), let note = r.string(), r.isAtEnd,
              note.utf8.count <= maxNoteBytes else { return nil }
        return HelpCall(id: id, at: date(ms), note: note)
    }
}

// MARK: - Meet-up spot

public enum Meetup: Equatable, Sendable {
    /// A place (free text, and a position only if the sender chose to add one),
    /// a time, and the organiser counted as coming.
    case spot(id: UUID, place: String, latitude: Double?, longitude: Double?, at: Date)
    case reply(id: UUID, coming: Bool)

    public static let maxPlaceBytes = 120

    public func encode() -> Data {
        switch self {
        case .spot(let id, let place, let lat, let lon, let at):
            var d = Data([1]); d.append(uuidBytes(id)); d.appendBigEndian(millis(at))
            d.appendString(place, maxBytes: Self.maxPlaceBytes)
            if let lat, let lon {
                d.append(1); d.appendBigEndian(lat.bitPattern); d.appendBigEndian(lon.bitPattern)
            } else {
                d.append(0)
            }
            return d
        case .reply(let id, let coming):
            var d = Data([2]); d.append(uuidBytes(id)); d.append(coming ? 1 : 0); return d
        }
    }

    public static func decode(_ data: Data) -> Meetup? {
        var r = ByteReader(data)
        guard let tag = r.u8(), let id = readUUID(&r) else { return nil }
        switch tag {
        case 1:
            guard let ms = r.u64(), let place = r.string(), place.utf8.count <= maxPlaceBytes,
                  let hasPos = r.u8() else { return nil }
            var lat: Double?, lon: Double?
            if hasPos == 1 {
                guard let a = r.u64(), let b = r.u64() else { return nil }
                let la = Double(bitPattern: a), lo = Double(bitPattern: b)
                guard (-90...90).contains(la), (-180...180).contains(lo) else { return nil }
                lat = la; lon = lo
            } else if hasPos != 0 { return nil }
            guard r.isAtEnd else { return nil }
            return .spot(id: id, place: place, latitude: lat, longitude: lon, at: date(ms))
        case 2:
            guard let c = r.u8(), c <= 1, r.isAtEnd else { return nil }
            return .reply(id: id, coming: c == 1)
        default:
            return nil
        }
    }
}

/// Who is coming to one meet-up. The latest reply from each person counts.
public struct MeetupRSVP: Equatable, Sendable {
    public let id: UUID
    public private(set) var coming: Set<PeerID>
    public private(set) var notComing: Set<PeerID> = []

    public init(id: UUID, organiser: PeerID) {
        self.id = id
        self.coming = [organiser]
    }

    public mutating func record(_ reply: Meetup, from: PeerID) {
        guard case .reply(let id, let yes) = reply, id == self.id else { return }
        if yes { coming.insert(from); notComing.remove(from) } else { notComing.insert(from); coming.remove(from) }
    }
}

// MARK: - Battery

public struct BatteryLevel: Equatable, Sendable {
    /// Rounded to the nearest 10% before it leaves the phone: enough to know a
    /// friend's phone is about to die, no finer.
    public let percent: UInt8
    public let charging: Bool

    public init(fraction: Double, charging: Bool) {
        let clamped = min(1, max(0, fraction))
        self.percent = UInt8((clamped * 10).rounded() * 10)
        self.charging = charging
    }

    public func encode() -> Data { Data([percent, charging ? 1 : 0]) }

    public static func decode(_ data: Data) -> BatteryLevel? {
        guard data.count == 2, data[data.startIndex] <= 100, data[data.startIndex + 1] <= 1 else { return nil }
        return BatteryLevel(fraction: Double(data[data.startIndex]) / 100, charging: data[data.startIndex + 1] == 1)
    }
}

// MARK: - Who may send what

public enum Admission {
    /// Ping, battery and Find tokens count only on a whisper channel to me, from a friend.
    /// Anything else of those kinds is dropped: the "friends only" rule holds
    /// on the wire, not only in the UI.
    public static func accepts(_ packet: Packet, me: PeerID, friends: Set<PeerID>, blocked: Set<PeerID>) -> Bool {
        if blocked.contains(packet.origin) { return false }
        switch packet.kind {
        case .ping, .battery, .find:
            return friends.contains(packet.origin) && Whisper.isFor(packet, me: me)
        default:
            return true
        }
    }
}

/// At most one event per `interval` from each person (Ping: a friend cannot
/// make your phone chirp over and over).
public struct RateLimiter: Sendable {
    public let interval: TimeInterval
    private var last: [PeerID: Date] = [:]

    public init(interval: TimeInterval) { self.interval = interval }

    public mutating func allow(_ peer: PeerID, now: Date) -> Bool {
        if let prev = last[peer], now.timeIntervalSince(prev) < interval { return false }
        last[peer] = now
        return true
    }
}

/// Outbound packets waiting for the radio, in `sendPriority` order, oldest
/// first within a priority. Bounded: when full, the lowest-priority newest
/// packet is the one that goes, and help is never dropped for anything else.
public struct SendQueue: Sendable {
    public let capacity: Int
    private var items: [(priority: Int, order: UInt64, packet: Packet)] = []
    private var counter: UInt64 = 0

    public init(capacity: Int = 256) { self.capacity = max(1, capacity) }

    public var count: Int { items.count }

    /// Returns the packet that was dropped to make room, if any.
    @discardableResult
    public mutating func push(_ p: Packet) -> Packet? {
        counter &+= 1
        items.append((p.kind.sendPriority, counter, p))
        guard items.count > capacity else { return nil }
        // Drop the worst: highest priority number, then newest.
        let worst = items.indices.max { (items[$0].priority, items[$0].order) < (items[$1].priority, items[$1].order) }!
        return items.remove(at: worst).packet
    }

    public mutating func pop() -> Packet? {
        guard let best = items.indices.min(by: { (items[$0].priority, items[$0].order) < (items[$1].priority, items[$1].order) })
        else { return nil }
        return items.remove(at: best).packet
    }
}

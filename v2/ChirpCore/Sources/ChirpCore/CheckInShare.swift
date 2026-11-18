import Foundation

// What a check-in puts on the air, and what a phone keeps of other people's.
//
// The consent half is `LocationConsent.swift` (`CheckIn.reduce`): nothing is
// shared without a fresh yes, and sharing ends after 15 minutes, on Stop, on
// leaving the app or when location access is turned off. This file is the
// wire half. A position goes out only through `Dispatch.checkInPosition`,
// which needs a sharing state and a locked channel, so "only your birdhouse sees
// it, only while you check in" (site/privacy) holds in one place.

public enum CheckInMessage: Equatable, Sendable {
    /// Where I am, good to `accuracy` metres, shared until `until`.
    case at(latitude: Double, longitude: Double, accuracy: UInt16, until: Date)
    /// I stopped sharing: forget my position now.
    case stopped

    public func encode() -> Data {
        switch self {
        case .at(let lat, let lon, let accuracy, let until):
            var d = Data([1])
            d.appendBigEndian(lat.bitPattern)
            d.appendBigEndian(lon.bitPattern)
            d.appendBigEndian(accuracy)
            d.appendBigEndian(UInt64(max(0, until.timeIntervalSince1970 * 1000)))
            return d
        case .stopped:
            return Data([2])
        }
    }

    public static func decode(_ data: Data) -> CheckInMessage? {
        var r = ByteReader(data)
        guard let tag = r.u8() else { return nil }
        switch tag {
        case 1:
            guard let a = r.u64(), let b = r.u64(), let acc = r.u16(), let ms = r.u64(), r.isAtEnd else { return nil }
            let lat = Double(bitPattern: a), lon = Double(bitPattern: b)
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return .at(latitude: lat, longitude: lon, accuracy: acc, until: Date(timeIntervalSince1970: Double(ms) / 1000))
        case 2:
            return r.isAtEnd ? .stopped : nil
        default:
            return nil
        }
    }

    /// Metres from a Core Location accuracy: whole, at least 1, capped.
    public static func accuracy(_ metres: Double) -> UInt16 {
        guard metres.isFinite, metres > 0 else { return UInt16.max }
        return UInt16(min(Double(UInt16.max), max(1, metres.rounded(.up))))
    }
}

/// Other people's check-ins, as this phone keeps them: the latest position
/// from each person, gone when they stop, when it runs out, or when they are
/// blocked. Held in memory only. A sender cannot keep a position up longer
/// than one check-in: `until` is cut to `CheckIn.duration` from when it came.
public struct CheckInBoard: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let peer: PeerID
        public let channel: ChannelID
        public let latitude: Double
        public let longitude: Double
        public let accuracy: UInt16
        public let until: Date
        public let heard: Date
    }

    public private(set) var entries: [PeerID: Entry] = [:]

    public init() {}

    public mutating func apply(_ message: CheckInMessage, from peer: PeerID, channel: ChannelID, now: Date) {
        switch message {
        case .stopped:
            entries[peer] = nil
        case .at(let lat, let lon, let accuracy, let until):
            let end = min(until, now.addingTimeInterval(CheckIn.duration))
            guard end > now else { entries[peer] = nil; return }
            entries[peer] = Entry(peer: peer, channel: channel, latitude: lat, longitude: lon,
                                  accuracy: accuracy, until: end, heard: now)
        }
    }

    /// Drops what ran out; returns who went.
    @discardableResult
    public mutating func expire(now: Date) -> [PeerID] {
        let gone = entries.values.filter { $0.until <= now }.map(\.peer).sorted()
        for p in gone { entries[p] = nil }
        return gone
    }

    public mutating func forget(_ peer: PeerID) { entries[peer] = nil }

    /// Everyone whose check-in is still running.
    public func live(now: Date) -> [Entry] {
        entries.values.filter { $0.until > now }.sorted { $0.peer < $1.peer }
    }

    public func position(of peer: PeerID, now: Date) -> Entry? {
        entries[peer].flatMap { $0.until > now ? $0 : nil }
    }
}

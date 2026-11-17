import Foundation

/// Find (scope item 4): point to a friend.
///
/// Precision finding is Nearby Interaction between two iPhones with the UWB
/// chip. Each side needs the other's discovery token before ranging starts,
/// and with no internet the only way to swap tokens is this mesh: a `.find`
/// packet on the whisper channel (sealed pairwise, admitted only from a
/// friend, see `Admission`). The token is opaque bytes here; the app archives
/// and unarchives `NIDiscoveryToken`. The ranging itself, and the Nearby
/// Interaction permission prompt (asked on the first Find tap, never at
/// launch), live in the app.
///
/// Without UWB on either phone, or before ranging starts, the app shows the
/// plain fallback below, which claims no more than the mesh knows. 1.0 showed
/// invented hop counts, signal bars and metres (audit section 4).
public enum Find {
    public static let maxTokenBytes = 2048

    public enum Message: Equatable, Sendable {
        /// "Here is my token; send me yours."
        case offer(token: Data)
        /// "Here is mine back."
        case answer(token: Data)
        /// Stop ranging.
        case stop

        public func encode() -> Data {
            switch self {
            case .offer(let t): var d = Data([1]); d.appendBigEndian(UInt16(t.count)); d.append(t); return d
            case .answer(let t): var d = Data([2]); d.appendBigEndian(UInt16(t.count)); d.append(t); return d
            case .stop: return Data([3])
            }
        }

        public static func decode(_ data: Data) -> Message? {
            var r = ByteReader(data)
            guard let tag = r.u8() else { return nil }
            if tag == 3 { return r.isAtEnd ? .stop : nil }
            guard tag == 1 || tag == 2, let n = r.u16(), n > 0, Int(n) <= maxTokenBytes,
                  let t = r.bytes(Int(n)), r.isAtEnd else { return nil }
            return tag == 1 ? .offer(token: t) : .answer(token: t)
        }
    }

    /// What the app can honestly say without a UWB fix.
    public enum Fallback: Equatable, Sendable {
        /// Heard directly in the last few seconds: within Wi-Fi or Bluetooth range.
        case inRange
        /// Heard only through a relay: further away, direction unknown.
        case throughOthers
        /// Not heard recently.
        case outOfRange(lastSeen: Date?)
    }

    public static let recent: TimeInterval = 10

    public static func fallback(for person: Roster.Person?, lastSeen: Date?, now: Date) -> Fallback {
        guard let person, now.timeIntervalSince(person.lastSeen) <= recent else {
            return .outOfRange(lastSeen: person?.lastSeen ?? lastSeen)
        }
        return person.hops == 0 ? .inRange : .throughOthers
    }
}

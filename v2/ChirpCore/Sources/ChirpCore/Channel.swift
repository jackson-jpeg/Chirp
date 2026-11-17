import CryptoKit
import Foundation

/// A channel and, if it is locked, its key.
///
/// Carried over from 1.0: the invite code, base64url(channel UUID ‖ 16-byte
/// seed), and the key derived from it by HKDF bound to the channel ID (audit
/// section 7, round-trip tested). Dropped: epoch "rotation" (every epoch key
/// derived from the same base key, so it gave no forward secrecy) and the
/// plaintext `KRO!` packets.
///
/// Changed: a locked channel seals every payload on it, voice and floor
/// included. 1.0 encrypted only texts, so anyone in radio range heard a
/// locked channel's voice (claim H7).
public struct Channel: Equatable, Sendable {
    public let id: ChannelID
    public var name: String
    /// Nil for an open channel.
    public let seed: Data?

    public static let seedLength = 16

    public static let nearby = Channel(id: .nearby, name: "Nearby", seed: nil)

    public init(id: ChannelID, name: String, seed: Data?) {
        self.id = id
        self.name = name
        self.seed = seed
    }

    public static func newLocked(name: String) -> Channel {
        let seed = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return Channel(id: .random(), name: name, seed: seed)
    }

    public static func newOpen(name: String) -> Channel {
        Channel(id: .random(), name: name, seed: nil)
    }

    public var isLocked: Bool { seed != nil }

    var key: SymmetricKey? {
        seed.map {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: $0),
                                   salt: Data("ChirpChannelInvite-v1".utf8),
                                   info: Data(id.uuid.uuidString.utf8),
                                   outputByteCount: 32)
        }
    }

    // MARK: Invite codes

    /// 43 characters for a locked channel. An open channel has no secret, so
    /// its code is the 22-character channel ID alone.
    public var inviteCode: String {
        var raw = id.bytes
        if let seed { raw.append(seed) }
        return raw.base64URL
    }

    public static func join(inviteCode code: String, name: String) -> Channel? {
        guard let raw = Data(base64URL: code.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        switch raw.count {
        case 16:
            return ChannelID(bytes: raw).map { Channel(id: $0, name: name, seed: nil) }
        case 16 + seedLength:
            guard let id = ChannelID(bytes: raw.prefix(16)) else { return nil }
            return Channel(id: id, name: name, seed: Data(raw.suffix(seedLength)))
        default:
            return nil
        }
    }

    // MARK: Sealing

    /// The payload as it goes on the wire for this channel. The packet header
    /// (kind, origin, epoch, sequence, channel) is authenticated as associated
    /// data, so a sealed payload cannot be replayed under another header.
    public func seal(_ payload: Data, header: Data) throws -> Data {
        guard let key else { return payload }
        let box = try AES.GCM.seal(payload, using: key, authenticating: header)
        guard let combined = box.combined else { throw CryptoKitError.incorrectParameterSize }
        return combined
    }

    /// Nil when the payload was not sealed with this channel's key.
    public func open(_ wire: Data, header: Data) -> Data? {
        guard let key else { return wire }
        guard let box = try? AES.GCM.SealedBox(combined: wire) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: header)
    }
}

extension Packet {
    /// The header fields that do not change on relay (TTL and hops do), used as
    /// associated data when sealing.
    public var sealedHeader: Data {
        var out = Data()
        out.append(Packet.version)
        out.append(kind.rawValue)
        out.append(origin.bytes)
        out.appendBigEndian(epoch)
        out.appendBigEndian(sequence)
        out.append(channel.bytes)
        return out
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}

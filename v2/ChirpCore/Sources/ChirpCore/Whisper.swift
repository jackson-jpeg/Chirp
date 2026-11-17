import CryptoKit
import Foundation

/// Whisper: talk to one person, not the group (scope item 1).
///
/// A whisper is ordinary audio and floor traffic on a private two-person
/// channel, so it reuses everything a channel already has: the channel-scoped
/// floor (a whisper never takes the group's floor, and the group never takes
/// the whisper's), sealing bound to the header, the jitter buffer.
///
/// - The channel ID is derived from the two PeerIDs, so both people compute the
///   same one with no setup, and a relay sees an opaque ID: it cannot tell who
///   a whisper is for.
/// - The key comes from the pair's X25519 agreement (each side's agreement key
///   is learned from the other's signed presence), so nobody else, relays
///   included, can open it.
///
/// Ping and battery level use the same private channel, which is what makes
/// them "friends only" on the wire and not just in the UI.
public enum Whisper {
    /// The private channel between two people. Order-independent.
    public static func channelID(_ a: PeerID, _ b: PeerID) -> ChannelID {
        let (lo, hi) = a < b ? (a, b) : (b, a)
        var bytes = [UInt8](SHA256.hash(data: Data("chirp2.whisper".utf8) + lo.bytes + hi.bytes).prefix(16))
        // Never collide with the nearby channel or look like demo traffic.
        if Array(bytes.prefix(4)) == SendGate.demoPrefix || bytes.allSatisfy({ $0 == 0 }) { bytes[0] ^= 0x80 }
        return ChannelID(bytes: Data(bytes))!
    }

    /// The sealed channel this device uses to whisper with `them`. Nil when
    /// their agreement key is malformed.
    public static func channel(me: LocalIdentity, them: PeerID, theirAgreementKey: Data, name: String) -> Channel? {
        guard let key = me.sharedKey(with: theirAgreementKey, purpose: "chirp2.whisper") else { return nil }
        let seed = key.withUnsafeBytes { Data($0.prefix(Channel.seedLength)) }
        return Channel(id: channelID(me.peerID, them), name: name, seed: seed)
    }

    /// Whether a packet is a whisper addressed to this device: its channel is
    /// the private channel between its origin and me.
    public static func isFor(_ packet: Packet, me: PeerID) -> Bool {
        packet.origin != me && packet.channel == channelID(me, packet.origin)
    }
}

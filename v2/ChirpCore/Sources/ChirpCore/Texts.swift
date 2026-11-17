import Foundation

// Texts with delivery ticks.
//
// Kept from 1.0 (audit section 7): a message ID, dedup by ID, an ack by ID.
// Changed:
// - Ticks are part of the stored message, so they survive a relaunch (1.0 kept
//   them in memory and every tick reverted to "sent", claim H8).
// - A device acks only a message on a channel it has joined, and the ack
//   travels on that channel (sealed, if the channel is locked). 1.0 acked
//   anything it heard on any channel, so "delivered" meant "some phone in
//   range stored it" (claim H9).
// - Texts are signed by the sender's key, checked against the key the roster
//   learned from that person's presence. The header origin alone is 16 bytes
//   anyone can write.
// - One ack kind with its own packet kind. 1.0 had two acks sharing the magic
//   "ACK!", told apart by trying to parse JSON.

public struct TextBody: Equatable, Sendable {
    public static let maxBytes = 1000
    public let id: UUID
    public let sentAt: Date
    public let text: String

    public init(id: UUID = UUID(), sentAt: Date, text: String) {
        self.id = id
        self.sentAt = sentAt
        self.text = text
    }

    private func body() -> Data {
        var out = withUnsafeBytes(of: id.uuid) { Data($0) }
        out.appendBigEndian(UInt64(max(0, sentAt.timeIntervalSince1970 * 1000)))
        out.appendString(text, maxBytes: Self.maxBytes)
        return out
    }

    /// Signed over the body and the packet's sealed header, so a signature
    /// cannot be lifted onto another packet or channel.
    public func signedPayload(by identity: LocalIdentity, header: Data) throws -> Data {
        let b = body()
        return b + (try identity.sign(header + b))
    }

    public static func verify(_ payload: Data, header: Data, signingKey: Data) -> TextBody? {
        var r = ByteReader(payload)
        guard let idBytes = r.bytes(16), let ms = r.u64(), let text = r.string(),
              let sig = r.bytes(64), r.isAtEnd else { return nil }
        let bodyLength = 16 + 8 + 2 + Data(text.utf8).count
        guard LocalIdentity.verify(signature: sig, of: header + payload.prefix(bodyLength),
                                   signingPublicKey: signingKey) else { return nil }
        let b = [UInt8](idBytes)
        let id = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                             b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        return TextBody(id: id, sentAt: Date(timeIntervalSince1970: Double(ms) / 1000), text: text)
    }
}

/// The payload of an ack packet: the ID of the message it acknowledges.
public enum Ack {
    public static func payload(for id: UUID) -> Data { withUnsafeBytes(of: id.uuid) { Data($0) } }
    public static func messageID(in payload: Data) -> UUID? {
        guard payload.count == 16 else { return nil }
        let b = [UInt8](payload)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

public struct StoredText: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let channel: UUID
    public let sender: String        // PeerID hex
    public let senderName: String
    public let sentAt: Date
    public let text: String
    public let outgoing: Bool
    /// For outgoing texts: who has acked it (PeerID hex). Empty is one tick.
    public var deliveredTo: Set<String>

    public var isDelivered: Bool { !deliveredTo.isEmpty }
}

/// Every text on this device, by channel. Codable, so the app persists it
/// whole (with iOS file protection); ticks are saved with the messages.
public struct TextLedger: Equatable, Sendable, Codable {
    public private(set) var texts: [StoredText] = []
    public init() {}

    public mutating func recordOutgoing(_ body: TextBody, channel: ChannelID, me: PeerID, myName: String) {
        guard !texts.contains(where: { $0.id == body.id }) else { return }
        texts.append(StoredText(id: body.id, channel: channel.uuid, sender: me.hex, senderName: myName,
                                sentAt: body.sentAt, text: body.text, outgoing: true, deliveredTo: []))
    }

    public enum Incoming: Equatable, Sendable {
        /// New: store it and ack it.
        case stored
        /// Seen before (a relay copy, or a resend): ack again, store nothing.
        case duplicate
        /// Not on a channel this device has joined: neither store nor ack.
        case notJoined
    }

    /// What to do with a verified incoming text.
    public mutating func receive(_ body: TextBody, channel: ChannelID, from sender: PeerID, senderName: String,
                                 joined: Set<ChannelID>) -> Incoming {
        guard joined.contains(channel) else { return .notJoined }
        guard !texts.contains(where: { $0.id == body.id }) else { return .duplicate }
        texts.append(StoredText(id: body.id, channel: channel.uuid, sender: sender.hex, senderName: senderName,
                                sentAt: body.sentAt, text: body.text, outgoing: false, deliveredTo: []))
        return .stored
    }

    /// An ack arrived on `channel` from `from`. Counts only for our own text
    /// on that same channel, and never from ourselves. Returns true when the
    /// tick changed.
    @discardableResult
    public mutating func ack(_ id: UUID, from: PeerID, channel: ChannelID, me: PeerID) -> Bool {
        guard from != me,
              let i = texts.firstIndex(where: { $0.id == id && $0.outgoing && $0.channel == channel.uuid }) else {
            return false
        }
        return texts[i].deliveredTo.insert(from.hex).inserted
    }

    /// A channel's texts, oldest first, without anyone blocked.
    public func thread(_ channel: ChannelID, hiding blocked: Set<PeerID>) -> [StoredText] {
        let hidden = Set(blocked.map(\.hex))
        return texts.filter { $0.channel == channel.uuid && !hidden.contains($0.sender) }
                    .sorted { ($0.sentAt, $0.id.uuidString) < ($1.sentAt, $1.id.uuidString) }
    }
}

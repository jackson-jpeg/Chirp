import Foundation

/// A reaction attached to a mesh text message.
struct MessageReaction: Codable, Sendable, Identifiable {
    let id: UUID
    let messageID: UUID
    let emoji: String
    let senderID: String
    let senderName: String
}

/// A text message transmitted through the ChirpChirp mesh network.
///
/// Text messages ride the existing ``MeshPacket`` infrastructure as `.control`
/// packets with a `TXT!` (0x54 0x58 0x54 0x21) magic prefix to distinguish
/// them from ``FloorControlMessage`` payloads. The JSON body follows the prefix.
///
/// Max text length is 1000 characters — bandwidth is sacred on a mesh.
struct MeshTextMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let channelID: String
    /// Message body. Must not exceed ``MeshTextMessage.maxTextLength`` characters.
    let text: String
    let timestamp: Date
    /// When non-nil, this message is a reply in a thread.
    let replyToID: UUID?
    let attachmentType: AttachmentType?
    /// Delivery status: `.sent` when first transmitted, `.delivered` when peer ACK received.
    var deliveryStatus: DeliveryStatus = .sent
    /// Reactions from peers on this message.
    var reactions: [MessageReaction] = []

    /// Tracks whether a peer has acknowledged receipt of this message.
    enum DeliveryStatus: String, Codable, Sendable {
        case sent
        case delivered
        case read
    }

    enum AttachmentType: String, Codable, Sendable {
        /// Embedded latitude/longitude.
        case location
        /// Compressed thumbnail (max 50 KB).
        case image
        /// Peer identity card.
        case contact
        /// File transfer (metadata sent via FileTransferService).
        case file
        /// Voice note audio clip.
        case voiceNote
    }

    // MARK: - Init

    init(id: UUID, senderID: String, senderName: String, channelID: String,
         text: String, timestamp: Date, replyToID: UUID? = nil,
         attachmentType: AttachmentType? = nil, deliveryStatus: DeliveryStatus = .sent,
         reactions: [MessageReaction] = []) {
        self.id = id
        self.senderID = senderID
        self.senderName = senderName
        self.channelID = channelID
        self.text = text
        self.timestamp = timestamp
        self.replyToID = replyToID
        self.attachmentType = attachmentType
        self.deliveryStatus = deliveryStatus
        self.reactions = reactions
    }

    // MARK: - Constants

    /// Maximum allowed characters in ``text``.
    static let maxTextLength = 1000

    /// Maximum allowed characters for an image payload (base64-encoded JPEG).
    static let maxImagePayloadLength = 100_000

    /// Prefix for image attachment payloads.
    static let imagePrefix = "IMG:"

    /// Magic bytes prepended to JSON before placing into ``MeshPacket/payload``.
    /// ASCII: `TXT!`
    static let magicPrefix: [UInt8] = [0x54, 0x58, 0x54, 0x21]

    /// Magic bytes for delivery acknowledgment packets. ASCII: `ACK!`
    static let ackMagicPrefix: [UInt8] = [0x41, 0x43, 0x4B, 0x21]

    /// Magic bytes for reaction packets. ASCII: `RXN!`
    static let reactionMagicPrefix: [UInt8] = [0x52, 0x58, 0x4E, 0x21]

    /// Magic bytes for typing indicator packets. ASCII: `TYP!`
    static let typingMagicPrefix: [UInt8] = [0x54, 0x59, 0x50, 0x21]

    /// Magic bytes for read receipt packets. ASCII: `RRD!`
    static let readReceiptMagicPrefix: [UInt8] = [0x52, 0x52, 0x44, 0x21]

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        senderID = try container.decode(String.self, forKey: .senderID)
        senderName = try container.decode(String.self, forKey: .senderName)
        channelID = try container.decode(String.self, forKey: .channelID)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        replyToID = try container.decodeIfPresent(UUID.self, forKey: .replyToID)
        attachmentType = try container.decodeIfPresent(AttachmentType.self, forKey: .attachmentType)
        deliveryStatus = try container.decodeIfPresent(DeliveryStatus.self, forKey: .deliveryStatus) ?? .sent
        reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
    }

    // MARK: - Wire helpers

    /// Encode this message as wire-ready data: magic prefix + JSON.
    ///
    /// Image attachments skip the normal text truncation; their payload is
    /// clamped by ``maxImagePayloadLength`` in the send path instead.
    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``MeshTextMessage`` from a ``MeshPacket`` control payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> MeshTextMessage? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(MeshTextMessage.self, from: Data(json))
    }
}

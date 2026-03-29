import Foundation

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

    enum AttachmentType: String, Codable, Sendable {
        /// Embedded latitude/longitude.
        case location
        /// Compressed thumbnail (max 50 KB).
        case image
        /// Peer identity card.
        case contact
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

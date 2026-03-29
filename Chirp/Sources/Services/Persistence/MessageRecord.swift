import Foundation
import GRDB

/// GRDB record type that maps 1:1 to ``MeshTextMessage`` for SQLite persistence.
struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {

    static let databaseTableName = "messages"

    let id: String
    let senderID: String
    let senderName: String
    let channelID: String
    let text: String
    /// ISO 8601 string representation of the message timestamp.
    let timestamp: String
    let replyToID: String?
    let attachmentType: String?

    // MARK: - Converters

    /// Create a record from a ``MeshTextMessage``.
    init(from message: MeshTextMessage) {
        self.id = message.id.uuidString
        self.senderID = message.senderID
        self.senderName = message.senderName
        self.channelID = message.channelID
        self.text = message.text
        self.timestamp = ISO8601DateFormatter().string(from: message.timestamp)
        self.replyToID = message.replyToID?.uuidString
        self.attachmentType = message.attachmentType?.rawValue
    }

    /// Convert back to a ``MeshTextMessage``.
    func toMeshTextMessage() -> MeshTextMessage? {
        guard let uuid = UUID(uuidString: id),
              let date = ISO8601DateFormatter().date(from: timestamp) else {
            return nil
        }
        let replyUUID = replyToID.flatMap { UUID(uuidString: $0) }
        let attachment = attachmentType.flatMap { MeshTextMessage.AttachmentType(rawValue: $0) }

        return MeshTextMessage(
            id: uuid,
            senderID: senderID,
            senderName: senderName,
            channelID: channelID,
            text: text,
            timestamp: date,
            replyToID: replyUUID,
            attachmentType: attachment
        )
    }
}

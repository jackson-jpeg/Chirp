import Foundation

/// A translated message sent over the mesh.
///
/// Babel messages ride the existing ``MeshPacket`` infrastructure as `.control`
/// packets with a `BBL!` (0x42 0x42 0x4C 0x21) magic prefix to distinguish
/// them from other payload types. The JSON body follows the prefix.
struct BabelMessage: Codable, Sendable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let channelID: String
    let sourceLanguage: String      // BCP-47 code, e.g., "en-US"
    let targetLanguage: String      // BCP-47 code, e.g., "es"
    let originalText: String        // Source language transcription
    let translatedText: String      // Target language translation
    let isFinal: Bool               // false for partial results
    let timestamp: Date

    // MARK: - Constants

    /// Magic bytes prepended to JSON before placing into ``MeshPacket/payload``.
    /// ASCII: `BBL!`
    static let magicPrefix: [UInt8] = [0x42, 0x42, 0x4C, 0x21]

    // MARK: - Wire helpers

    /// Encode this message as wire-ready data: magic prefix + JSON.
    func wirePayload() throws -> Data {
        let json = try MeshCodable.encoder.encode(self)
        var data = Data(Self.magicPrefix)
        data.append(json)
        return data
    }

    /// Attempt to decode a ``BabelMessage`` from a ``MeshPacket`` control payload.
    /// Returns `nil` if the magic prefix is absent or JSON decoding fails.
    static func from(payload: Data) -> BabelMessage? {
        let prefix = Data(magicPrefix)
        guard payload.count > prefix.count,
              payload.prefix(prefix.count) == prefix else {
            return nil
        }
        let json = payload.dropFirst(prefix.count)
        return try? MeshCodable.decoder.decode(BabelMessage.self, from: Data(json))
    }
}

/// Configuration for an active translation session.
struct BabelSession: Sendable {
    let id: UUID
    let sourceLanguageCode: String  // BCP-47
    let targetLanguageCode: String  // BCP-47
    var isActive: Bool
}

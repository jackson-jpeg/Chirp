import Foundation

/// Shared JSON encoder/decoder configured for mesh wire format.
///
/// All mesh-serialized models (``MeshTextMessage``, ``FloorControlMessage``, etc.)
/// should use these coders so date formatting and key ordering stay consistent
/// across every device in the network.
enum MeshCodable {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

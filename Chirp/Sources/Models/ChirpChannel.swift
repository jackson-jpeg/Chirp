import Foundation

struct ChirpChannel: Identifiable, Equatable, Sendable, Codable {

    enum AccessMode: String, Codable, Sendable {
        case open
        case locked
    }

    let id: String
    var name: String
    var peers: [ChirpPeer] = []
    var createdAt: Date = Date()
    var accessMode: AccessMode = .open
    var theme: ChannelTheme = .squad
    var ownerID: String?
    /// Shareable invite code for locked channels. Reconstructed from the
    /// Keychain seed on load — never persisted (it contains key material).
    var inviteCode: String?
    /// Legacy pre-Keychain key storage. Decoded only so old saves can be
    /// migrated; never encoded again.
    var encryptionKeyData: Data?

    var activePeerCount: Int { peers.filter(\.isConnected).count }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, peers, createdAt, accessMode, theme, ownerID
        case inviteCode, encryptionKeyData
    }

    /// Custom encode so key material (the invite code and the legacy raw key)
    /// never lands in UserDefaults. Decoding stays synthesized, so old saves
    /// that do contain those fields still load for migration.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(peers, forKey: .peers)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(accessMode, forKey: .accessMode)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
    }
}

import CryptoKit
import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class ChannelManager {

    // MARK: - Public State

    private(set) var channels: [ChirpChannel] = []
    private(set) var activeChannel: ChirpChannel?

    // MARK: - Private

    private let logger = Logger.ptt
    private let storageKey = "com.chirpchirp.savedChannels"
    private let activeChannelKey = "com.chirpchirp.activeChannelID"
    private var channelCryptoCache: [String: ChannelCrypto] = [:]

    // MARK: - Key Rotation

    /// Current encryption epoch per channel. Advances on rotation.
    private var channelEpochs: [String: UInt32] = [:]
    /// Message count since last rotation per channel.
    private var epochMessageCounts: [String: Int] = [:]
    /// Timestamp of last rotation per channel.
    private var epochRotationDates: [String: Date] = [:]
    /// Rotate after this many messages.
    private let rotationMessageThreshold = 100
    /// Rotate after this interval.
    private let rotationTimeInterval: TimeInterval = 1800  // 30 minutes
    /// Called when a key rotation occurs. Payload should be broadcast to mesh.
    var onKeyRotation: ((Data, String) -> Void)?

    /// Well-known channel ID shared by all devices for the default "General" channel.
    static let defaultGeneralChannelID = "00000000-0000-0000-0000-000000000001"

    // MARK: - Init

    init() {
        loadChannels()
        migrateGeneralChannelID()
    }

    // MARK: - Channel Lifecycle

    @discardableResult
    func createChannel(
        name: String,
        accessMode: ChirpChannel.AccessMode = .open,
        ownerID: String? = nil,
        id: String? = nil
    ) -> ChirpChannel {
        let channelID = id ?? UUID().uuidString
        var encryptionKeyData: Data?
        var inviteCode: String?

        if accessMode == .locked {
            let key = ChannelCrypto.generateKey()
            encryptionKeyData = key.withUnsafeBytes { Data($0) }
            inviteCode = ChannelCrypto.createInviteCode(channelID: channelID, key: key)
            channelCryptoCache[channelID] = ChannelCrypto(key: key)
        }

        let channel = ChirpChannel(
            id: channelID,
            name: name,
            peers: [],
            createdAt: Date(),
            accessMode: accessMode,
            ownerID: ownerID,
            inviteCode: inviteCode,
            encryptionKeyData: encryptionKeyData
        )
        channels.append(channel)
        saveChannels()
        logger.info("Created channel '\(name)' (\(channel.id)) mode=\(accessMode.rawValue)")
        return channel
    }

    func joinChannel(id: String) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else {
            logger.warning("joinChannel failed — channel \(id) not found")
            return
        }

        if activeChannel != nil {
            leaveChannel()
        }

        activeChannel = self.channels[index]
        UserDefaults.standard.set(id, forKey: activeChannelKey)
        logger.info("Joined channel '\(self.channels[index].name)' (\(id))")
    }

    func leaveChannel() {
        guard let channel = activeChannel else { return }
        logger.info("Left channel '\(channel.name)' (\(channel.id))")
        activeChannel = nil
        UserDefaults.standard.removeObject(forKey: activeChannelKey)
    }

    // MARK: - Peer Management

    func addPeerToChannel(channelID: String, peer: ChirpPeer) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }
        guard !channels[index].peers.contains(where: { $0.id == peer.id }) else { return }

        self.channels[index].peers.append(peer)
        syncActiveChannel(channelID: channelID, at: index)
        logger.info("Added peer '\(peer.name)' to channel '\(self.channels[index].name)'")
    }

    func removePeerFromChannel(channelID: String, peerID: String) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else { return }

        self.channels[index].peers.removeAll { $0.id == peerID }
        syncActiveChannel(channelID: channelID, at: index)
        logger.info("Removed peer \(peerID) from channel '\(self.channels[index].name)'")
    }

    func channel(withID id: String) -> ChirpChannel? {
        channels.first { $0.id == id }
    }

    /// Join a locked channel using an invite code. Returns true on success.
    func joinWithInviteCode(_ code: String) -> Bool {
        // Find the channel whose invite code matches
        guard let index = channels.firstIndex(where: { $0.inviteCode == code }) else {
            logger.warning("joinWithInviteCode failed — no channel matches code")
            return false
        }

        let channel = channels[index]

        // Derive the crypto key from the invite code
        guard let key = ChannelCrypto.keyFromInviteCode(code) else {
            logger.warning("joinWithInviteCode failed — invalid invite code")
            return false
        }

        channelCryptoCache[channel.id] = ChannelCrypto(key: key)

        if activeChannel != nil {
            leaveChannel()
        }

        activeChannel = channel
        UserDefaults.standard.set(channel.id, forKey: activeChannelKey)
        logger.info("Joined locked channel '\(channel.name)' via invite code")
        return true
    }

    /// Get the ChannelCrypto instance for a given channel, if available.
    func getChannelCrypto(for channelID: String) -> ChannelCrypto? {
        // Return cached instance first
        if let cached = channelCryptoCache[channelID] {
            return cached
        }

        // Try to reconstruct from stored key data
        guard let channel = channels.first(where: { $0.id == channelID }),
              let keyData = channel.encryptionKeyData else {
            return nil
        }

        let key = SymmetricKey(data: keyData)
        let crypto = ChannelCrypto(key: key)
        channelCryptoCache[channelID] = crypto
        return crypto
    }

    // MARK: - Epoch Management

    /// Get the current encryption epoch for a channel.
    func currentEpoch(for channelID: String) -> UInt32 {
        channelEpochs[channelID] ?? 0
    }

    /// Record a message sent on a channel and rotate if thresholds are met.
    /// Returns the epoch to use for encryption.
    func recordMessageAndGetEpoch(for channelID: String) -> UInt32 {
        let count = (epochMessageCounts[channelID] ?? 0) + 1
        epochMessageCounts[channelID] = count

        let lastRotation = epochRotationDates[channelID] ?? Date.distantPast
        let timeSinceRotation = Date().timeIntervalSince(lastRotation)

        if count >= rotationMessageThreshold || timeSinceRotation >= rotationTimeInterval {
            advanceEpoch(for: channelID)
        }

        return channelEpochs[channelID] ?? 0
    }

    /// Advance the epoch for a channel. Called locally on threshold or when receiving KRO!.
    func advanceEpoch(for channelID: String) {
        let current = channelEpochs[channelID] ?? 0
        channelEpochs[channelID] = current + 1
        epochMessageCounts[channelID] = 0
        epochRotationDates[channelID] = Date()
        logger.info("Key rotation: channel \(channelID) advanced to epoch \(current + 1)")

        // Broadcast rotation to peers
        let payload = buildKeyRotationPayload(channelID: channelID)
        onKeyRotation?(payload, channelID)
    }

    /// Handle a received KRO! (key rotation) packet. Advance epoch if behind.
    func handleKeyRotation(channelID: String, peerEpoch: UInt32) {
        let current = channelEpochs[channelID] ?? 0
        if peerEpoch > current {
            channelEpochs[channelID] = peerEpoch
            epochMessageCounts[channelID] = 0
            epochRotationDates[channelID] = Date()
            logger.info("Key rotation from peer: channel \(channelID) jumped to epoch \(peerEpoch)")
        }
    }

    /// Build a KRO! packet payload for broadcasting epoch advancement.
    /// Format: [KRO! magic:4][epoch:4 BE][channelID UTF-8]
    func buildKeyRotationPayload(channelID: String) -> Data {
        let epoch = channelEpochs[channelID] ?? 0
        var payload = Data([0x4B, 0x52, 0x4F, 0x21])  // "KRO!"
        var epochBE = epoch.bigEndian
        withUnsafeBytes(of: &epochBE) { payload.append(contentsOf: $0) }
        payload.append(Data(channelID.utf8))
        return payload
    }

    /// Parse a KRO! packet payload. Returns (channelID, epoch) or nil.
    static func parseKeyRotationPayload(_ payload: Data) -> (channelID: String, epoch: UInt32)? {
        guard payload.count >= 9,  // 4 magic + 4 epoch + at least 1 byte channel
              payload[0] == 0x4B, payload[1] == 0x52,
              payload[2] == 0x4F, payload[3] == 0x21 else {
            return nil
        }
        let epoch = payload[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        guard let channelID = String(data: payload[8...], encoding: .utf8) else { return nil }
        return (channelID, epoch)
    }

    /// Kick a peer from a channel. Only the channel owner can kick.
    func kickPeer(channelID: String, peerID: String, requestingOwner: String) -> Bool {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
            logger.warning("kickPeer failed — channel \(channelID) not found")
            return false
        }

        guard channels[index].ownerID == requestingOwner else {
            logger.warning("kickPeer denied — \(requestingOwner) is not owner of channel \(channelID)")
            return false
        }

        channels[index].peers.removeAll { $0.id == peerID }
        syncActiveChannel(channelID: channelID, at: index)
        saveChannels()
        logger.info("Owner \(requestingOwner) kicked peer \(peerID) from channel \(channelID)")
        return true
    }

    func deleteChannel(id: String) {
        if activeChannel?.id == id {
            activeChannel = nil
            UserDefaults.standard.removeObject(forKey: activeChannelKey)
        }
        channels.removeAll { $0.id == id }
        saveChannels()
        logger.info("Deleted channel \(id)")
    }

    // MARK: - Migration

    /// One-time migration: replace any random-UUID "General" channel with the
    /// well-known ID so all devices share the same channel.
    private func migrateGeneralChannelID() {
        guard let index = channels.firstIndex(where: {
            $0.name == "General" && $0.accessMode == .open && $0.id != Self.defaultGeneralChannelID
        }) else { return }

        let old = channels[index]
        let wasActive = activeChannel?.id == old.id

        channels[index] = ChirpChannel(
            id: Self.defaultGeneralChannelID,
            name: old.name,
            peers: old.peers,
            createdAt: old.createdAt,
            accessMode: old.accessMode,
            ownerID: old.ownerID,
            inviteCode: old.inviteCode,
            encryptionKeyData: old.encryptionKeyData
        )

        if wasActive {
            activeChannel = channels[index]
            UserDefaults.standard.set(Self.defaultGeneralChannelID, forKey: activeChannelKey)
        }

        saveChannels()
        logger.info("Migrated General channel from \(old.id) to well-known ID")
    }

    // MARK: - Persistence

    private func saveChannels() {
        do {
            let data = try JSONEncoder().encode(channels)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to save channels: \(error.localizedDescription)")
        }
    }

    private func loadChannels() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            channels = try JSONDecoder().decode([ChirpChannel].self, from: data)
            // Restore active channel
            if let activeID = UserDefaults.standard.string(forKey: activeChannelKey),
               let index = channels.firstIndex(where: { $0.id == activeID }) {
                activeChannel = channels[index]
            }
            logger.info("Loaded \(self.channels.count) channel(s)")
        } catch {
            logger.error("Failed to load channels: \(error.localizedDescription)")
        }
    }

    private func syncActiveChannel(channelID: String, at index: Int) {
        if activeChannel?.id == channelID {
            activeChannel = channels[index]
        }
    }
}

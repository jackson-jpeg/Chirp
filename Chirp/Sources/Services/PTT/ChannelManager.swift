import CryptoKit
import Foundation
import Observation
import OSLog

@Observable
final class ChannelManager: @unchecked Sendable {

    // MARK: - Public State

    private(set) var channels: [ChirpChannel] = []
    private(set) var activeChannel: ChirpChannel?

    // MARK: - Private

    private let logger = Logger.ptt
    private let storageKey = "com.chirp.savedChannels"
    private let activeChannelKey = "com.chirp.activeChannelID"
    private var channelCryptoCache: [String: ChannelCrypto] = [:]

    // MARK: - Init

    init() {
        loadChannels()
    }

    // MARK: - Channel Lifecycle

    @discardableResult
    func createChannel(
        name: String,
        accessMode: ChirpChannel.AccessMode = .open,
        ownerID: String? = nil
    ) -> ChirpChannel {
        let channelID = UUID().uuidString
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

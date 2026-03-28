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

    // MARK: - Init

    init() {
        loadChannels()
    }

    // MARK: - Channel Lifecycle

    @discardableResult
    func createChannel(name: String) -> ChirpChannel {
        let channel = ChirpChannel(
            id: UUID().uuidString,
            name: name,
            peers: [],
            createdAt: Date()
        )
        channels.append(channel)
        saveChannels()
        logger.info("Created channel '\(name)' (\(channel.id))")
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

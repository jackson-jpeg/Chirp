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

    // MARK: - Channel Lifecycle

    /// Creates a new channel and returns it. Does not automatically join.
    @discardableResult
    func createChannel(name: String) -> ChirpChannel {
        let channel = ChirpChannel(
            id: UUID().uuidString,
            name: name,
            peers: [],
            createdAt: Date()
        )
        channels.append(channel)
        logger.info("Created channel '\(name)' (\(channel.id))")
        return channel
    }

    /// Join an existing channel by ID. Leaves the current channel first if needed.
    func joinChannel(id: String) {
        guard let index = channels.firstIndex(where: { $0.id == id }) else {
            logger.warning("joinChannel failed — channel \(id) not found")
            return
        }

        if activeChannel != nil {
            leaveChannel()
        }

        activeChannel = channels[index]
        logger.info("Joined channel '\(channels[index].name)' (\(id))")
    }

    /// Leave the currently active channel.
    func leaveChannel() {
        guard let channel = activeChannel else {
            logger.debug("leaveChannel called with no active channel")
            return
        }

        logger.info("Left channel '\(channel.name)' (\(channel.id))")
        activeChannel = nil
    }

    // MARK: - Peer Management

    /// Add a peer to a specific channel.
    func addPeerToChannel(channelID: String, peer: ChirpPeer) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
            logger.warning("addPeerToChannel failed — channel \(channelID) not found")
            return
        }

        // Avoid duplicates.
        guard !channels[index].peers.contains(where: { $0.id == peer.id }) else {
            logger.debug("Peer \(peer.name) already in channel \(channelID)")
            return
        }

        channels[index].peers.append(peer)
        syncActiveChannel(channelID: channelID, at: index)
        logger.info("Added peer '\(peer.name)' to channel '\(channels[index].name)'")
    }

    /// Remove a peer from a specific channel.
    func removePeerFromChannel(channelID: String, peerID: String) {
        guard let index = channels.firstIndex(where: { $0.id == channelID }) else {
            logger.warning("removePeerFromChannel failed — channel \(channelID) not found")
            return
        }

        channels[index].peers.removeAll { $0.id == peerID }
        syncActiveChannel(channelID: channelID, at: index)
        logger.info("Removed peer \(peerID) from channel '\(channels[index].name)'")
    }

    // MARK: - Queries

    /// Find a channel by ID.
    func channel(withID id: String) -> ChirpChannel? {
        channels.first { $0.id == id }
    }

    /// Remove a channel entirely.
    func deleteChannel(id: String) {
        if activeChannel?.id == id {
            activeChannel = nil
        }
        channels.removeAll { $0.id == id }
        logger.info("Deleted channel \(id)")
    }

    // MARK: - Private

    /// Keep activeChannel in sync when the backing array mutates.
    private func syncActiveChannel(channelID: String, at index: Int) {
        if activeChannel?.id == channelID {
            activeChannel = channels[index]
        }
    }
}

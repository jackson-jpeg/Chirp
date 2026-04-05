import Foundation

/// Injects realistic-looking demo data for App Store screenshots.
/// Activated by the `-demoMode` launch argument.
enum DemoData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoMode")
    }

    // MARK: - Peers

    static let peers: [ChirpPeer] = [
        ChirpPeer(id: "peer-1", name: "Sarah", isConnected: true, signalStrength: 3, lastHeartbeat: Date(), transportType: .multipeer),
        ChirpPeer(id: "peer-2", name: "Miguel", isConnected: true, signalStrength: 2, lastHeartbeat: Date(), transportType: .multipeer),
        ChirpPeer(id: "peer-3", name: "Kai", isConnected: true, signalStrength: 3, lastHeartbeat: Date(), transportType: .wifiAware),
        ChirpPeer(id: "peer-4", name: "Priya", isConnected: true, signalStrength: 1, lastHeartbeat: Date().addingTimeInterval(-30), transportType: .multipeer),
        ChirpPeer(id: "peer-5", name: "Alex", isConnected: true, signalStrength: 2, lastHeartbeat: Date().addingTimeInterval(-10), transportType: .multipeer),
    ]

    // MARK: - Friends

    static let friends: [(id: String, name: String)] = [
        ("peer-1", "Sarah"),
        ("peer-2", "Miguel"),
        ("peer-3", "Kai"),
        ("peer-4", "Priya"),
        ("peer-5", "Alex"),
        ("peer-6", "Jordan"),
    ]

    // MARK: - Channels

    @MainActor
    static func createChannels(manager: ChannelManager, localPeerID: String) {
        // Clear any existing channels first
        for channel in manager.channels {
            manager.deleteChannel(id: channel.id)
        }

        // General channel with active peers
        let general = manager.createChannel(name: "General", accessMode: .open, ownerID: localPeerID, id: ChannelManager.defaultGeneralChannelID)
        for peer in peers {
            manager.addPeerToChannel(channelID: general.id, peer: peer)
        }
        manager.joinChannel(id: general.id)

        // Hiking group
        let hiking = manager.createChannel(name: "Trail Group", accessMode: .open)
        manager.addPeerToChannel(channelID: hiking.id, peer: peers[0])
        manager.addPeerToChannel(channelID: hiking.id, peer: peers[2])
        manager.addPeerToChannel(channelID: hiking.id, peer: peers[4])

        // Private channel
        let priv = manager.createChannel(name: "Camp Alpha", accessMode: .open, ownerID: localPeerID)
        manager.addPeerToChannel(channelID: priv.id, peer: peers[1])
        manager.addPeerToChannel(channelID: priv.id, peer: peers[3])
    }

    // MARK: - Messages

    static func createMessages(channelID: String, localPeerID: String, localPeerName: String) -> [MeshTextMessage] {
        let now = Date()
        return [
            MeshTextMessage(id: UUID(), senderID: "peer-1", senderName: "Sarah", channelID: channelID,
                            text: "Everyone make it to the trailhead?", timestamp: now.addingTimeInterval(-600),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: "peer-2", senderName: "Miguel", channelID: channelID,
                            text: "Just parked. Heading up now", timestamp: now.addingTimeInterval(-540),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: "peer-3", senderName: "Kai", channelID: channelID,
                            text: "Copy that. Signal is already gone up here", timestamp: now.addingTimeInterval(-480),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: localPeerID, senderName: localPeerName, channelID: channelID,
                            text: "ChirpChirp still works though", timestamp: now.addingTimeInterval(-420),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: "peer-4", senderName: "Priya", channelID: channelID,
                            text: "This is incredible. No signal and I can hear everyone", timestamp: now.addingTimeInterval(-360),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: "peer-1", senderName: "Sarah", channelID: channelID,
                            text: "We're at the summit. The view is unreal up here", timestamp: now.addingTimeInterval(-300),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: "peer-5", senderName: "Alex", channelID: channelID,
                            text: "Got it. 800m away. Be there in 10", timestamp: now.addingTimeInterval(-240),
                            replyToID: nil, attachmentType: nil),
            MeshTextMessage(id: UUID(), senderID: localPeerID, senderName: localPeerName, channelID: channelID,
                            text: "The mesh just relayed through 3 hops to reach Alex", timestamp: now.addingTimeInterval(-180),
                            replyToID: nil, attachmentType: nil),
        ]
    }

    // MARK: - Apply

    @MainActor
    static func apply(to appState: AppState) {
        guard isEnabled else { return }

        // Channels with peers
        createChannels(manager: appState.channelManager, localPeerID: appState.localPeerID)

        // Friends
        for friend in friends {
            appState.friendsManager.addFriend(id: friend.id, name: friend.name)
        }
        // Mark some as online
        for i in 0..<min(4, appState.friendsManager.friends.count) {
            appState.friendsManager.updateOnlineStatus(peerID: appState.friendsManager.friends[i].id, isOnline: true)
        }

        // Fake connected peer count
        appState.setDemoPeerCount(5)

        // Inject messages into text message service
        if let activeChannel = appState.channelManager.activeChannel {
            let messages = createMessages(
                channelID: activeChannel.id,
                localPeerID: appState.localPeerID,
                localPeerName: appState.callsign
            )
            for msg in messages {
                appState.textMessageService.injectDemoMessage(msg)
            }
        }
    }
}

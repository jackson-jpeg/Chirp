import Foundation
import OSLog

/// Builds the mesh router's local-delivery handler — the single dispatch point
/// for every packet the router accepts for this device: audio to the engine,
/// text/reactions/files to their services, floor control to the floor session.
///
/// Extracted from AppState so the loopback test suite (`LoopbackHarnessTests`)
/// runs the exact delivery code production runs, wired to the same services,
/// instead of a reimplementation that could drift green while the app broke.
enum MeshDelivery {

    /// All delivery is dispatched to @MainActor for safe access to
    /// @MainActor-isolated services (ChannelManager, FloorSession,
    /// TextMessageService). Audio playback remains low-latency because
    /// AudioEngine.receiveAudioPacket schedules buffers on the player node
    /// internally.
    ///
    /// `notifyMessage` is injected rather than calling NotificationService
    /// directly: UNUserNotificationCenter cannot be touched from a bare test
    /// process, and the notification banner is not part of what delivery is
    /// responsible for proving.
    /// Builds the text service's send handler — the policy for every outgoing
    /// text-service payload (message, ACK, reaction, receipt):
    ///
    ///   * live broadcast whenever the *transport* has any connected peer —
    ///     never gated on the per-channel roster, because the roster is only
    ///     populated for the active channel and receivers filter by channel
    ///     themselves. Gating on the roster silently dropped every send made
    ///     from a channel that wasn't the active one, delivery ACKs included.
    ///   * a store-and-forward copy for each known channel member currently
    ///     offline, so they receive it on reconnection.
    ///
    /// Extracted from AppState for the same reason as
    /// `makeLocalDeliveryHandler`: so the test suite exercises the production
    /// send policy instead of a reimplementation.
    static func makeTextSendHandler(
        sendControl: @escaping (Data, String) throws -> Void,
        transportPeers: @escaping () -> [ChirpPeer],
        channelLookup: @escaping (String) -> ChirpChannel?,
        localPeerName: @escaping () -> String?,
        enqueue: @escaping (StoreAndForwardRelay.PendingMessage) -> Void
    ) -> (Data, String) -> Void {
        return { payload, channelID in
            if !transportPeers().isEmpty {
                do {
                    try sendControl(payload, channelID)
                } catch {
                    Logger.network.error("Text message send failed: \(error.localizedDescription)")
                }
            } else {
                Logger.network.warning("Text send deferred — no connected transport peers (channel \(channelID))")
            }

            // Store-and-forward: queue for known channel members currently offline.
            let peers = channelLookup(channelID)?.peers ?? []
            let offlinePeers = peers.filter { !$0.isConnected }
            guard !offlinePeers.isEmpty, let senderName = localPeerName() else { return }
            for peer in offlinePeers {
                enqueue(StoreAndForwardRelay.PendingMessage(
                    id: UUID(),
                    recipientPeerID: peer.id,
                    payload: payload,
                    channelID: channelID,
                    senderName: senderName,
                    timestamp: Date()
                ))
            }
        }
    }

    static func makeLocalDeliveryHandler(
        audioEngine audioEng: AudioEngine,
        floorSession floorCtrl: FloorSession,
        channelManager chanMgr: ChannelManager,
        peerTracker peerTrk: PeerTracker,
        textMessageService txtService: TextMessageService,
        fileTransferService fileService: FileTransferService,
        meshBeacon beaconSvc: MeshBeacon,
        pheromoneRouter pheroRouter: PheromoneRouter,
        notifyMessage: @escaping @MainActor (_ senderName: String, _ text: String, _ channelName: String) -> Void
    ) -> @Sendable (MeshPacket) -> Void {
        return { (packet: MeshPacket) in
            Task { @MainActor in
                // Channel filtering: drop audio for wrong channel.
                // Control packets with empty channelID (broadcasts) are always delivered.
                let activeID = chanMgr.activeChannel?.id ?? ""
                if !packet.channelID.isEmpty && packet.channelID != activeID {
                    // Wrong channel -- drop audio, but still deliver broadcast controls
                    if packet.type == .audio {
                        #if DEBUG
                        AudioTelemetry.shared.countStage("audioDropChannelFilter")
                        #endif
                        return
                    }
                }

                // Silently discard cover traffic
                // inside the payload. These are only recognisable after local decryption.
                if MeshShield.isCoverTraffic(packet.payload) {
                    return
                }

                switch packet.type {
                case .audio:
                    if let audioPacket = AudioPacket.deserialize(packet.payload) {
                        #if DEBUG
                        AudioTelemetry.shared.countStage("audioToEngine")
                        #endif
                        audioEng.receiveAudioPacket(audioPacket.opusData, sequenceNumber: audioPacket.sequenceNumber)
                    } else {
                        #if DEBUG
                        AudioTelemetry.shared.countStage("audioPayloadDeserializeFail")
                        #endif
                    }
                case .control:
                    // Extract 4-byte magic prefix for O(1) dispatch
                    let payload = packet.payload
                    let prefixStr: String
                    if payload.count >= 4 {
                        prefixStr = String(data: payload.prefix(4), encoding: .ascii) ?? ""
                    } else {
                        prefixStr = ""
                    }

                    // Hand a payload to the text service and, if it stored a new
                    // message, send the mesh-level delivery ACK and the local
                    // notification. Shared between the plaintext "TXT!" case and
                    // the encrypted fallback below — an encrypted message that
                    // only reveals itself as text after decryption inside
                    // handlePacket must earn the same ACK a plaintext one does.
                    // (A closure, not a nested func: local functions do not
                    // inherit the surrounding @MainActor isolation.)
                    let deliverToTextService: () -> Void = {
                        let channelForACK = packet.channelID
                        let beforeCount = txtService.messagesByChannel[channelForACK]?.count ?? 0
                        txtService.handlePacket(payload, channelID: channelForACK)
                        let afterCount = txtService.messagesByChannel[channelForACK]?.count ?? 0

                        if afterCount > beforeCount, !channelForACK.isEmpty {
                            pheroRouter.acknowledgeDelivery(
                                packetID: packet.packetID,
                                senderID: packet.originID.uuidString,
                                channelID: packet.channelID
                            )
                            if let lastMsg = txtService.messagesByChannel[channelForACK]?.last {
                                let chName = chanMgr.channels.first(where: { $0.id == channelForACK })?.name ?? "Chirp"
                                notifyMessage(lastMsg.senderName, lastMsg.text, chName)
                            }
                        }
                    }

                    switch prefixStr {
                    case "ACK!":
                        // Two wire formats share this magic: the pheromone
                        // DeliveryACK ("ACK!" + JSON) and the text service's
                        // per-message ACK ("ACK!" + UUID string). handleACK
                        // returns false when the payload isn't its JSON — that
                        // is the text ACK, and swallowing it here is what kept
                        // every sent message stuck at .sent forever.
                        if !pheroRouter.handleACK(payload, fromPeer: packet.originID.uuidString) {
                            txtService.handlePacket(payload, channelID: packet.channelID)
                        }

                    case "TXT!":
                        deliverToTextService()

                    case "RXN!":
                        txtService.handleReaction(payload, channelID: packet.channelID)

                    case "FIL!", "FLC!", "FNK!":
                        fileService.handlePacket(payload, channelID: packet.channelID)

                    case "BCN!":
                        // Presence beacons. The broadcaster, the HomeView node
                        // list, and the MeshIntelligence topology observers
                        // were all live while nothing routed received beacons
                        // to handleBeacon — every device announced itself and
                        // no device ever heard anyone.
                        beaconSvc.handleBeacon(payload)

                    case "KRO!":
                        if let rotation = ChannelManager.parseKeyRotationPayload(payload) {
                            chanMgr.handleKeyRotation(channelID: rotation.channelID, peerEpoch: rotation.epoch)
                        }

                    default:
                        // FloorControlMessage uses JSON without a magic prefix
                        if let message = try? MeshCodable.decoder.decode(FloorControlMessage.self, from: payload) {
                            floorCtrl.handleMessage(message, from: packet.originID.uuidString)

                            switch message {
                            case .heartbeat(let peerID, let timestamp):
                                Task { await peerTrk.handleHeartbeat(peerID: peerID, timestamp: timestamp) }
                            case .peerJoin(let peerID, let peerName):
                                Task { await peerTrk.updatePeer(id: peerID, name: peerName) }
                            case .peerLeave(let peerID):
                                Task { await peerTrk.removePeer(id: peerID) }
                            default:
                                break
                            }
                        } else {
                            // Locked-channel traffic: ChannelCrypto output is
                            // [epoch][AES-GCM] with no plaintext magic, so every
                            // encrypted text-service payload (TXT!/ACK!/RXN!/
                            // TYP!/RRD!) lands here. handlePacket decrypts with
                            // the channel key and ignores anything that still
                            // doesn't match — before this fallback, locked
                            // channels dropped every message on the floor.
                            deliverToTextService()
                            // Encrypted file-transfer traffic (FIL!/FLC!/FNK!)
                            // lands here for the same reason. The file service
                            // decrypts with its own provider and ignores
                            // payloads that are not file traffic, exactly as
                            // the text service ignores file payloads — each
                            // packet is claimed by at most one of the two.
                            // Before this call, locked channels dropped every
                            // file transfer on the floor.
                            fileService.handlePacket(payload, channelID: packet.channelID)
                        }
                    }
                }
            }
        }
    }
}

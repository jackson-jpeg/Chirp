import SwiftUI

struct ChannelView: View {
    @Environment(AppState.self) private var appState

    let channel: ChirpChannel

    @State private var pttState: PTTState = .idle
    @State private var inputLevel: Float = 0.0
    @State private var toast: ToastItem?

    private let peerGridColumns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: channel info
            channelHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.top, 8)

            // Peer grid
            ScrollView {
                if channel.peers.isEmpty {
                    emptyPeersView
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: peerGridColumns, spacing: 20) {
                        ForEach(channel.peers) { peer in
                            VStack(spacing: 6) {
                                PeerAvatarView(
                                    peer: peer,
                                    isActiveSpeaker: isActiveSpeaker(peer)
                                )

                                Text(peer.name)
                                    .font(.system(.caption2, weight: .medium))
                                    .foregroundStyle(
                                        isActiveSpeaker(peer) ? Color(hex: 0x30D158) : .secondary
                                    )
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
            }

            Spacer()

            // Waveform (visible during transmit/receive)
            if pttState == .transmitting || isReceiving {
                WaveformView(inputLevel: inputLevel, pttState: pttState)
                    .frame(height: 50)
                    .padding(.horizontal, 40)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .animation(.easeInOut(duration: 0.2), value: pttState)

                // Speaker name during receiving
                if case .receiving(let name, _) = pttState {
                    Text(name)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x30D158))
                        .padding(.top, 4)
                }
            }

            // PTT Button
            PTTButtonView(
                pttState: $pttState,
                onPressDown: {
                    HapticsManager.shared.pttDown()
                    SoundEffects.shared.playChirpBegin()
                    appState.pttEngine.startTransmitting()
                },
                onPressUp: {
                    HapticsManager.shared.pttUp()
                    SoundEffects.shared.playChirpEnd()
                    appState.pttEngine.stopTransmitting()
                }
            )
            .padding(.bottom, 40)
            .padding(.top, 16)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .chirpToast($toast)
        .onChange(of: appState.pttState) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                pttState = newValue
            }
            appState.updateLiveActivity()
        }
        .onChange(of: appState.inputLevel) { _, newValue in
            inputLevel = newValue
            // Throttle live activity updates to avoid excessive calls
            if pttState == .transmitting || isReceiving {
                appState.updateLiveActivity()
            }
        }
        .onAppear {
            // Start live activity for this channel
            appState.liveActivityManager.startActivity(channelName: channel.name)
        }
        .onDisappear {
            appState.liveActivityManager.endActivity()
        }
    }

    // MARK: - Channel Header

    private var channelHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(channel.activePeerCount) active")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                SignalStrengthIndicator(level: 3)

                // Peer count badge
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                    Text("\(channel.peers.count)")
                        .font(.system(.caption, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0xFFB800))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: 0xFFB800).opacity(0.15))
                )
            }
        }
    }

    // MARK: - Empty Peers

    private var emptyPeersView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("No peers on this channel")
                .font(.system(.headline, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Invite friends to join this channel")
                .font(.system(.subheadline))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private var isReceiving: Bool {
        if case .receiving = pttState { return true }
        return false
    }

    private func isActiveSpeaker(_ peer: ChirpPeer) -> Bool {
        if case .receiving(_, let speakerID) = pttState {
            return peer.id == speakerID
        }
        return false
    }
}

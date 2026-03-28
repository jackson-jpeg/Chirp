import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var showChannelCreation = false
    @State private var showPairing = false
    @State private var toast: ToastItem?
    @State private var connectedPeerCount = 0

    private var connectionStatus: ConnectionStatus {
        let pairedCount = appState.wifiAwareManager.pairedDevices.count

        if pairedCount == 0 {
            return .disconnected
        }

        if connectedPeerCount > 0 {
            return .connected(peerCount: connectedPeerCount)
        }
        return .searching
    }

    private var hasPairedDevices: Bool {
        return !appState.wifiAwareManager.pairedDevices.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status pill
                StatusPillView(status: connectionStatus)
                    .padding(.top, 12)

                channelListView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Chirp")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showPairing = true
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(hex: 0xFFB800))
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showChannelCreation) {
                ChannelCreationView()
            }
            .sheet(isPresented: $showPairing) {
                PairingView()
                    .onAppearAnimations()
            }
            .chirpToast($toast)
            .task {
                // Periodically refresh connected peer count from actor
                while !Task.isCancelled {
                    let peers = await appState.peerTracker.connectedPeers
                    connectedPeerCount = peers.count
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Color(hex: 0xFFB800).opacity(0.5))

            VStack(spacing: 8) {
                Text("No Devices Paired")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.white)

                Text("Pair with a nearby device to start talking.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showPairing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Pair Your First Device")
                }
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: 0xFFB800))
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Channel List

    private var channelListView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if appState.channelManager.channels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.secondary)

                        Text("No channels yet")
                            .font(.system(.headline, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text("Create a channel to start talking")
                            .font(.system(.subheadline))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 80)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.channelManager.channels) { channel in
                            NavigationLink {
                                ChannelView(channel: channel)
                            } label: {
                                channelRow(channel)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }

            // FAB - Create channel
            Button {
                showChannelCreation = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color(hex: 0xFFB800))
                            .shadow(color: Color(hex: 0xFFB800).opacity(0.3), radius: 12, y: 4)
                    )
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Channel Row

    private func channelRow(_ channel: ChirpChannel) -> some View {
        HStack(spacing: 14) {
            // Channel icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: 0xFFB800).opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: 0xFFB800))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(channel.activePeerCount) active \u{00B7} \(channel.peers.count) peers")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

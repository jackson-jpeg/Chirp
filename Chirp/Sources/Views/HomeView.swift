import SwiftUI

// MARK: - Signal Animation

private struct SignalBarsView: View {
    let active: Bool

    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(active ? Color(hex: 0x30D158) : Color.gray.opacity(0.3))
                    .frame(width: 3, height: CGFloat(6 + index * 3))
                    .opacity(active && animating ? (index == 2 ? 0.4 : 1.0) : 1.0)
            }
        }
        .onAppear {
            guard active else { return }
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                animating = true
            }
        }
    }
}

// MARK: - Noise Texture Overlay

private struct NoiseOverlay: View {
    var body: some View {
        Canvas { context, size in
            // Draw a subtle pattern using small rects
            for x in stride(from: 0, to: size.width, by: 4) {
                for y in stride(from: 0, to: size.height, by: 4) {
                    let val = sin(x * 0.7 + y * 1.3) * cos(x * 1.1 - y * 0.9)
                    let opacity = abs(val) * 0.03
                    context.fill(
                        Path(CGRect(x: x, y: y, width: 4, height: 4)),
                        with: .color(Color.white.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Pulsing FAB

private struct PulsingFAB: View {
    let isEmpty: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    var body: some View {
        ZStack {
            if isEmpty {
                Circle()
                    .fill(Color(hex: 0xFFB800).opacity(pulseOpacity))
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulseScale)
            }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color(hex: 0xFFB800))
                            .shadow(color: Color(hex: 0xFFB800).opacity(0.4), radius: 16, y: 4)
                    )
            }
        }
        .onAppear {
            guard isEmpty else { return }
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.6
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - Radio Empty State

private struct ChannelEmptyStateView: View {
    @State private var waveScale: CGFloat = 0.8
    @State private var waveOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 40)

            ZStack {
                // Outer ring pulse
                Circle()
                    .stroke(Color(hex: 0xFFB800).opacity(0.15), lineWidth: 1)
                    .frame(width: 120, height: 120)
                    .scaleEffect(waveScale)
                    .opacity(waveOpacity)

                Circle()
                    .fill(Color(hex: 0xFFB800).opacity(0.08))
                    .frame(width: 90, height: 90)

                Image(systemName: "radio")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color(hex: 0xFFB800).opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("Create your first channel")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Channels let your group talk instantly.\nTap + to get started.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .onAppear {
            withAnimation(
                .easeOut(duration: 2.5)
                .repeatForever(autoreverses: false)
            ) {
                waveScale = 1.5
                waveOpacity = 0.4
            }
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var showChannelCreation = false
    @State private var showPairing = false
    @State private var toast: ToastItem?
    @State private var connectedPeerCount = 0
    @State private var isRefreshing = false

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

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
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                // Subtle noise texture
                NoiseOverlay()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Callsign section
                    callsignHeader
                        .padding(.top, 8)

                    // Enhanced status pill
                    enhancedStatusPill
                        .padding(.top, 12)

                    // Channel list with pull-to-refresh
                    channelListView
                }
            }
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
                                .foregroundStyle(amber)
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
                while !Task.isCancelled {
                    let peers = await appState.peerTracker.connectedPeers
                    connectedPeerCount = peers.count
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    // MARK: - Callsign Header

    private var callsignHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(amber.opacity(0.15))
                    .frame(width: 34, height: 34)

                Image(systemName: "radio")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(amber)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Your Callsign")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(appState.localPeerName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Enhanced Status Pill

    private var enhancedStatusPill: some View {
        HStack(spacing: 10) {
            // Animated status dot
            Circle()
                .fill(connectionStatus.dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: connectionStatus.dotColor.opacity(0.6), radius: 4)

            Text(appState.localPeerName)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))

            Text("--")
                .font(.system(.caption2))
                .foregroundStyle(.secondary)

            Text(connectionStatus.text)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(connectionStatus.dotColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Channel List

    private var channelListView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if appState.channelManager.channels.isEmpty {
                    ChannelEmptyStateView()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.channelManager.channels) { channel in
                            NavigationLink {
                                ChannelView(channel: channel)
                            } label: {
                                channelCard(channel)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
            .refreshable {
                await refreshPeerDiscovery()
            }

            // FAB
            PulsingFAB(
                isEmpty: appState.channelManager.channels.isEmpty
            ) {
                showChannelCreation = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Channel Card

    private func channelCard(_ channel: ChirpChannel) -> some View {
        let isActive = appState.channelManager.activeChannel?.id == channel.id

        return HStack(spacing: 14) {
            // Channel icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(amber.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(amber)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    // Member count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(channel.peers.count)")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)

                    // Status dot
                    if isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(green)
                                .frame(width: 6, height: 6)
                            Text("Joined")
                                .font(.system(.caption, weight: .bold))
                                .foregroundStyle(green)
                        }
                    }
                }
            }

            Spacer()

            // Signal animation
            SignalBarsView(active: isActive)
                .padding(.trailing, 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isActive
                        ? amber.opacity(0.6)
                        : Color.white.opacity(0.06),
                    lineWidth: isActive ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isActive ? amber.opacity(0.1) : .clear,
            radius: 12,
            y: 4
        )
    }

    // MARK: - Refresh

    private func refreshPeerDiscovery() async {
        isRefreshing = true
        // Trigger a fresh peer discovery scan
        try? await Task.sleep(for: .seconds(1))
        let peers = await appState.peerTracker.connectedPeers
        connectedPeerCount = peers.count
        isRefreshing = false
    }
}

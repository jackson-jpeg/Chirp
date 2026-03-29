import SwiftUI

// MARK: - Glass Bar Header

private struct GlassHeaderBar: View {
    let callsign: String
    let peerCount: Int

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

    var body: some View {
        HStack(spacing: 12) {
            // Logo mark with perch birds
            HStack(spacing: 6) {
                PerchBirdsView(size: 36, isAnimating: true)
                    .frame(width: 36, height: 22)

                Text("ChirpChirp")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(amber)
            }

            Spacer()

            // Callsign
            Text(callsign)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.08))
                )

            // Peer count
            HStack(spacing: 5) {
                Circle()
                    .fill(peerCount > 0 ? green : Color.gray.opacity(0.4))
                    .frame(width: 7, height: 7)

                Text("\(peerCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(peerCount > 0 ? green : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        )
    }
}

// MARK: - Friend Avatar Bubble

private struct FriendAvatarBubble: View {
    let friend: ChirpFriend
    let action: () -> Void

    private let green = Color(hex: 0x30D158)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    // Avatar circle with initial
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorForName(friend.name),
                                    colorForName(friend.name).opacity(0.6),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(String(friend.name.prefix(1)).uppercased())
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )

                    // Online dot
                    if friend.isOnline {
                        Circle()
                            .fill(green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2.5)
                            )
                            .offset(x: 2, y: 2)
                    }
                }

                Text(friend.name.split(separator: " ").first.map(String.init) ?? friend.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(width: 64)
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Channel Card

private struct ChannelCard: View {
    let channel: ChirpChannel
    let isActive: Bool
    let friends: [ChirpFriend]

    @State private var borderPhase: CGFloat = 0.0
    @State private var pressed = false

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

    private var gradientColors: [Color] {
        let hash = abs(channel.name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.08).truncatingRemainder(dividingBy: 1.0)
        return [
            Color(hue: hue1, saturation: 0.4, brightness: 0.15),
            Color(hue: hue2, saturation: 0.35, brightness: 0.10),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: name + lock + live badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(channel.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if channel.accessMode == .locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    // Time since creation
                    Text(channel.createdAt.relativeDisplay)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                if isActive {
                    LiveBadge()
                }
            }

            // Bottom row: peer avatars + arrow
            HStack(spacing: 0) {
                // Stacked peer avatars
                peerAvatarStack

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .environment(\.colorScheme, .dark)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    isActive
                        ? amber.opacity(0.5 + Foundation.sin(borderPhase) * 0.3)
                        : Color.white.opacity(0.06),
                    lineWidth: isActive ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isActive ? amber.opacity(0.15) : Color.black.opacity(0.3),
            radius: isActive ? 20 : 10,
            y: 6
        )
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .onAppear {
            guard isActive else { return }
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                borderPhase = .pi * 2
            }
        }
    }

    @ViewBuilder
    private var peerAvatarStack: some View {
        let peerNames = channel.peers.prefix(4)
        let overflow = max(0, channel.peers.count - 4)

        HStack(spacing: -10) {
            ForEach(Array(peerNames.enumerated()), id: \.element.id) { index, peer in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                peerColor(peer.name),
                                peerColor(peer.name).opacity(0.6),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(String(peer.name.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .zIndex(Double(4 - index))
            }

            if overflow > 0 {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text("+\(overflow)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black, lineWidth: 2)
                    )
            }
        }
    }

    private func peerColor(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.6)
    }
}

// MARK: - Live Badge

private struct LiveBadge: View {
    @State private var glowing = false

    private let amber = Color(hex: 0xFFB800)

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: 0xFF3B30))
                .frame(width: 7, height: 7)
                .shadow(color: Color(hex: 0xFF3B30).opacity(glowing ? 0.8 : 0.2), radius: 4)

            Text("LIVE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: 0xFF3B30).opacity(0.2))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: 0xFF3B30).opacity(0.4), lineWidth: 0.5)
                )
        )
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                glowing = true
            }
        }
    }
}

// MARK: - Pulsing Glass FAB

private struct GlassFAB: View {
    let isEmpty: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.4

    private let amber = Color(hex: 0xFFB800)

    var body: some View {
        ZStack {
            if isEmpty {
                Circle()
                    .fill(amber.opacity(pulseOpacity))
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulseScale)
            }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 64, height: 64)
                    .background(
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [amber, Color(hex: 0xFFC830)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Circle()
                                .fill(.ultraThinMaterial.opacity(0.15))
                                .environment(\.colorScheme, .dark)
                        }
                    )
                    .clipShape(Circle())
                    .shadow(color: amber.opacity(0.5), radius: 20, y: 6)
            }
        }
        .onAppear {
            guard isEmpty else { return }
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.7
                pulseOpacity = 0.0
            }
        }
    }
}

// MARK: - Beautiful Empty State

private struct ChannelEmptyState: View {
    let onTap: () -> Void

    @State private var floatOffset: CGFloat = 0.0

    private let amber = Color(hex: 0xFFB800)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)

            // Perch birds mascot illustration
            PerchBirdsView(size: 160, isAnimating: true)
                .offset(y: floatOffset)

            Spacer()
                .frame(height: 32)

            VStack(spacing: 12) {
                Text("Create your first channel")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Channels let your group talk instantly.\nTap the card below to get started.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()
                .frame(height: 32)

            // Tappable card
            Button(action: onTap) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(amber.opacity(0.12))
                            .frame(width: 52, height: 52)

                        Image(systemName: "plus.bubble.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(amber)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("New Channel")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Start talking with friends nearby")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(amber.opacity(0.5))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(amber.opacity(0.15), lineWidth: 0.5)
                        )
                )
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
            ) {
                floatOffset = -8
            }
        }
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeDisplay: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
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
    @State private var showSOSConfirm = false
    @State private var sosHoldProgress: CGFloat = 0
    @State private var pendingMessageCount: Int = 0

    private let amber = Color(hex: 0xFFB800)
    private let green = Color(hex: 0x30D158)

    private var connectionStatus: ConnectionStatus {
        let mpPeers = appState.connectedPeerCount

        if mpPeers > 0 {
            return .connected(peerCount: mpPeers)
        }

        return .searching
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Glass header bar
                    GlassHeaderBar(
                        callsign: appState.callsign,
                        peerCount: appState.connectedPeerCount
                    )

                    // Friends quick-access row
                    if !appState.friendsManager.friends.isEmpty {
                        friendsQuickAccess
                    }

                    // Channel list or empty state
                    channelListView
                }

                // Emergency mode overlay — always on top
                EmergencyModeOverlay(emergencyMode: EmergencyMode.shared)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // SOS Emergency Button — requires long press to activate
                    SOSToolbarButton(showConfirm: $showSOSConfirm)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Voice messages indicator
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(pendingMessageCount > 0 ? amber : .secondary)

                            if pendingMessageCount > 0 {
                                Text("\(min(pendingMessageCount, 99))")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(
                                        Circle()
                                            .fill(Color(hex: 0xFF3B30))
                                    )
                                    .offset(x: 8, y: -8)
                            }
                        }

                        NavigationLink {
                            MeshMapView()
                        } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(amber)
                        }

                        NavigationLink {
                            FriendsView()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(amber)

                                if !appState.friendsManager.onlineFriends.isEmpty {
                                    Circle()
                                        .fill(green)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 3, y: -3)
                                }
                            }
                        }

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
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showChannelCreation) {
                ChannelCreationView()
            }
            .sheet(isPresented: $showPairing) {
                PairingView()
                    .onAppearAnimations()
            }
            .alert("Activate SOS Beacon?", isPresented: $showSOSConfirm) {
                Button("Send SOS", role: .destructive) {
                    activateSOS()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will broadcast an emergency signal to all nearby mesh devices. Use only in a real emergency.")
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

    // MARK: - Friends Quick Access

    private var friendsQuickAccess: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(
                    appState.friendsManager.friends.sorted { a, b in
                        // Online friends first
                        if a.isOnline != b.isOnline { return a.isOnline }
                        return a.name < b.name
                    }
                ) { friend in
                    FriendAvatarBubble(friend: friend) {
                        // Start direct channel with friend
                        showChannelCreation = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Channel List

    private var channelListView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                if appState.channelManager.channels.isEmpty {
                    ChannelEmptyState {
                        showChannelCreation = true
                    }
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.channelManager.channels) { channel in
                            let isActive = appState.channelManager.activeChannel?.id == channel.id

                            NavigationLink {
                                ChannelView(channel: channel)
                            } label: {
                                ChannelCard(
                                    channel: channel,
                                    isActive: isActive,
                                    friends: appState.friendsManager.friends
                                )
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        appState.channelManager.deleteChannel(id: channel.id)
                                    }
                                } label: {
                                    Label("Delete Channel", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
            }
            .refreshable {
                await refreshPeerDiscovery()
            }

            // FAB
            GlassFAB(
                isEmpty: appState.channelManager.channels.isEmpty
            ) {
                showChannelCreation = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Refresh

    private func refreshPeerDiscovery() async {
        isRefreshing = true
        try? await Task.sleep(for: .seconds(1))
        let peers = await appState.peerTracker.connectedPeers
        connectedPeerCount = peers.count
        isRefreshing = false
    }

    // MARK: - SOS

    private func activateSOS() {
        // Send an SOS control packet through the mesh with max TTL
        let sosPayload: [String: String] = [
            "type": "SOS",
            "from": appState.callsign,
            "peerID": appState.localPeerID,
            "time": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONEncoder().encode(sosPayload) else { return }

        Task {
            let packet = await appState.meshRouter.createPacket(
                type: .control,
                payload: data,
                channelID: "",  // Broadcast to all channels
                sequenceNumber: 0,
                priority: .critical  // SOS: maximum TTL and relay priority
            )
            // Forward to all peers
            appState.multipeerTransport.forwardPacket(packet.serialize(), excludePeer: "")
        }

        toast = ToastItem(message: "SOS beacon activated", type: .error)
    }
}

// MARK: - SOS Toolbar Button

/// A long-press-activated SOS button that prevents accidental triggers.
/// Shows red only when held; requires deliberate press to confirm.
private struct SOSToolbarButton: View {
    @Binding var showConfirm: Bool

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?

    private let holdDuration: TimeInterval = 1.5  // seconds to hold before confirming
    private let sosRed = Color(hex: 0xFF3B30)

    var body: some View {
        Button {
            // Tap does nothing -- must long press
        } label: {
            ZStack {
                // Background fill that grows with hold progress
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(sosRed, lineWidth: 2.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)

                Text("SOS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(isHolding ? .white : sosRed.opacity(0.6))
            }
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(isHolding ? sosRed.opacity(0.3) : Color.clear)
            )
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onChanged { _ in
                    startHold()
                }
                .onEnded { _ in
                    completeHold()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    cancelHold()
                }
        )
        .accessibilityLabel("SOS Emergency Beacon")
        .accessibilityHint("Long press for \(String(format: "%.1f", holdDuration)) seconds to activate emergency beacon")
    }

    private func startHold() {
        isHolding = true
        holdProgress = 0
        holdTimer?.invalidate()

        let interval: TimeInterval = 0.05
        let steps = holdDuration / interval
        nonisolated(unsafe) var currentStep: Double = 0

        holdTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            currentStep += 1
            let progress = CGFloat(currentStep / steps)
            DispatchQueue.main.async {
                withAnimation(.linear(duration: interval)) {
                    holdProgress = progress
                }
            }
            if currentStep >= steps {
                timer.invalidate()
            }
        }
    }

    private func completeHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        isHolding = false
        holdProgress = 0
        showConfirm = true
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
            holdProgress = 0
        }
    }
}

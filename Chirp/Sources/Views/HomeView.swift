import SwiftUI

// MARK: - Glass Header Bar (Revamped)

private struct GlassHeaderBar: View {
    let callsign: String
    let peerCount: Int

    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Logo mark — larger, more prominent
                HStack(spacing: 8) {
                    PerchBirdsView(size: 44, isAnimating: true)
                        .frame(width: 44, height: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ChirpChirp")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Constants.Colors.amber)

                        Text(callsign)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer()

                // Mesh node count — prominent with animated pulse
                HStack(spacing: 6) {
                    ZStack {
                        if peerCount > 0 {
                            Circle()
                                .fill(Constants.Colors.electricGreen.opacity(pulseOpacity * 0.5))
                                .frame(width: 14, height: 14)
                        }
                        Circle()
                            .fill(peerCount > 0 ? Constants.Colors.electricGreen : Color.gray.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }

                    Text(peerCount > 0
                         ? String(localized: "home.header.nodesInMesh \(peerCount)")
                         : String(localized: "home.header.noMesh")
                    )
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(peerCount > 0 ? Constants.Colors.electricGreen : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            Capsule()
                                .stroke(
                                    peerCount > 0
                                        ? Constants.Colors.electricGreen.opacity(0.2)
                                        : Color.white.opacity(0.06),
                                    lineWidth: 0.5
                                )
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.clear,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            )
        }
        .onAppear {
            guard peerCount > 0 else { return }
            withAnimation(
                .easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: true)
            ) {
                pulseOpacity = 0.15
            }
        }
    }
}

// MeshStatusBar removed — replaced by ProtectStatusBar (see Components/ProtectStatusBar.swift)

// MARK: - Friend Avatar Bubble

private struct FriendAvatarBubble: View {
    let friend: ChirpFriend
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
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

                    if friend.isOnline {
                        Circle()
                            .fill(Constants.Colors.electricGreen)
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
        .accessibilityLabel("\(friend.name), \(friend.isOnline ? "online" : "offline")")
        .frame(width: 64)
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Channel Card (Enhanced)

private struct ChannelCard: View {
    let channel: ChirpChannel
    let isActive: Bool
    let friends: [ChirpFriend]
    let unreadCount: Int

    @State private var borderPhase: CGFloat = 0.0
    @State private var glowIntensity: Double = 0.0

    private var gradientColors: [Color] {
        let hash = abs(channel.name.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.08).truncatingRemainder(dividingBy: 1.0)
        return [
            Color(hue: hue1, saturation: 0.4, brightness: 0.15),
            Color(hue: hue2, saturation: 0.35, brightness: 0.10),
        ]
    }

    private var channelAccessibilityLabel: String {
        var parts = [channel.name]
        parts.append("\(channel.activePeerCount) peer\(channel.activePeerCount == 1 ? "" : "s")")
        if channel.accessMode == .locked {
            parts.append("locked")
        }
        if isActive {
            parts.append("currently active")
        }
        if unreadCount > 0 {
            parts.append("\(unreadCount) unread")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: name + lock + badges
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

                    // Time since creation + hop indicator
                    HStack(spacing: 10) {
                        Text(channel.createdAt.relativeDisplay)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))

                        // Mesh hop reach indicator
                        HStack(spacing: 3) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(channel.activePeerCount) peer\(channel.activePeerCount == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Constants.Colors.amber.opacity(0.5))
                    }
                }

                Spacer()

                // Badges column
                VStack(alignment: .trailing, spacing: 6) {
                    if isActive {
                        LiveBadge()
                    }

                    if unreadCount > 0 {
                        UnreadBadge(count: unreadCount)
                    }
                }
            }

            // Bottom row: peer avatars + arrow
            HStack(spacing: 0) {
                peerAvatarStack

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(channelAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.channelCard)
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
                        ? Constants.Colors.amber.opacity(0.6 + glowIntensity * 0.3)
                        : Color.white.opacity(0.06),
                    lineWidth: isActive ? 2.0 : 0.5
                )
        )
        .shadow(
            color: isActive ? Constants.Colors.amber.opacity(0.2 + glowIntensity * 0.15) : Color.black.opacity(0.3),
            radius: isActive ? 24 : 10,
            y: 6
        )
        .onAppear {
            guard isActive else { return }
            withAnimation(
                .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
            ) {
                glowIntensity = 1.0
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

// MARK: - Unread Badge

private struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(min(count, 99))\(count > 99 ? "+" : "")")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Constants.Colors.amber)
            )
            .accessibilityLabel("\(count) unread message\(count == 1 ? "" : "s")")
    }
}

// MARK: - Live Badge

private struct LiveBadge: View {
    @State private var glowing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Constants.Colors.hotRed)
                .frame(width: 7, height: 7)
                .shadow(color: Constants.Colors.hotRed.opacity(glowing ? 0.8 : 0.2), radius: 4)

            Text("LIVE")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Constants.Colors.hotRed.opacity(0.2))
                .overlay(
                    Capsule()
                        .stroke(Constants.Colors.hotRed.opacity(0.4), lineWidth: 0.5)
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

// MARK: - Mesh Network Illustration (Empty State)

private struct MeshNetworkIllustration: View {
    @State private var nodePositions: [(CGFloat, CGFloat)] = [
        (0.2, 0.3), (0.5, 0.15), (0.8, 0.35),
        (0.35, 0.65), (0.65, 0.7), (0.5, 0.5),
    ]
    @State private var lineOpacity: Double = 0.0
    @State private var nodeScale: CGFloat = 0.0

    var body: some View {
        ZStack {
            // Connection lines
            Canvas { context, size in
                let points = nodePositions.map { CGPoint(x: $0.0 * size.width, y: $0.1 * size.height) }
                let connections: [(Int, Int)] = [
                    (0, 5), (1, 5), (2, 5), (3, 5), (4, 5),
                    (0, 1), (1, 2), (3, 4), (0, 3),
                ]

                for (a, b) in connections {
                    var path = Path()
                    path.move(to: points[a])
                    path.addLine(to: points[b])
                    context.stroke(
                        path,
                        with: .color(Constants.Colors.amber.opacity(lineOpacity * 0.3)),
                        lineWidth: 1
                    )
                }
            }

            // Nodes
            ForEach(0..<nodePositions.count, id: \.self) { index in
                let pos = nodePositions[index]
                let isCenter = index == 5
                Circle()
                    .fill(
                        isCenter
                            ? Constants.Colors.amber.opacity(0.8)
                            : Constants.Colors.amber.opacity(0.4)
                    )
                    .frame(width: isCenter ? 12 : 8, height: isCenter ? 12 : 8)
                    .shadow(color: Constants.Colors.amber.opacity(0.4), radius: isCenter ? 8 : 4)
                    .scaleEffect(nodeScale)
                    .position(
                        x: pos.0 * 180,
                        y: pos.1 * 120
                    )
            }
        }
        .frame(width: 180, height: 120)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                nodeScale = 1.0
            }
            withAnimation(.easeIn(duration: 1.2).delay(0.5)) {
                lineOpacity = 1.0
            }
        }
    }
}

// MARK: - Enhanced Empty State

private struct ChannelEmptyState: View {
    let onTap: () -> Void

    @State private var floatOffset: CGFloat = 0.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Mesh network illustration
            MeshNetworkIllustration()
                .offset(y: floatOffset)

            Spacer()
                .frame(height: 20)

            // Perch birds mascot
            PerchBirdsView(size: 120, isAnimating: true)
                .offset(y: floatOffset * 0.6)

            Spacer()
                .frame(height: 28)

            VStack(spacing: 12) {
                Text(String(localized: "home.emptyState.title"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(String(localized: "home.emptyState.subtitle"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()
                .frame(height: 36)

            // CTA card
            Button(action: onTap) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Constants.Colors.amber.opacity(0.15))
                            .frame(width: 52, height: 52)

                        Image(systemName: "plus.bubble.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Constants.Colors.amber)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "home.emptyState.createChannel"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(String(localized: "home.emptyState.createChannelSubtitle"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Constants.Colors.amber.opacity(0.7))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Constants.Colors.amber.opacity(0.2), lineWidth: 0.5)
                        )
                )
                .shadow(color: Constants.Colors.amber.opacity(0.1), radius: 16, y: 4)
            }
            .padding(.horizontal, 20)
            .accessibilityLabel("Create your first channel")

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

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.12))
                        .frame(width: 50, height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(color.opacity(0.15), lineWidth: 0.5)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Bottom Quick Actions

private struct BottomQuickActions: View {
    let onNewChannel: () -> Void
    let onSOS: () -> Void
    let gatewayAvailable: Bool
    let onGateway: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            QuickActionButton(
                icon: "plus.bubble.fill",
                label: String(localized: "home.quickAction.newChannel"),
                color: Constants.Colors.amber,
                action: onNewChannel
            )

            Spacer()

            QuickActionButton(
                icon: "sos",
                label: "SOS",
                color: Constants.Colors.hotRed,
                action: onSOS
            )

            if gatewayAvailable {
                Spacer()

                QuickActionButton(
                    icon: "antenna.radiowaves.left.and.right",
                    label: String(localized: "home.quickAction.gateway"),
                    color: Constants.Colors.electricGreen,
                    action: onGateway
                )
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 14)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                }
        )
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

// MARK: - SOS Toolbar Button

/// A long-press-activated SOS button that prevents accidental triggers.
/// Shows red only when held; requires deliberate press to confirm.
private struct SOSToolbarButton: View {
    @Binding var showConfirm: Bool

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?

    private let holdDuration: TimeInterval = 1.5

    var body: some View {
        Button {
            // Tap does nothing -- must long press
        } label: {
            ZStack {
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Constants.Colors.hotRed, lineWidth: 2.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)

                Text("SOS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(isHolding ? .white : Constants.Colors.hotRed.opacity(0.6))
            }
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(isHolding ? Constants.Colors.hotRed.opacity(0.3) : Color.clear)
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

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var showChannelCreation = false
    @State private var showPairing = false
    @State private var showGatewayMessage = false
    @State private var toast: ToastItem?
    @State private var connectedPeerCount = 0
    @State private var isRefreshing = false
    @State private var showSOSConfirm = false
    @State private var sosHoldProgress: CGFloat = 0
    @State private var pendingMessageCount: Int = 0
    @State private var selectedTab: HomeTab = .channels
    @Namespace private var tabAnimation

    private enum HomeTab: String, CaseIterable {
        case channels = "Channels"
        case protect = "Protect"
        case files = "Files"
    }

    private var connectionStatus: ConnectionStatus {
        let mpPeers = appState.connectedPeerCount

        if mpPeers > 0 {
            return .connected(peerCount: mpPeers)
        }

        return .searching
    }

    // MARK: - Tab Picker

    private var homeTabPicker: some View {
        HStack(spacing: Constants.Layout.smallSpacing) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Constants.Colors.amber)
                                    .matchedGeometryEffect(id: "tabIndicator", in: tabAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.vertical, 10)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Deep dark background with subtle navy gradient
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.06),
                        Color.black,
                        Color(red: 0.01, green: 0.01, blue: 0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Glass header bar
                    GlassHeaderBar(
                        callsign: appState.callsign,
                        peerCount: appState.connectedPeerCount
                    )

                    // Protect status bar
                    ProtectStatusBar(
                        peerCount: appState.connectedPeerCount,
                        threatCount: appState.bleScanner.threatDevices.count,
                        isScanning: appState.bleScanner.isScanning,
                        isEmergencyActive: EmergencyMode.shared.isActive
                    )

                    // Tab picker
                    homeTabPicker

                    // Tab content
                    switch selectedTab {
                    case .channels:
                        // Friends quick-access row
                        if !appState.friendsManager.friends.isEmpty {
                            friendsQuickAccess
                        }

                        // Channel list or empty state
                        channelListView

                    case .protect:
                        ProtectTabView()

                    case .files:
                        FilesTabView()
                    }

                    // Bottom quick actions
                    BottomQuickActions(
                        onNewChannel: { showChannelCreation = true },
                        onSOS: { showSOSConfirm = true },
                        gatewayAvailable: MeshGateway.shared.gatewayAvailable,
                        onGateway: { showGatewayMessage = true }
                    )
                }

                // Emergency mode overlay -- always on top
                EmergencyModeOverlay(emergencyMode: EmergencyMode.shared)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MeshMapView()
                    } label: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Constants.Colors.amber)
                    }
                    .accessibilityLabel("Mesh Map")
                    .accessibilityIdentifier(AccessibilityID.meshMapButton)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier(AccessibilityID.settingsButton)
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
            .sheet(isPresented: $showGatewayMessage) {
                GatewayMessageView(
                    localPeerID: appState.localPeerID,
                    localPeerName: appState.localPeerName
                )
            }
            .alert(String(localized: "home.sos.alertTitle"), isPresented: $showSOSConfirm) {
                Button(String(localized: "home.sos.sendButton"), role: .destructive) {
                    activateSOS()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "home.sos.alertMessage"))
            }
            .chirpToast($toast)
            .onChange(of: appState.proximityAlert.recentAlerts.count) { _, _ in
                if let latest = appState.proximityAlert.recentAlerts.last {
                    toast = ToastItem(message: "\(latest.friendName) is \(latest.distance)!", type: .info)
                }
            }
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
        VStack(spacing: 0) {
            // Section header with "See All" link
            HStack {
                Text(String(localized: "home.friends.title"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))

                if !appState.friendsManager.onlineFriends.isEmpty {
                    Text(String(localized: "home.friends.online \(appState.friendsManager.onlineFriends.count)"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Constants.Colors.electricGreen.opacity(0.7))
                }

                Spacer()

                NavigationLink {
                    FriendsView()
                } label: {
                    Text(String(localized: "home.friends.seeAll"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Constants.Colors.amber.opacity(0.7))
                }
                .accessibilityLabel("See all friends")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(
                        appState.friendsManager.friends.sorted { a, b in
                            if a.isOnline != b.isOnline { return a.isOnline }
                            return a.name < b.name
                        }
                    ) { friend in
                        FriendAvatarBubble(friend: friend) {
                            showChannelCreation = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
        )
    }

    // MARK: - Channel List

    private var channelListView: some View {
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
                                friends: appState.friendsManager.friends,
                                unreadCount: appState.textMessageService.unreadCount(for: channel.id)
                            )
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    appState.channelManager.deleteChannel(id: channel.id)
                                }
                            } label: {
                                Label(String(localized: "home.channel.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .refreshable {
            await refreshPeerDiscovery()
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
                channelID: "",
                sequenceNumber: 0,
                priority: .critical
            )
            appState.multipeerTransport.forwardPacket(packet.serialize(), excludePeer: "")
        }

        toast = ToastItem(message: "SOS beacon activated", type: .error)
    }
}

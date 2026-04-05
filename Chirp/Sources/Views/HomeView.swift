import SwiftUI

// MARK: - Compact Header

private struct CompactHeader: View {
    let callsign: String
    let peerCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(callsign)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500)
                        .frame(width: 7, height: 7)

                    Text(peerCount > 0
                         ? String(localized: "home.header.nodesInMesh \(peerCount)")
                         : String(localized: "home.header.noMesh")
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate400)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Inline Status Strip

private struct InlineStatusStrip: View {
    let peerCount: Int
    let threatCount: Int
    let isScanning: Bool
    let isEmergencyActive: Bool

    private var threatColor: Color {
        if threatCount == 0 { return Constants.Colors.electricGreen }
        if threatCount <= 2 { return Constants.Colors.amber }
        return Constants.Colors.hotRed
    }

    private var modeText: String {
        if isEmergencyActive { return "EMERGENCY" }
        if isScanning { return "Scanning" }
        return "Normal"
    }

    private var modeColor: Color {
        if isEmergencyActive { return Constants.Colors.emergencyRed }
        if isScanning { return Constants.Colors.amber }
        return Constants.Colors.electricGreen
    }

    var body: some View {
        HStack(spacing: 16) {
            statusPill(
                icon: "antenna.radiowaves.left.and.right",
                text: "\(peerCount) peer\(peerCount == 1 ? "" : "s")",
                color: peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500
            )

            statusPill(
                icon: "shield.fill",
                text: "\(threatCount) threat\(threatCount == 1 ? "" : "s")",
                color: threatColor
            )

            statusPill(
                icon: "circle.fill",
                text: modeText,
                color: modeColor,
                iconSize: 6
            )

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func statusPill(icon: String, text: String, color: Color, iconSize: CGFloat = 11) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)
        }
    }
}

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
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(friend.name.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )

                    if friend.isOnline {
                        Circle()
                            .fill(Constants.Colors.electricGreen)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Constants.Colors.slate900, lineWidth: 2)
                            )
                            .offset(x: 1, y: 1)
                    }
                }

                Text(friend.name.split(separator: " ").first.map(String.init) ?? friend.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Constants.Colors.slate400)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(friend.name), \(friend.isOnline ? "online" : "offline")")
        .frame(width: 60)
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Channel Card (Liquid Glass)

private struct ChannelCard: View {
    let channel: ChirpChannel
    let isActive: Bool
    let friends: [ChirpFriend]
    let unreadCount: Int

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
        HStack(spacing: 14) {
            // Channel icon
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Constants.Colors.blue500.opacity(0.15) : Constants.Colors.slate700.opacity(0.6))
                    .frame(width: 50, height: 50)

                Image(systemName: channel.accessMode == .locked ? "lock.fill" : "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? Constants.Colors.blue500 : Constants.Colors.slate400)
            }

            // Channel info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(channel.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if isActive {
                        Circle()
                            .fill(Constants.Colors.electricGreen)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(channel.activePeerCount) peer\(channel.activePeerCount == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.slate400)

                    Text("\u{00B7}")
                        .foregroundStyle(Constants.Colors.slate600)

                    Text(channel.createdAt.relativeDisplay)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.slate500)
                }
            }

            Spacer()

            // Right side: unread badge or chevron
            VStack(alignment: .trailing, spacing: 6) {
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))\(unreadCount > 99 ? "+" : "")")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Constants.Colors.blue500)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.Colors.slate600)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(channelAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.channelCard)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isActive ? Constants.Colors.blue500.opacity(0.3) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
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

// MARK: - Empty State (Redesigned)

private struct ChannelEmptyState: View {
    let peerCount: Int
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 48)

            // Device readiness card
            VStack(spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Constants.Colors.slate500)

                VStack(spacing: 8) {
                    Text(String(localized: "home.emptyState.title"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(String(localized: "home.emptyState.subtitle"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.Colors.slate400)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                // Readiness indicators
                VStack(spacing: 12) {
                    readinessRow(icon: "wifi", label: "Wi-Fi Direct", ready: true)
                    readinessRow(icon: "antenna.radiowaves.left.and.right", label: "Mesh Network", ready: peerCount > 0)
                    readinessRow(icon: "lock.shield.fill", label: "Encryption", ready: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Constants.Colors.slate800.opacity(0.5))
                )
            }
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 32)

            // Create channel button
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))

                    Text(String(localized: "home.emptyState.createChannel"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Constants.Colors.blue500)
                )
            }
            .padding(.horizontal, 40)
            .accessibilityLabel("Create your first channel")

            Spacer()
        }
    }

    private func readinessRow(icon: String, label: String, ready: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)

            Spacer()

            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ready ? Constants.Colors.electricGreen : Constants.Colors.slate600)
        }
    }
}

// MARK: - SOS Toolbar Button

/// A long-press-activated SOS button that prevents accidental triggers.
/// Shows red only when held; requires deliberate press to confirm.
private struct SOSToolbarButton: View {
    @Binding var showConfirm: Bool

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

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
        holdTask?.cancel()

        let interval: Duration = .milliseconds(50)
        let totalSteps = holdDuration / 0.05

        holdTask = Task { @MainActor in
            var currentStep: Double = 0
            while !Task.isCancelled, currentStep < totalSteps {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                currentStep += 1
                let progress = CGFloat(currentStep / totalSteps)
                withAnimation(.linear(duration: 0.05)) {
                    holdProgress = progress
                }
            }
        }
    }

    private func completeHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        holdProgress = 0
        showConfirm = true
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
            holdProgress = 0
        }
    }
}

// MARK: - Home Tab Enum

enum HomeTab: String, CaseIterable {
    case talk = "Talk"
    case messages = "Messages"
    case map = "Map"
    case more = "More"

    var icon: String {
        switch self {
        case .talk: return "waveform"
        case .messages: return "bubble.left.and.bubble.right"
        case .map: return "map"
        case .more: return "ellipsis"
        }
    }
}

// MARK: - Bottom Navigation Bar

private struct BottomNavBar: View {
    @Binding var selectedTab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Constants.Colors.amber : Constants.Colors.slate500)

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? Constants.Colors.amber : Constants.Colors.slate500)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Constants.Colors.slate700.opacity(0.5))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }
}

// MARK: - Channel Selector Pill

private struct ChannelSelectorPill: View {
    let channels: [ChirpChannel]
    let activeChannel: ChirpChannel?
    let onSelect: (ChirpChannel) -> Void
    let onCreate: () -> Void

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)

                Text(activeChannel?.name ?? "No Channel")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Constants.Colors.slate400)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Constants.Colors.slate800)
                    .overlay(
                        Capsule()
                            .stroke(Constants.Colors.slate700, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Channel: \(activeChannel?.name ?? "None"). Tap to switch.")
        .confirmationDialog("Switch Channel", isPresented: $showPicker) {
            ForEach(channels) { channel in
                Button(channel.name) {
                    onSelect(channel)
                }
            }
            Button("New Channel") {
                onCreate()
            }
            Button("Cancel", role: .cancel) {}
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
    @State private var showPermissionAlert = false
    @State private var permissionAlert: AppState.PermissionDeniedAlert?
    @State private var selectedTab: HomeTab = .talk
    @State private var pttState: PTTState = .idle
    @State private var inputLevel: Float = 0.0
    @State private var transmitStartTime: Date?

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
                // Dark blue-black background
                Constants.Colors.slate900
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Compact header with callsign + mesh status
                    CompactHeader(
                        callsign: appState.callsign,
                        peerCount: appState.connectedPeerCount
                    )

                    // Tab content
                    tabContent

                    // Bottom navigation bar
                    BottomNavBar(selectedTab: $selectedTab)
                }

                // FAB for new channel (messages tab only)
                if selectedTab == .messages {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                showChannelCreation = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Constants.Colors.blue500)
                                            .shadow(color: Constants.Colors.blue500.opacity(0.4), radius: 12, y: 4)
                                    )
                            }
                            .accessibilityLabel("New Channel")
                            .padding(.trailing, 20)
                            .padding(.bottom, 80) // space for bottom nav
                        }
                    }
                }

                // Emergency mode overlay -- always on top
                EmergencyModeOverlay(emergencyMode: EmergencyMode.shared)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            MeshMapView()
                        } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Constants.Colors.slate400)
                        }
                        .accessibilityLabel("Mesh Map")
                        .accessibilityIdentifier(AccessibilityID.meshMapButton)

                        if MeshGateway.shared.gatewayAvailable {
                            Button {
                                showGatewayMessage = true
                            } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Constants.Colors.electricGreen)
                            }
                            .accessibilityLabel("Gateway")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SOSToolbarButton(showConfirm: $showSOSConfirm)
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
            .onChange(of: appState.permissionDeniedAlert) { _, newAlert in
                if let alert = newAlert {
                    permissionAlert = alert
                    showPermissionAlert = true
                    appState.permissionDeniedAlert = nil
                }
            }
            .alert(permissionAlert?.title ?? "", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    appState.openAppSettings()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(permissionAlert?.message ?? "")
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .chirpPTTShortcutTriggered)) { _ in
                // Action Button / Shortcut triggered — switch to Talk tab
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = .talk
                }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .talk:
            pttHomeContent

        case .messages:
            // Inline status strip
            InlineStatusStrip(
                peerCount: appState.connectedPeerCount,
                threatCount: appState.bleScanner.threatDevices.count,
                isScanning: appState.bleScanner.isScanning,
                isEmergencyActive: EmergencyMode.shared.isActive
            )

            // Friends quick-access row
            if !appState.friendsManager.friends.isEmpty {
                friendsQuickAccess
            }

            // Channel list or empty state
            channelListView

        case .map:
            GeoMapView(
                userLocation: appState.locationService.currentLocation?.coordinate,
                peers: []
            )

        case .more:
            MoreView()
        }
    }

    // MARK: - PTT Home Content

    private var pttHomeContent: some View {
        VStack(spacing: 0) {
            // Channel selector
            ChannelSelectorPill(
                channels: appState.channelManager.channels,
                activeChannel: appState.channelManager.activeChannel,
                onSelect: { channel in
                    appState.channelManager.joinChannel(id: channel.id)
                },
                onCreate: {
                    showChannelCreation = true
                }
            )
            .padding(.top, 12)

            Spacer()

            // PTT button — large, centered
            PTTButtonView(
                pttState: $pttState,
                onPressDown: {
                    guard appState.micPermissionGranted else {
                        Task { await appState.requestMicPermission() }
                        return
                    }
                    HapticsManager.shared.pttDown()
                    SoundEffects.shared.playChirpBegin()
                    transmitStartTime = Date()
                    appState.pttEngine.startTransmitting()
                },
                onPressUp: {
                    guard appState.micPermissionGranted else { return }
                    HapticsManager.shared.pttUp()
                    SoundEffects.shared.playChirpEnd()
                    transmitStartTime = nil
                    appState.pttEngine.stopTransmitting()
                }
            )

            Spacer()

            // Peer count + status indicator
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.connectedPeerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500)
                        .frame(width: 8, height: 8)

                    Text("\(appState.connectedPeerCount) nearby")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Constants.Colors.slate400)
                }

                if EmergencyMode.shared.isActive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Constants.Colors.emergencyRed)
                            .frame(width: 8, height: 8)

                        Text("EMERGENCY")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Constants.Colors.emergencyRed)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .onChange(of: appState.pttState) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                pttState = newValue
            }
        }
        .onChange(of: appState.inputLevel) { _, newValue in
            inputLevel = newValue
        }
    }

    // MARK: - Friends Quick Access

    private var friendsQuickAccess: some View {
        VStack(spacing: 0) {
            // Section header with "See All" link
            HStack {
                Text(String(localized: "home.friends.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.Colors.slate400)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if !appState.friendsManager.onlineFriends.isEmpty {
                    Text(String(localized: "home.friends.online \(appState.friendsManager.onlineFriends.count)"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Constants.Colors.electricGreen.opacity(0.8))
                }

                Spacer()

                NavigationLink {
                    FriendsView()
                } label: {
                    Text(String(localized: "home.friends.seeAll"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.blue500)
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
    }

    // MARK: - Channel List

    private var channelListView: some View {
        ScrollView {
            if appState.channelManager.channels.isEmpty {
                ChannelEmptyState(peerCount: appState.connectedPeerCount) {
                    showChannelCreation = true
                }
            } else {
                LazyVStack(spacing: 8) {
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
                .padding(.top, 12)
                .padding(.bottom, 80) // space for FAB
            }
        }
        .refreshable {
            await refreshPeerDiscovery()
        }
    }

    // MARK: - Refresh

    private func refreshPeerDiscovery() async {
        isRefreshing = true

        // Restart multipeer advertising + browsing to force fresh discovery
        appState.multipeerTransport.stop()
        appState.multipeerTransport.start()

        // Brief pause so peers have time to reconnect
        try? await Task.sleep(for: .seconds(1))

        // Refresh local peer count
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

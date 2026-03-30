import SwiftUI

struct ChannelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let channel: ChirpChannel

    @State private var pttState: PTTState = .idle
    @State private var inputLevel: Float = 0.0
    @State private var toast: ToastItem?
    @State private var transmitStartTime: Date?
    @State private var meshPhase: CGFloat = 0
    @State private var channelMode: ChannelMode = .talk
    @State private var hasUsedPTT: Bool = false
    @State private var showHoldHint: Bool = true
    @State private var showPairingSheet: Bool = false
    @State private var showCameraPicker: Bool = false

    enum ChannelMode: CaseIterable {
        case talk
        case chat

        var label: String {
            switch self {
            case .talk: return String(localized: "channel.mode.talk")
            case .chat: return String(localized: "channel.mode.chat")
            }
        }
    }

    // MARK: - Layout Constants

    private let pttButtonSize: CGFloat = 160
    private let peerCircleRadius: CGFloat = 145
    private let peerAvatarSize: CGFloat = 52
    private let waveformRadius: CGFloat = 100

    // MARK: - Body

    // MARK: - Unread Badge

    private var chatUnreadCount: Int {
        appState.textMessageService.unreadCount(for: channel.id)
    }

    var body: some View {
        ZStack {
            // Animated mesh background
            animatedMeshBackground

            // Vignette color tint at edges
            vignetteOverlay

            VStack(spacing: 0) {
                // Minimal channel header
                channelHeader
                    .padding(.horizontal, Constants.Layout.horizontalPadding)
                    .padding(.top, Constants.Layout.smallSpacing)

                // Mode picker: Talk | Chat
                modePicker
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .padding(.bottom, Constants.Layout.smallSpacing)

                Group {
                    if channelMode == .talk {
                        // Existing PTT UI
                        talkModeContent
                    } else {
                        // Chat UI
                        chatModeContent
                            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: channelMode)
            }

            // Transcript overlay — slides down from top when receiving
            TranscriptOverlayView(transcription: appState.liveTranscription)
        }
        .debugOverlay()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
                .accessibilityLabel("Back")
            }
            // Show "Boost" pairing button when Wi-Fi Aware is available
            if appState.wifiAwareTransport != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPairingSheet = true
                    } label: {
                        Image(systemName: "wifi")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Constants.Colors.amber)
                    }
                    .accessibilityLabel("Boost connection with Wi-Fi Aware pairing")
                }
            }
        }
        .sheet(isPresented: $showPairingSheet) {
            PairingView()
                .environment(appState)
        }
        .sheet(isPresented: $showCameraPicker) {
            ImagePickerView(source: .camera) { image in
                sendCameraImage(image)
            }
        }
        .chirpToast($toast)
        .onAppear {
            if appState.channelManager.activeChannel?.id != channel.id {
                appState.channelManager.joinChannel(id: channel.id)
            }
        }
        .onChange(of: appState.pttState) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                pttState = newValue
            }
            appState.updateLiveActivity()
        }
        .onChange(of: appState.inputLevel) { _, newValue in
            inputLevel = newValue
            if pttState == .transmitting || isReceiving {
                appState.updateLiveActivity()
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ChannelMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        channelMode = mode
                    }
                    if mode == .chat {
                        appState.textMessageService.markAsRead(channelID: channel.id)
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Text(mode.label.uppercased())
                            .font(Constants.Typography.caption)
                            .tracking(2)
                            .foregroundStyle(channelMode == mode ? .white : Constants.Colors.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                if channelMode == mode {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Constants.Colors.blue500, Constants.Colors.blue600],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .shadow(color: Constants.Colors.blue500.opacity(0.4), radius: 8)
                                }
                            }

                        // Unread badge on Chat tab
                        if mode == .chat && channelMode != .chat && chatUnreadCount > 0 {
                            Text("\(min(chatUnreadCount, 99))")
                                .font(Constants.Typography.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Constants.Colors.hotRed))
                                .offset(x: -4, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.label) mode\(channelMode == mode ? ", selected" : "")")
                .accessibilityHint(mode == .chat && chatUnreadCount > 0 ? "\(chatUnreadCount) unread message\(chatUnreadCount == 1 ? "" : "s")" : "")
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Constants.Colors.surfaceGlass)
                .overlay(
                    Capsule()
                        .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: Constants.Layout.glassBorderWidth)
                )
        )
    }

    // MARK: - Talk Mode Content

    private var talkModeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Status pill — floats higher
            statusPill
                .padding(.bottom, Constants.Layout.spacing)

            // Quick replies — tap to send as text message
            QuickReplyBar(replies: appState.quickReplyManager.replies) { reply in
                appState.textMessageService.send(
                    text: reply.label,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.callsign
                )
                toast = ToastItem(message: "Sent: \(reply.label)", type: .success)
            }
            .padding(.bottom, Constants.Layout.spacing)

            // Idle birds — friendly waiting state above waveform
            if pttState == .idle {
                PerchBirdsView(size: 100, isAnimating: true)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .padding(.bottom, Constants.Layout.smallSpacing)
            }

            // Central composition: peers around waveform around PTT
            centralComposition
                .padding(.bottom, Constants.Layout.smallSpacing)

            // "Hold to Talk" / "Release to stop" hint
            pttHintText
                .padding(.bottom, Constants.Layout.spacing)

            // Quick action icons
            quickActionBar
                .padding(.bottom, Constants.Layout.spacing)

            // Loopback indicator
            loopbackIndicator

            Spacer()
                .frame(height: 32)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    // MARK: - Chat Mode Content

    private var chatModeContent: some View {
        ChatView(
            channelID: channel.id,
            localPeerID: appState.localPeerID,
            localPeerName: appState.localPeerName,
            messages: appState.textMessageService.messages(for: channel.id),
            onSend: { text, replyToID in
                appState.textMessageService.send(
                    text: text,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.localPeerName,
                    replyToID: replyToID
                )
            },
            onShareLocation: {
                guard let location = appState.locationService.currentLocation else {
                    toast = ToastItem(message: "Location unavailable", type: .warning)
                    return
                }
                let locText = LocationService.encodeLocation(location)
                appState.textMessageService.send(
                    text: locText,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.callsign,
                    attachmentType: .location
                )
                toast = ToastItem(message: "Location shared", type: .success)
            },
            onSendImage: { payload in
                appState.textMessageService.send(
                    text: payload,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.callsign,
                    attachmentType: .image
                )
                toast = ToastItem(message: "Image sent", type: .success)
            },
            onSendFile: { fileURL in
                guard let fileData = try? Data(contentsOf: fileURL) else {
                    toast = ToastItem(message: "Could not read file", type: .warning)
                    return
                }
                guard fileData.count <= FileTransferService.maxFileSize else {
                    let maxMB = FileTransferService.maxFileSize / 1_048_576
                    toast = ToastItem(message: "File too large (max \(maxMB) MB)", type: .warning)
                    return
                }
                let fileName = fileURL.lastPathComponent
                let mimeType = fileURL.mimeType
                appState.fileTransferService.sendFile(
                    fileData,
                    fileName: fileName,
                    mimeType: mimeType,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.callsign
                )
                toast = ToastItem(message: "Sending \(fileName)...", type: .info)
            },
            cicadaService: appState.cicadaService
        )
    }

    // MARK: - Animated Mesh Background

    private var animatedMeshBackground: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Base: deep black
                let baseRect = CGRect(origin: .zero, size: size)
                context.fill(Path(baseRect), with: .color(.black))

                // State-dependent colors
                let (color1, color2, color3) = meshColors(for: pttState)

                // Animated mesh blobs — large soft radial gradients that drift
                let cx = size.width / 2
                let cy = size.height / 2

                // Blob 1: upper-left drift
                let b1x = cx * 0.6 + sin(time * 0.3) * cx * 0.25
                let b1y = cy * 0.4 + cos(time * 0.25) * cy * 0.2
                drawMeshBlob(context: context, center: CGPoint(x: b1x, y: b1y),
                             radius: size.width * 0.55, color: color1, opacity: 0.12)

                // Blob 2: lower-right drift
                let b2x = cx * 1.3 + cos(time * 0.35) * cx * 0.2
                let b2y = cy * 1.4 + sin(time * 0.28) * cy * 0.15
                drawMeshBlob(context: context, center: CGPoint(x: b2x, y: b2y),
                             radius: size.width * 0.5, color: color2, opacity: 0.10)

                // Blob 3: center drift
                let b3x = cx + sin(time * 0.22 + 1.5) * cx * 0.15
                let b3y = cy * 0.8 + cos(time * 0.18 + 0.7) * cy * 0.12
                drawMeshBlob(context: context, center: CGPoint(x: b3x, y: b3y),
                             radius: size.width * 0.45, color: color3, opacity: 0.08)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: pttState)
        .accessibilityHidden(true)
    }

    private func meshColors(for state: PTTState) -> (Color, Color, Color) {
        switch state {
        case .idle:
            return (
                Color(hex: 0x1A2040), // navy
                Color(hex: 0x1E1E2E), // charcoal blue
                Color(hex: 0x15192D)  // deep navy
            )
        case .transmitting:
            return (
                Color(hex: 0x3A1520), // crimson
                Color(hex: 0x2E1018), // dark crimson
                Color(hex: 0x401825)  // deep red
            )
        case .receiving:
            return (
                Color(hex: 0x0F2E1A), // emerald
                Color(hex: 0x122815), // dark green
                Color(hex: 0x0A3320)  // deep emerald
            )
        case .denied:
            return (
                Color(hex: 0x1A1A1E),
                Color(hex: 0x151518),
                Color(hex: 0x121215)
            )
        }
    }

    private func drawMeshBlob(
        context: GraphicsContext, center: CGPoint,
        radius: CGFloat, color: Color, opacity: Double
    ) {
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let gradient = Gradient(colors: [
            color.opacity(opacity),
            color.opacity(opacity * 0.5),
            Color.clear
        ])
        context.fill(
            Circle().path(in: rect),
            with: .radialGradient(gradient, center: center,
                                  startRadius: 0, endRadius: radius)
        )
    }

    // MARK: - Vignette Overlay

    private var vignetteOverlay: some View {
        ZStack {
            // Edge vignette — always present
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.black.opacity(0.5)
                ]),
                center: .center,
                startRadius: 200,
                endRadius: 500
            )
            .ignoresSafeArea()

            // State color tint at edges
            if pttState == .transmitting {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Constants.Colors.hotRed.opacity(0.15)
                    ]),
                    center: .center,
                    startRadius: 180,
                    endRadius: 500
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if isReceiving {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Constants.Colors.electricGreen.opacity(0.10)
                    ]),
                    center: .center,
                    startRadius: 180,
                    endRadius: 500
                )
                .ignoresSafeArea()
                .transition(.opacity)

                // Green edge glow when receiving
                Rectangle()
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0)
                            .strokeBorder(
                                Constants.Colors.electricGreen.opacity(0.2),
                                lineWidth: 2
                            )
                            .blur(radius: 12)
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: pttState)
        .accessibilityHidden(true)
    }

    // MARK: - Channel Header (Minimal)

    private var channelHeader: some View {
        HStack(spacing: Constants.Layout.smallSpacing) {
            Text(channel.name)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Constants.Colors.textPrimary)

            if channel.accessMode == .locked {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(Constants.Typography.badge)
                }
                .foregroundStyle(Constants.Colors.amber)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Constants.Colors.glassAmber)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Constants.Colors.glassAmberBorder, lineWidth: 0.5)
                )
                .accessibilityLabel("Locked channel")
            }

            // Mesh reach indicator
            meshReachLabel

            Spacer()

            // Peer count pill
            peerCountPill
        }
        .accessibilityElement(children: .combine)
    }

    private var meshReachLabel: some View {
        let beacon = appState.meshBeacon
        let hops = max(1, beacon.maxHopDepth)
        let range = beacon.estimatedRange > 0 ? beacon.estimatedRange : 80

        return Text("~\(range)m | \(hops) hop\(hops == 1 ? "" : "s")")
            .font(Constants.Typography.monoSmall)
            .foregroundStyle(Constants.Colors.textTertiary)
    }

    private var peerCountPill: some View {
        let count = appState.channelManager.activeChannel?.activePeerCount ?? 0

        return HStack(spacing: 5) {
            Circle()
                .fill(count > 0 ? Constants.Colors.electricGreen : Color.gray)
                .frame(width: 6, height: 6)

            Text("\(count) peer\(count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Constants.Colors.surfaceGlass)
        )
        .overlay(
            Capsule()
                .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appState.channelManager.activeChannel?.activePeerCount ?? 0) peer\((appState.channelManager.activeChannel?.activePeerCount ?? 0) == 1 ? "" : "s") connected")
        .accessibilityIdentifier(AccessibilityID.peerCountPill)
    }

    // MARK: - Status Pill (Floating Glass)

    private var statusPill: some View {
        let stateColor = statusAccentColor
        let isActive = pttState != .idle

        return statusPillContent
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Constants.Colors.surfaceGlass)
                    .overlay(
                        Capsule()
                            .fill(stateColor.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [stateColor.opacity(0.4), Constants.Colors.surfaceBorder, stateColor.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: Constants.Layout.glassBorderWidth
                            )
                    )
            )
            .shadow(color: stateColor.opacity(isActive ? 0.3 : 0.1), radius: 16, y: 4)
            .animation(.easeInOut(duration: 0.2), value: pttState)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusAccessibilityLabel)
            .accessibilityIdentifier(AccessibilityID.statusPill)
    }

    private var statusAccessibilityLabel: String {
        switch pttState {
        case .idle:
            return "Status: Ready"
        case .transmitting:
            return "Status: Transmitting live"
        case .receiving(let name, _):
            return "Status: Receiving from \(name)"
        case .denied:
            return "Status: Channel busy"
        }
    }

    @ViewBuilder
    private var statusPillContent: some View {
        switch pttState {
        case .idle:
            HStack(spacing: Constants.Layout.smallSpacing) {
                Circle()
                    .fill(Constants.Colors.blue500)
                    .frame(width: 6, height: 6)
                Text(String(localized: "channel.status.ready"))
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.blue500)
            }

        case .transmitting:
            transmittingPillContent

        case .receiving(let name, _):
            HStack(spacing: Constants.Layout.smallSpacing) {
                Circle()
                    .fill(Constants.Colors.electricGreen)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "channel.status.listening"))
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.electricGreen.opacity(0.6))
                    Text(name)
                        .font(Constants.Typography.body)
                        .foregroundStyle(Constants.Colors.electricGreen)
                }
            }

        case .denied:
            HStack(spacing: Constants.Layout.smallSpacing) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
                Text(String(localized: "channel.status.busy"))
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textSecondary)
            }
        }
    }

    private var transmittingPillContent: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let elapsed = transmitStartTime.map { timeline.date.timeIntervalSince($0) } ?? 0
            let seconds = Int(elapsed) % 60
            let minutes = Int(elapsed) / 60
            let pulse = sin(timeline.date.timeIntervalSinceReferenceDate * 4.0) * 0.4 + 0.6

            HStack(spacing: 8) {
                Circle()
                    .fill(Constants.Colors.hotRed)
                    .frame(width: 6, height: 6)
                    .opacity(pulse)

                Text(String(format: "%d:%02d", minutes, seconds))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(Constants.Colors.hotRed)
                    .contentTransition(.numericText())

                Text(String(localized: "channel.status.live"))
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Constants.Colors.hotRed))
            }
        }
    }

    private var statusAccentColor: Color {
        switch pttState {
        case .idle: Constants.Colors.blue500
        case .transmitting: Constants.Colors.hotRed
        case .receiving: Constants.Colors.electricGreen
        case .denied: Color.gray
        }
    }

    // MARK: - Central Composition

    private var centralComposition: some View {
        let livePeers = appState.channelManager.activeChannel?.peers ?? []

        return ZStack {
            // Circular waveform wrapping around the PTT button
            CircularWaveformView(
                inputLevel: pttState == .idle ? Float(0.05) : inputLevel,
                pttState: pttState,
                radius: waveformRadius
            )

            // Peer avatars arranged in a circle
            peerCircleLayout(peers: livePeers)

            // PTT button at dead center
            PTTButtonView(
                pttState: $pttState,
                onPressDown: {
                    guard appState.micPermissionGranted else {
                        HapticsManager.shared.denied()
                        toast = ToastItem(
                            message: "Microphone access required. Enable in Settings.",
                            type: .error
                        )
                        return
                    }
                    HapticsManager.shared.pttDown()
                    SoundEffects.shared.playChirpBegin()
                    transmitStartTime = Date()
                    if !hasUsedPTT {
                        withAnimation(.easeOut(duration: 0.3)) {
                            hasUsedPTT = true
                        }
                    }
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

            // Empty state radar when no peers
            if livePeers.isEmpty {
                emptyRadarOverlay
            }
        }
        .frame(width: peerCircleRadius * 2 + peerAvatarSize + 20,
               height: peerCircleRadius * 2 + peerAvatarSize + 20)
    }

    // MARK: - Peer Circle Layout

    @ViewBuilder
    private func peerCircleLayout(peers: [ChirpPeer]) -> some View {
        let connectedPeers = peers.filter(\.isConnected)

        ForEach(Array(connectedPeers.enumerated()), id: \.element.id) { index, peer in
            let angle = peerAngle(index: index, total: connectedPeers.count)
            let isActive = isActiveSpeaker(peer)

            VStack(spacing: 4) {
                PeerAvatarView(
                    peer: peer,
                    isActiveSpeaker: isActive,
                    linkQuality: appState.wifiAwareLinkMetrics[peer.id]
                )
                .scaleEffect(isActive ? 1.3 : 1.0)
                .shadow(
                    color: isActive
                        ? Constants.Colors.electricGreen.opacity(0.6)
                        : Color.clear,
                    radius: isActive ? 20 : 0
                )
                .shadow(
                    color: isActive
                        ? Constants.Colors.electricGreen.opacity(0.3)
                        : Color.clear,
                    radius: isActive ? 8 : 0
                )
                .overlay(
                    isActive
                        ? Circle()
                            .strokeBorder(Constants.Colors.electricGreen.opacity(0.4), lineWidth: 2)
                            .scaleEffect(1.35)
                            .modifier(StatusPulsingDot())
                        : nil
                )

                Text(peer.name.split(separator: " ").first.map(String.init) ?? peer.name)
                    .font(.system(size: isActive ? 11 : 10, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(
                        isActive
                            ? Constants.Colors.electricGreen
                            : Constants.Colors.textSecondary
                    )
                    .lineLimit(1)
            }
            .offset(
                x: cos(angle) * peerCircleRadius,
                y: sin(angle) * peerCircleRadius
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.5), value: connectedPeers.count)
        }
    }

    /// Calculate angle for a peer in the circle.
    /// 1 peer: top (above button). 2 peers: left and right. 3+: evenly spaced starting from top.
    private func peerAngle(index: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }

        switch total {
        case 1:
            // Directly above
            return -.pi / 2.0
        case 2:
            // Left and right
            let positions: [Double] = [-.pi, 0]
            return positions[index]
        default:
            // Evenly spaced, starting from top
            let startAngle = -.pi / 2.0
            return startAngle + (2.0 * .pi * Double(index) / Double(total))
        }
    }

    // MARK: - Empty Radar Overlay

    private var emptyRadarOverlay: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Smooth pulsing radar rings — staggered
                ForEach(0..<4, id: \.self) { ring in
                    let phase = (time * 0.35 + Double(ring) * 0.25)
                        .truncatingRemainder(dividingBy: 1.0)
                    let scale = 0.2 + phase * 0.8
                    let opacity = max(0, 0.20 - phase * 0.20)

                    Circle()
                        .strokeBorder(
                            Constants.Colors.blue500.opacity(opacity),
                            lineWidth: 0.8
                        )
                        .frame(width: peerCircleRadius * 2, height: peerCircleRadius * 2)
                        .scaleEffect(scale)
                }

                // Sweeping radar line
                let sweepAngle = Angle(radians: time * 1.2)
                Circle()
                    .trim(from: 0, to: 0.08)
                    .stroke(
                        Constants.Colors.blue500.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: peerCircleRadius * 1.6, height: peerCircleRadius * 1.6)
                    .rotationEffect(sweepAngle)

                VStack(spacing: 6) {
                    Text(String(localized: "channel.radar.scanning"))
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.blue500.opacity(0.6))

                    Text(String(localized: "channel.radar.peersHint"))
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }
                .offset(y: -peerCircleRadius - 20)
            }
        }
    }

    // MARK: - Loopback Indicator

    @ViewBuilder
    private var loopbackIndicator: some View {
        if appState.pttEngine.loopbackMode {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text(String(localized: "channel.loopback.on"))
                    .font(.system(.caption2, weight: .medium))
            }
            .foregroundStyle(Constants.Colors.amber.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Constants.Colors.surfaceGlass)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 0.5)
            )
            .padding(.bottom, Constants.Layout.smallSpacing)
        }
    }

    // MARK: - PTT Hint Text

    @ViewBuilder
    private var pttHintText: some View {
        if pttState == .idle && showHoldHint && !hasUsedPTT {
            Text(String(localized: "channel.ptt.holdToTalk"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Constants.Colors.textTertiary)
                .transition(.opacity)
        } else if pttState == .transmitting {
            Text(String(localized: "channel.ptt.releaseToStop"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Constants.Colors.hotRed.opacity(0.45))
                .transition(.opacity)
        }
    }

    // MARK: - Quick Action Bar

    private func sendCameraImage(_ image: UIImage) {
        guard let compressed = ImageCompressor.compress(image) else {
            toast = ToastItem(message: "Image compression failed", type: .warning)
            return
        }
        let base64 = compressed.base64EncodedString()
        let payload = MeshTextMessage.imagePrefix + base64
        guard payload.count <= MeshTextMessage.maxImagePayloadLength else {
            toast = ToastItem(message: "Image too large to send", type: .warning)
            return
        }
        appState.textMessageService.send(
            text: payload,
            channelID: channel.id,
            senderID: appState.localPeerID,
            senderName: appState.callsign,
            attachmentType: .image
        )
        toast = ToastItem(message: "Photo shared", type: .success)
    }

    private var quickActionBar: some View {
        HStack(spacing: Constants.Layout.horizontalPadding) {
            quickActionButton(
                icon: "camera.fill",
                label: String(localized: "channel.quickAction.camera"),
                color: Constants.Colors.slate400,
                size: 48
            ) {
                showCameraPicker = true
            }
            .accessibilityIdentifier(AccessibilityID.quickActionCamera)

            quickActionButton(
                icon: "text.bubble.fill",
                label: String(localized: "channel.quickAction.chat"),
                color: Constants.Colors.slate400,
                size: 48
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    channelMode = .chat
                }
                appState.textMessageService.markAsRead(channelID: channel.id)
            }
            .accessibilityIdentifier(AccessibilityID.quickActionChat)

            quickActionButton(
                icon: "location.fill",
                label: String(localized: "channel.quickAction.location"),
                color: Constants.Colors.blue500,
                size: 48
            ) {
                guard let location = appState.locationService.currentLocation else {
                    toast = ToastItem(message: "Location unavailable", type: .warning)
                    return
                }
                let locText = LocationService.encodeLocation(location)
                appState.textMessageService.send(
                    text: locText,
                    channelID: channel.id,
                    senderID: appState.localPeerID,
                    senderName: appState.callsign,
                    attachmentType: .location
                )
                toast = ToastItem(message: "Location shared", type: .success)
            }
            .accessibilityIdentifier(AccessibilityID.quickActionLocation)

            quickActionButton(
                icon: EmergencyBeacon.shared.isActive ? "xmark.circle.fill" : "sos",
                label: EmergencyBeacon.shared.isActive ? "STOP SOS" : String(localized: "channel.quickAction.sos"),
                color: Constants.Colors.hotRed,
                size: 48
            ) {
                if EmergencyBeacon.shared.isActive {
                    EmergencyBeacon.shared.deactivate()
                    toast = ToastItem(message: "SOS beacon stopped", type: .info)
                } else {
                    HapticsManager.shared.denied()
                    EmergencyBeacon.shared.activate(
                        senderID: appState.localPeerID,
                        senderName: appState.callsign
                    )
                    toast = ToastItem(message: "SOS BEACON ACTIVE — broadcasting every 5s", type: .warning)
                }
            }
            .accessibilityIdentifier(AccessibilityID.quickActionSOS)
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
    }

    private func quickActionButton(
        icon: String,
        label: String,
        color: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(Constants.Colors.surfaceGlass)
                        .overlay(
                            RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                .fill(color.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                .strokeBorder(color.opacity(0.2), lineWidth: Constants.Layout.glassBorderWidth)
                        )
                        .frame(width: size, height: size)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                .shadow(color: color.opacity(0.15), radius: 8, y: 2)

                Text(label)
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .accessibilityLabel(label)
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

// MARK: - StatusPulsingDot Modifier

private struct StatusPulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

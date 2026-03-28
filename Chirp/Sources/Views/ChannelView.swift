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

    // MARK: - Layout Constants

    private let pttButtonSize: CGFloat = 160
    private let peerCircleRadius: CGFloat = 145
    private let peerAvatarSize: CGFloat = 52
    private let waveformRadius: CGFloat = 100

    // MARK: - Body

    var body: some View {
        ZStack {
            // Animated mesh background
            animatedMeshBackground

            // Vignette color tint at edges
            vignetteOverlay

            VStack(spacing: 0) {
                // Minimal channel header
                channelHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // Status pill
                statusPill
                    .padding(.bottom, 24)

                // Central composition: peers around waveform around PTT
                centralComposition
                    .padding(.bottom, 24)

                // Loopback indicator
                loopbackIndicator

                Spacer()
                    .frame(height: 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
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
            }
        }
        .animation(.easeInOut(duration: 0.4), value: pttState)
    }

    // MARK: - Channel Header (Minimal)

    private var channelHeader: some View {
        HStack(spacing: 8) {
            Text(channel.name)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(.white)

            if channel.accessMode == .locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()
        }
    }

    // MARK: - Status Pill (Floating Glass)

    private var statusPill: some View {
        HStack(spacing: 8) {
            switch pttState {
            case .idle:
                Circle()
                    .fill(Constants.Colors.amber)
                    .frame(width: 6, height: 6)
                Text("Ready")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)

            case .transmitting:
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

                        Text("LIVE")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Constants.Colors.hotRed)
                            )
                            .opacity(pulse)
                    }
                }

            case .receiving(let name, _):
                Circle()
                    .fill(Constants.Colors.electricGreen)
                    .frame(width: 6, height: 6)
                Text("Listening to \(name)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Constants.Colors.electricGreen)

            case .denied:
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
                Text("Channel busy")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        )
        .overlay(
            Capsule()
                .strokeBorder(statusAccentColor.opacity(0.2), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.2), value: pttState)
    }

    private var statusAccentColor: Color {
        switch pttState {
        case .idle: Constants.Colors.amber
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
                    isActiveSpeaker: isActive
                )
                .scaleEffect(isActive ? 1.25 : 1.0)
                .shadow(
                    color: isActive
                        ? Constants.Colors.electricGreen.opacity(0.5)
                        : Color.clear,
                    radius: isActive ? 16 : 0
                )

                Text(peer.name.split(separator: " ").first.map(String.init) ?? peer.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        isActive
                            ? Constants.Colors.electricGreen
                            : .white.opacity(0.6)
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Pulsing radar rings
                ForEach(0..<3, id: \.self) { ring in
                    let phase = (time * 0.5 + Double(ring) * 0.33)
                        .truncatingRemainder(dividingBy: 1.0)
                    let scale = 0.3 + phase * 0.7
                    let opacity = max(0, 0.25 - phase * 0.25)

                    Circle()
                        .strokeBorder(
                            Constants.Colors.amber.opacity(opacity),
                            lineWidth: 1
                        )
                        .frame(width: peerCircleRadius * 2, height: peerCircleRadius * 2)
                        .scaleEffect(scale)
                }

                VStack(spacing: 6) {
                    Text("Scanning...")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Constants.Colors.amber.opacity(0.6))

                    Text("Peers will orbit here")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
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
                Text("Loopback ON")
                    .font(.system(.caption2, weight: .medium))
            }
            .foregroundStyle(Constants.Colors.amber.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(0.4)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Constants.Colors.amber.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.bottom, 8)
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

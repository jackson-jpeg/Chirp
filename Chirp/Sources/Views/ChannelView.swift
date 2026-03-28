import SwiftUI

struct ChannelView: View {
    @Environment(AppState.self) private var appState

    let channel: ChirpChannel

    @State private var pttState: PTTState = .idle
    @State private var inputLevel: Float = 0.0
    @State private var toast: ToastItem?
    @State private var radarPhase: CGFloat = 0
    @State private var statusPulse: Bool = false

    private let peerGridColumns = [
        GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 16)
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            backgroundGradient

            // Vignette tint overlay
            vignetteOverlay

            // Main content
            VStack(spacing: 0) {
                // Channel header
                channelHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Status bar
                statusBar
                    .padding(.top, 10)

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.top, 8)

                // Peer grid
                ScrollView {
                    if channel.peers.isEmpty {
                        emptyPeersView
                            .padding(.top, 50)
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
                                            isActiveSpeaker(peer)
                                                ? Constants.Colors.electricGreen
                                                : .secondary
                                        )
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    }
                }

                Spacer(minLength: 0)

                // Waveform section — always visible, more prominent
                waveformSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                // PTT Button with pedestal
                pttSection
                    .padding(.bottom, 40)
                    .padding(.top, 8)
            }
        }
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
            if pttState == .transmitting || isReceiving {
                appState.updateLiveActivity()
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color.black

            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: 0x1A1A1E),
                    Color(hex: 0x0D0D0F),
                    Color.black
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Vignette

    private var vignetteOverlay: some View {
        ZStack {
            if pttState == .transmitting {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Constants.Colors.hotRed.opacity(0.12)
                    ]),
                    center: .center,
                    startRadius: 150,
                    endRadius: 450
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else if isReceiving {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Constants.Colors.electricGreen.opacity(0.08)
                    ]),
                    center: .center,
                    startRadius: 150,
                    endRadius: 450
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: pttState)
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
                animatedSignalIndicator

                // Peer count badge
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                    Text("\(channel.peers.count)")
                        .font(.system(.caption, weight: .bold))
                }
                .foregroundStyle(Constants.Colors.amber)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Constants.Colors.amber.opacity(0.15))
                )
            }
        }
    }

    // MARK: - Animated Signal Indicator

    private var animatedSignalIndicator: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 4.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = sin(time * 2.0) * 0.3 + 0.7
            SignalStrengthIndicator(level: 3)
                .opacity(pttState == .transmitting ? pulse : 1.0)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch pttState {
            case .idle:
                Circle()
                    .fill(Constants.Colors.amber)
                    .frame(width: 7, height: 7)
                Text("Ready to talk")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)

            case .transmitting:
                TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = sin(time * 4.0) * 0.4 + 0.6
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Constants.Colors.hotRed)
                            .frame(width: 7, height: 7)
                            .opacity(pulse)
                        Text("Transmitting...")
                            .font(.system(.caption, weight: .heavy))
                            .foregroundStyle(Constants.Colors.hotRed)

                        Text("LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Constants.Colors.hotRed)
                            )
                            .opacity(pulse)
                    }
                }

            case .receiving(let name, _):
                Circle()
                    .fill(Constants.Colors.electricGreen)
                    .frame(width: 7, height: 7)
                Text("Listening to \(name)")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Constants.Colors.electricGreen)

            case .denied:
                Circle()
                    .fill(Color.gray)
                    .frame(width: 7, height: 7)
                Text("Channel busy")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusBackgroundColor.opacity(0.1))
                .overlay(
                    Capsule()
                        .strokeBorder(statusBackgroundColor.opacity(0.2), lineWidth: 0.5)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: pttState)
    }

    private var statusBackgroundColor: Color {
        switch pttState {
        case .idle: return Constants.Colors.amber
        case .transmitting: return Constants.Colors.hotRed
        case .receiving: return Constants.Colors.electricGreen
        case .denied: return Color.gray
        }
    }

    // MARK: - Waveform Section

    private var waveformSection: some View {
        ZStack {
            // Grid/mesh background
            frequencyGridBackground
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 6) {
                // Waveform
                WaveformView(
                    inputLevel: max(0.15, inputLevel),
                    pttState: pttState
                )
                .frame(height: 120)
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Frequency Grid Background

    private var frequencyGridBackground: some View {
        Canvas { context, size in
            let gridColor = Color.white.opacity(0.03)

            // Horizontal lines
            let hLineCount = 8
            let hSpacing = size.height / CGFloat(hLineCount)
            for i in 0...hLineCount {
                let y = CGFloat(i) * hSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }

            // Vertical lines
            let vLineCount = 16
            let vSpacing = size.width / CGFloat(vLineCount)
            for i in 0...vLineCount {
                let x = CGFloat(i) * vSpacing
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }

            // Center line (brighter)
            let centerY = size.height / 2.0
            var centerPath = Path()
            centerPath.move(to: CGPoint(x: 0, y: centerY))
            centerPath.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(
                centerPath,
                with: .color(Color.white.opacity(0.07)),
                lineWidth: 0.5
            )
        }
    }

    // MARK: - PTT Section

    private var pttSection: some View {
        VStack(spacing: 0) {
            // Pedestal effect
            Ellipse()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.04),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 20)
                .offset(y: 10)

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
        }
    }

    // MARK: - Empty Peers (Radar Animation)

    private var emptyPeersView: some View {
        VStack(spacing: 20) {
            // Radar animation with "You" at center
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    // Pulsing radar rings
                    ForEach(0..<3, id: \.self) { ring in
                        let phase = (time * 0.6 + Double(ring) * 0.33)
                            .truncatingRemainder(dividingBy: 1.0)
                        let scale = 0.5 + phase * 1.2
                        let opacity = max(0, 0.35 - phase * 0.35)

                        Circle()
                            .strokeBorder(
                                Constants.Colors.amber.opacity(opacity),
                                lineWidth: 1.5
                            )
                            .frame(width: 100, height: 100)
                            .scaleEffect(scale)
                    }

                    // Center device
                    Circle()
                        .fill(Constants.Colors.amber.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 28))
                        .foregroundStyle(Constants.Colors.amber)
                }
                .frame(width: 160, height: 160)
            }

            Text("You")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Constants.Colors.amber)

            Text("Waiting for peers...")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Other devices running Chirp nearby\nwill appear here automatically")
                .font(.system(.caption))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
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

import SwiftUI

struct PeerAvatarView: View {
    var peer: ChirpPeer
    var isActiveSpeaker: Bool

    @State private var waveScale1: CGFloat = 1.0
    @State private var waveScale2: CGFloat = 1.0
    @State private var waveScale3: CGFloat = 1.0
    @State private var waveOpacity1: Double = 0.0
    @State private var waveOpacity2: Double = 0.0
    @State private var waveOpacity3: Double = 0.0
    @State private var previousLevel: Int = 0

    private let size: CGFloat = 56

    // MARK: - Gradient from name hash

    private var gradientColors: (Color, Color) {
        let hash = abs(peer.name.hashValue)
        let palette: [(Color, Color)] = [
            (Color(hex: 0xFF6B6B), Color(hex: 0xEE5A24)),
            (Color(hex: 0x4ECDC4), Color(hex: 0x0ABDE3)),
            (Color(hex: 0x45B7D1), Color(hex: 0x6C5CE7)),
            (Color(hex: 0xFFA07A), Color(hex: 0xFD79A8)),
            (Color(hex: 0x98D8C8), Color(hex: 0x55E6C1)),
            (Color(hex: 0xC39BD3), Color(hex: 0xA29BFE)),
            (Color(hex: 0x7FB3D8), Color(hex: 0x74B9FF)),
            (Color(hex: 0xF0B27A), Color(hex: 0xFDCB6E)),
        ]
        return palette[hash % palette.count]
    }

    // MARK: - Initials

    private var initials: String {
        let words = peer.name
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")

        if words.count >= 2,
           let first = words.first?.first,
           let last = words.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let name = words.first, name.count >= 2 {
            return String(name.prefix(2)).uppercased()
        } else {
            return String(peer.name.prefix(1)).uppercased()
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Sound wave rings for active speaker
            if isActiveSpeaker {
                waveRing(scale: $waveScale1, opacity: $waveOpacity1)
                waveRing(scale: $waveScale2, opacity: $waveOpacity2)
                waveRing(scale: $waveScale3, opacity: $waveOpacity3)
            }

            // Avatar circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [gradientColors.0, gradientColors.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(
                            isActiveSpeaker
                                ? Color(hex: 0x30D158).opacity(0.9)
                                : Color.white.opacity(0.1),
                            lineWidth: isActiveSpeaker ? 2.5 : 1
                        )
                )
                .shadow(
                    color: isActiveSpeaker
                        ? Color(hex: 0x30D158).opacity(0.3)
                        : Color.clear,
                    radius: 8
                )
                .saturation(peer.isConnected ? 1.0 : 0.0)
                .opacity(peer.isConnected ? 1.0 : 0.5)

            // Initials
            Text(initials)
                .font(.system(size: initials.count > 1 ? 18 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .opacity(peer.isConnected ? 1.0 : 0.5)

            // Disconnected "x" overlay
            if !peer.isConnected {
                Circle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: size, height: size)

                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }

            // Signal strength mini-indicator (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SignalStrengthIndicator(level: peer.signalStrength)
                        .scaleEffect(0.65)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 20, height: 20)
                        )
                }
            }
            .frame(width: size + 4, height: size + 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(peer.name), \(peer.isConnected ? "connected" : "disconnected")\(isActiveSpeaker ? ", speaking" : "")")
        .onAppear {
            if isActiveSpeaker {
                startWaveAnimation()
            }
        }
        .onChange(of: isActiveSpeaker) { _, active in
            if active {
                startWaveAnimation()
            } else {
                stopWaveAnimation()
            }
        }
    }

    // MARK: - Wave Ring

    @ViewBuilder
    private func waveRing(scale: Binding<CGFloat>, opacity: Binding<Double>) -> some View {
        Circle()
            .stroke(Color(hex: 0x30D158).opacity(opacity.wrappedValue), lineWidth: 2)
            .frame(width: size + 8, height: size + 8)
            .scaleEffect(scale.wrappedValue)
    }

    // MARK: - Animation

    private func startWaveAnimation() {
        // Staggered expanding rings
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
            waveScale1 = 1.5
            waveOpacity1 = 0.0
        }
        waveOpacity1 = 0.6

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                waveScale2 = 1.5
                waveOpacity2 = 0.0
            }
            waveOpacity2 = 0.6
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                waveScale3 = 1.5
                waveOpacity3 = 0.0
            }
            waveOpacity3 = 0.6
        }
    }

    private func stopWaveAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            waveScale1 = 1.0
            waveScale2 = 1.0
            waveScale3 = 1.0
            waveOpacity1 = 0.0
            waveOpacity2 = 0.0
            waveOpacity3 = 0.0
        }
    }
}

import SwiftUI

struct PeerAvatarView: View {
    var peer: ChirpPeer
    var isActiveSpeaker: Bool

    @State private var glowScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0

    private let size: CGFloat = 56

    private var backgroundColor: Color {
        let hash = abs(peer.name.hashValue)
        let colors: [Color] = [
            Color(hex: 0xFF6B6B),
            Color(hex: 0x4ECDC4),
            Color(hex: 0x45B7D1),
            Color(hex: 0xFFA07A),
            Color(hex: 0x98D8C8),
            Color(hex: 0xC39BD3),
            Color(hex: 0x7FB3D8),
            Color(hex: 0xF0B27A),
        ]
        return colors[hash % colors.count]
    }

    private var initial: String {
        String(peer.name.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            // Active speaker glow
            if isActiveSpeaker {
                Circle()
                    .fill(Color(hex: 0x30D158).opacity(glowOpacity))
                    .frame(width: size + 16, height: size + 16)
                    .blur(radius: 8)
                    .scaleEffect(glowScale)
            }

            // Avatar circle
            Circle()
                .fill(backgroundColor.gradient)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(
                            isActiveSpeaker ? Color(hex: 0x30D158) : Color.clear,
                            lineWidth: 2
                        )
                )

            // Initial letter
            Text(initial)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Signal indicator overlay (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SignalStrengthIndicator(level: peer.signalStrength)
                        .scaleEffect(0.7)
                }
            }
            .frame(width: size + 8, height: size + 8)

            // Connection indicator dot
            if !peer.isConnected {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(hex: 0xFF3B30))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 1.5)
                            )
                    }
                    Spacer()
                }
                .frame(width: size, height: size)
            }
        }
        .onAppear {
            if isActiveSpeaker {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    glowScale = 1.15
                    glowOpacity = 0.6
                }
            }
        }
        .onChange(of: isActiveSpeaker) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    glowScale = 1.15
                    glowOpacity = 0.6
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    glowScale = 1.0
                    glowOpacity = 0.0
                }
            }
        }
    }
}

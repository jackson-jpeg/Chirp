import SwiftUI

enum ConnectionStatus {
    case connected(peerCount: Int)
    case searching
    case disconnected

    var text: String {
        switch self {
        case .connected(let count):
            return count == 1 ? "1 peer" : "\(count) peers"
        case .searching:
            return "Searching..."
        case .disconnected:
            return "No peers"
        }
    }

    var icon: String {
        switch self {
        case .connected:
            return "antenna.radiowaves.left.and.right"
        case .searching:
            return "magnifyingglass"
        case .disconnected:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var dotColor: Color {
        switch self {
        case .connected:
            return Color(hex: 0x30D158)
        case .searching:
            return Color(hex: 0xFFB800)
        case .disconnected:
            return Color(hex: 0xFF3B30)
        }
    }
}

struct StatusPillView: View {
    var status: ConnectionStatus

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    @State private var previousStatus: String = ""

    var body: some View {
        HStack(spacing: 6) {
            // Animated status dot
            ZStack {
                // Pulse ring behind dot (searching only)
                if case .searching = status {
                    Circle()
                        .fill(status.dotColor.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                }

                Circle()
                    .fill(status.dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: status.dotColor.opacity(0.5), radius: 3)
            }
            .frame(width: 12, height: 12)

            Text(status.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection: \(status.text)")
        .animation(.easeInOut(duration: 0.3), value: statusKey)
        .onAppear {
            startPulseIfNeeded()
        }
        .onChange(of: statusKey) { _, newKey in
            resetPulse()
            startPulseIfNeeded()
        }
    }

    // MARK: - Pulse Animation

    private func startPulseIfNeeded() {
        guard case .searching = status else { return }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 2.2
            pulseOpacity = 0.0
        }
    }

    private func resetPulse() {
        pulseScale = 1.0
        pulseOpacity = 1.0
    }

    private var statusKey: String {
        switch status {
        case .connected(let count): return "connected-\(count)"
        case .searching: return "searching"
        case .disconnected: return "disconnected"
        }
    }
}

import SwiftUI

enum ConnectionStatus {
    case connected(peerCount: Int)
    case searching
    case disconnected

    var text: String {
        switch self {
        case .connected(let count):
            return count == 1 ? "Connected to 1 peer" : "Connected to \(count) peers"
        case .searching:
            return "Searching for devices..."
        case .disconnected:
            return "No devices paired"
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

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.dotColor)
                .frame(width: 8, height: 8)
                .opacity(pulseOpacity)

            Text(status.text)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .onAppear {
            if case .searching = status {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.3
                }
            }
        }
        .onChange(of: statusKey) { _, _ in
            pulseOpacity = 1.0
            if case .searching = status {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseOpacity = 0.3
                }
            }
        }
    }

    // Simple key to detect status type changes
    private var statusKey: String {
        switch status {
        case .connected: return "connected"
        case .searching: return "searching"
        case .disconnected: return "disconnected"
        }
    }
}

import SwiftUI

struct ProtectStatusBar: View {
    let peerCount: Int
    let threatCount: Int
    let isScanning: Bool
    let isEmergencyActive: Bool

    @State private var gradientOffset: CGFloat = 0
    @State private var pulseOpacity: Double = 0.6
    @State private var emergencyPulse: Bool = false

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
        HStack(spacing: 0) {
            // Peers section
            NavigationLink {
                MeshMapView()
            } label: {
                HStack(spacing: 6) {
                    ZStack {
                        if peerCount > 0 {
                            Circle()
                                .fill(Constants.Colors.electricGreen.opacity(pulseOpacity * 0.5))
                                .frame(width: 10, height: 10)
                        }
                        Circle()
                            .fill(peerCount > 0 ? Constants.Colors.electricGreen : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }

                    Text("\(peerCount) peer\(peerCount == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .accessibilityLabel("\(peerCount) mesh peer\(peerCount == 1 ? "" : "s"), tap for mesh map")

            separator

            // Threats section
            NavigationLink {
                RoomScannerView()
            } label: {
                HStack(spacing: 6) {
                    Text("\(threatCount) flagged")
                        .foregroundStyle(threatColor.opacity(0.8))
                }
            }
            .accessibilityLabel("\(threatCount) flagged device\(threatCount == 1 ? "" : "s"), tap for device scanner")

            separator

            // Mode section
            NavigationLink {
                EmergencySOSView()
            } label: {
                HStack(spacing: 6) {
                    Text(modeText)
                        .foregroundStyle(modeColor.opacity(isEmergencyActive ? (emergencyPulse ? 1.0 : 0.5) : 0.8))
                }
            }
            .accessibilityLabel("Mode: \(modeText), tap for emergency controls")

            Spacer()
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.5))

                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            modeColor.opacity(0.0),
                            modeColor.opacity(0.08),
                            modeColor.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: gradientOffset * geo.size.width)
                }
                .clipped()
            }
        )
        .onAppear {
            withAnimation(
                .linear(duration: 4.0)
                    .repeatForever(autoreverses: true)
            ) {
                gradientOffset = 0.6
            }

            if peerCount > 0 {
                withAnimation(
                    .easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: true)
                ) {
                    pulseOpacity = 0.15
                }
            }

            if isEmergencyActive {
                withAnimation(
                    .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true)
                ) {
                    emergencyPulse = true
                }
            }
        }
    }

    private var separator: some View {
        Text("  |  ")
            .foregroundStyle(.white.opacity(0.15))
    }
}

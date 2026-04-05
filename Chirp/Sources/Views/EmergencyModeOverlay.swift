import SwiftUI
import UIKit

/// Persistent red banner overlay shown when emergency mode is active.
///
/// Sits at the top of the screen over all other content. Tap to expand
/// for detailed status (location broadcast, SOS beacon, battery).
/// Pulsing red border draws attention.
struct EmergencyModeOverlay: View {
    @Environment(AppState.self) private var appState

    let emergencyMode: EmergencyMode

    @State private var isExpanded = false
    @State private var pulseOpacity: Double = 0.6
    @State private var borderGlow: Double = 0.4

    private let red = Constants.Colors.hotRed
    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        if emergencyMode.isActive {
            VStack(spacing: 0) {
                banner
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    }

                if isExpanded {
                    expandedDetails
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
            .ignoresSafeArea(edges: .horizontal)
            .allowsHitTesting(true)
            .onAppear { startPulseAnimation() }
        }
    }

    // MARK: - Compact Banner

    private var banner: some View {
        HStack(spacing: 10) {
            // Pulsing dot
            Circle()
                .fill(red)
                .frame(width: 8, height: 8)
                .opacity(pulseOpacity)

            Text(String(localized: "emergency.overlay.emergencyMode"))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .tracking(2)

            Spacer()

            // Battery percentage
            batteryLabel

            // Mesh node count
            HStack(spacing: 4) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10, weight: .bold))
                Text("\(appState.connectedPeerCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(amber)

            // Expand/collapse chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(Constants.Colors.hotRed.opacity(0.15))
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Constants.Colors.hotRed.opacity(0.3))
                        .frame(height: 1)
                }
        )
        .overlay(
            Rectangle()
                .stroke(red.opacity(borderGlow), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "emergency.overlay.bannerAccessibility"))
        .accessibilityHint(String(localized: "emergency.overlay.bannerHint"))
    }

    // MARK: - Expanded Details

    private var expandedDetails: some View {
        VStack(spacing: 12) {
            // Location broadcast status
            statusRow(
                icon: "location.fill",
                label: String(localized: "emergency.overlay.locationBroadcast"),
                value: emergencyMode.locationBroadcastInterval > 0
                    ? String(localized: "emergency.overlay.everySeconds \(Int(emergencyMode.locationBroadcastInterval))")
                    : String(localized: "emergency.overlay.disabled"),
                color: emergencyMode.locationBroadcastInterval > 0 ? green : .secondary
            )

            // SOS beacon status
            let beaconActive = EmergencyBeacon.shared.isActive
            statusRow(
                icon: "sos",
                label: String(localized: "emergency.overlay.sosBeacon"),
                value: beaconActive
                    ? String(localized: "emergency.overlay.broadcasting")
                    : String(localized: "emergency.overlay.standby"),
                color: beaconActive ? red : .secondary
            )

            // Audio quality
            statusRow(
                icon: "waveform",
                label: String(localized: "emergency.overlay.audioQuality"),
                value: emergencyMode.audioQuality == .emergency
                    ? String(localized: "emergency.overlay.audioLow")
                    : String(localized: "emergency.overlay.audioNormal"),
                color: amber
            )

            // Mesh relay
            statusRow(
                icon: "arrow.triangle.branch",
                label: String(localized: "emergency.overlay.meshRelay"),
                value: emergencyMode.shouldRelayEverything
                    ? String(localized: "emergency.overlay.relayAll")
                    : String(localized: "emergency.overlay.relayNormal"),
                color: emergencyMode.shouldRelayEverything ? green : .secondary
            )

            // TTL
            statusRow(
                icon: "arrow.up.and.down.and.sparkles",
                label: String(localized: "emergency.overlay.maxTTL"),
                value: String(localized: "emergency.overlay.hops \(emergencyMode.maxTTL)"),
                color: amber
            )

            // Deactivate button
            Button {
                emergencyMode.deactivate()
            } label: {
                Text(String(localized: "emergency.overlay.deactivate"))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(red.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(red.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
            .accessibilityLabel(String(localized: "emergency.overlay.deactivate"))
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Rectangle()
                        .fill(red.opacity(0.05))
                )
        )
    }

    // MARK: - Helpers

    private var batteryLabel: some View {
        let level = UIDevice.current.batteryLevel
        let percent = level >= 0 ? Int(level * 100) : -1

        return HStack(spacing: 4) {
            Image(systemName: batteryIcon(level))
                .font(.system(size: 10, weight: .bold))
            if percent >= 0 {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } else {
                Text("--%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(batteryColor(level))
    }

    private func statusRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func batteryIcon(_ level: Float) -> String {
        switch level {
        case 0.75...: return "battery.100"
        case 0.50...: return "battery.75"
        case 0.25...: return "battery.50"
        case 0.10...: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ level: Float) -> Color {
        switch level {
        case 0.20...: return green
        case 0.10...: return amber
        default: return red
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseOpacity = 0.2
        }
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            borderGlow = 0.8
        }
    }
}

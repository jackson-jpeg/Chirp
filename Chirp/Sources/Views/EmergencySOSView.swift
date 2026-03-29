import CoreLocation
import SwiftUI

// MARK: - Countdown Overlay

private struct CountdownOverlay: View {
    let secondsRemaining: Int
    let onCancel: () -> Void

    @State private var scale: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("ACTIVATING SOS")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundStyle(Constants.Colors.hotRed)
                    .tracking(4)

                Text("\(secondsRemaining)")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(Constants.Colors.hotRed)
                    .scaleEffect(scale)
                    .animation(.easeOut(duration: 0.3), value: scale)
                    .onChange(of: secondsRemaining) {
                        scale = 0.5
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            scale = 1.0
                        }
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            scale = 1.0
                        }
                    }

                Text("Press cancel to abort")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Button(action: onCancel) {
                    Text("CANCEL")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }
}

// MARK: - Pulsing SOS Button

private struct SOSButton: View {
    let isActive: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    @State private var innerGlow: Double = 0.3

    private let red = Constants.Colors.hotRed

    var body: some View {
        ZStack {
            // Outer pulse rings (when active).
            if isActive {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(red.opacity(pulseOpacity * (0.4 - Double(ring) * 0.12)), lineWidth: 2)
                        .frame(width: 200 + CGFloat(ring) * 40, height: 200 + CGFloat(ring) * 40)
                        .scaleEffect(pulseScale)
                }
            }

            // Glow ring.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [red.opacity(isActive ? 0.4 : 0.15), Color.clear],
                        center: .center,
                        startRadius: 60,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)

            // Main button.
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    red,
                                    red.opacity(0.8),
                                    Color(hex: 0xCC1100),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .shadow(color: red.opacity(isActive ? 0.8 : 0.4), radius: isActive ? 40 : 20)

                    // Inner highlight.
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                        .frame(width: 160, height: 160)

                    VStack(spacing: 4) {
                        Image(systemName: "sos")
                            .font(.system(size: 48, weight: .black))
                            .foregroundStyle(.white)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .tracking(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            guard isActive else { return }
            startPulseAnimation()
        }
        .onChange(of: isActive) {
            if isActive {
                startPulseAnimation()
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 1.3
            pulseOpacity = 0.0
        }
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            innerGlow = 0.6
        }
    }
}

// MARK: - Received SOS Alert Card

private struct SOSAlertCard: View {
    let alert: EmergencyBeacon.SOSMessage
    let distance: CLLocationDistance?
    let bearing: Double?

    private let red = Constants.Colors.hotRed
    private let amber = Constants.Colors.amber

    var body: some View {
        HStack(spacing: 14) {
            // Pulsing beacon icon.
            ZStack {
                Circle()
                    .fill(red.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.senderName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(alert.coordinateString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(amber.opacity(0.7))

                HStack(spacing: 12) {
                    if let distance {
                        Label(formatDistance(distance), systemImage: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Label(
                        "\(Int(alert.batteryLevel * 100))%",
                        systemImage: batteryIcon(alert.batteryLevel)
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(batteryColor(alert.batteryLevel))

                    Text(alert.timestamp, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            // Directional arrow.
            if let bearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(amber)
                    .rotationEffect(.degrees(bearing))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(red.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        }
        return String(format: "%.1fkm", meters / 1000)
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
        case 0.20...: return Constants.Colors.electricGreen
        case 0.10...: return amber
        default: return red
        }
    }
}

// MARK: - Emergency SOS View

struct EmergencySOSView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isCountingDown = false
    @State private var countdownSeconds = 3
    @State private var countdownTimer: Timer?
    @State private var vignetteOpacity: Double = 0.0

    private let red = Constants.Colors.hotRed
    private let amber = Constants.Colors.amber

    private var beacon: EmergencyBeacon { EmergencyBeacon.shared }

    var body: some View {
        ZStack {
            // Dark background.
            Color.black.ignoresSafeArea()

            // Red vignette when active.
            if beacon.isActive {
                RadialGradient(
                    colors: [Color.clear, red.opacity(vignetteOpacity)],
                    center: .center,
                    startRadius: 150,
                    endRadius: 500
                )
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 28) {
                    // Header.
                    headerSection

                    // SOS Button.
                    SOSButton(isActive: beacon.isActive) {
                        if beacon.isActive {
                            beacon.deactivate()
                        } else {
                            startCountdown()
                        }
                    }
                    .padding(.vertical, 16)

                    // Status info.
                    if beacon.isActive {
                        activeStatusSection
                    } else {
                        inactiveInfoSection
                    }

                    // GPS coordinates.
                    coordinateSection

                    // Received alerts from others.
                    if !beacon.receivedAlerts.isEmpty {
                        receivedAlertsSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            // Countdown overlay.
            if isCountingDown {
                CountdownOverlay(
                    secondsRemaining: countdownSeconds,
                    onCancel: cancelCountdown
                )
                .transition(.opacity)
            }
        }
        .navigationTitle("Emergency SOS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if beacon.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Deactivate") {
                        beacon.deactivate()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(red)
                }
            }
        }
        .onAppear {
            if beacon.isActive {
                startVignetteAnimation()
            }
        }
        .onChange(of: beacon.isActive) {
            if beacon.isActive {
                startVignetteAnimation()
            } else {
                vignetteOpacity = 0
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sos")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(red)

            Text("EMERGENCY BEACON")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(red.opacity(0.8))
                .tracking(3)

            Text(beacon.isActive
                 ? "Broadcasting SOS to mesh network"
                 : "Tap SOS to broadcast your location")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Active Status

    private var activeStatusSection: some View {
        VStack(spacing: 12) {
            // Broadcast count + mesh node count.
            HStack(spacing: 20) {
                statusPill(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Broadcasts",
                    value: "\(beacon.broadcastCount)",
                    color: red
                )

                statusPill(
                    icon: "point.3.connected.trianglepath.dotted",
                    label: "Mesh Nodes",
                    value: "\(appState.connectedPeerCount)",
                    color: amber
                )
            }

            // Battery level.
            let battery = UIDevice.current.batteryLevel
            if battery >= 0 {
                HStack(spacing: 8) {
                    Image(systemName: "battery.50")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(battery > 0.2 ? Constants.Colors.electricGreen : red)

                    Text("\(Int(battery * 100))% battery remaining")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Text("Broadcasting to \(appState.connectedPeerCount) mesh node\(appState.connectedPeerCount == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(red)
        }
    }

    // MARK: - Inactive Info

    private var inactiveInfoSection: some View {
        VStack(spacing: 16) {
            infoRow(icon: "antenna.radiowaves.left.and.right",
                    text: "Broadcasts every 5 seconds at max range (TTL 8)")
            infoRow(icon: "location.fill",
                    text: "Includes your GPS coordinates and battery level")
            infoRow(icon: "bell.badge.fill",
                    text: "All mesh devices show an alert with your location")
            infoRow(icon: "moon.fill",
                    text: "Continues broadcasting even when app is backgrounded")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(amber)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
    }

    // MARK: - Coordinates

    private var coordinateSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(amber)

                Text("CURRENT POSITION")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(amber.opacity(0.7))
                    .tracking(2)
            }

            if let location = beacon.lastLocation {
                Text(String(
                    format: "%.6f, %.6f",
                    location.coordinate.latitude,
                    location.coordinate.longitude
                ))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

                Text(String(format: "Altitude: %.0fm | Accuracy: %.0fm",
                            location.altitude, location.horizontalAccuracy))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text("Acquiring GPS signal...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(amber.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Received Alerts

    private var receivedAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(red)

                Text("INCOMING SOS ALERTS")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(red.opacity(0.8))
                    .tracking(2)

                Spacer()

                Text("\(beacon.receivedAlerts.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(red.opacity(0.15))
                    )
            }

            ForEach(beacon.receivedAlerts) { alert in
                SOSAlertCard(
                    alert: alert,
                    distance: beacon.distanceToSOS(alert),
                    bearing: beacon.bearingToSOS(alert)
                )
            }
        }
    }

    // MARK: - Helpers

    private func statusPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private func startCountdown() {
        countdownSeconds = 3
        isCountingDown = true

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                countdownSeconds -= 1
                if countdownSeconds <= 0 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                    isCountingDown = false
                    beacon.activate(
                        senderID: appState.localPeerID,
                        senderName: appState.callsign
                    )
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        isCountingDown = false
        countdownSeconds = 3
    }

    private func startVignetteAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            vignetteOpacity = 0.3
        }
    }
}

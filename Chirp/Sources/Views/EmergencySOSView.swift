import CoreLocation
import SwiftUI

// MARK: - Countdown Overlay

private struct CountdownOverlay: View {
    let secondsRemaining: Int
    let onCancel: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var vignetteIntensity: Double = 0.0

    private let red = Constants.Colors.emergencyRed

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            // Red vignette that intensifies as countdown progresses
            RadialGradient(
                colors: [Color.clear, red.opacity(vignetteIntensity)],
                center: .center,
                startRadius: 80,
                endRadius: 450
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text(String(localized: "emergency.countdown.activating"))
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(red)
                    .tracking(6)

                Text("\(secondsRemaining)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: red, radius: 30)
                    .shadow(color: red.opacity(0.5), radius: 60)
                    .scaleEffect(scale)
                    .animation(.easeOut(duration: 0.3), value: scale)
                    .onChange(of: secondsRemaining) {
                        scale = 0.5
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                            scale = 1.0
                        }
                        // Intensify vignette as countdown decreases
                        withAnimation(.easeInOut(duration: 0.8)) {
                            vignetteIntensity = Double(3 - secondsRemaining + 1) * 0.15
                        }
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                            scale = 1.0
                        }
                        vignetteIntensity = 0.1
                    }
                    .accessibilityLabel(String(localized: "emergency.countdown.secondsRemaining \(secondsRemaining)"))

                Text(String(localized: "emergency.countdown.cancelHint"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Button(action: onCancel) {
                    Text(String(localized: "emergency.countdown.cancel"))
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
                .accessibilityLabel(String(localized: "emergency.countdown.cancelAccessibility"))
                .accessibilityIdentifier(AccessibilityID.sosCancelButton)
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

    @State private var ringPhase: Double = 0
    @State private var innerGlow: Double = 0.3
    @State private var sosTextPulse: Double = 1.0

    private let red = Constants.Colors.emergencyRed

    var body: some View {
        ZStack {
            // Outer pulse rings (when active) — staggered expanding rings like PTT transmit
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for ring in 0..<4 {
                            let phase = (t * 0.6 + Double(ring) * 0.25)
                                .truncatingRemainder(dividingBy: 1.0)
                            let radius = 90.0 + phase * 80.0
                            let opacity = (1.0 - phase) * 0.35
                            let path = Path(ellipseIn: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            ))
                            context.stroke(
                                path,
                                with: .color(Color(hex: 0xCC0000).opacity(opacity)),
                                lineWidth: 2.5 - phase * 1.5
                            )
                        }
                    }
                }
                .frame(width: 340, height: 340)
                .allowsHitTesting(false)
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
                                    Constants.Colors.hotRed,
                                    red,
                                    Color(hex: 0x990000),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .shadow(color: red.opacity(isActive ? 0.9 : 0.4), radius: isActive ? 45 : 20)

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

                    // Warning stripes border when inactive
                    if !isActive {
                        Circle()
                            .stroke(Color.black.opacity(0.3), lineWidth: 3)
                            .frame(width: 160, height: 160)
                    }

                    VStack(spacing: 4) {
                        Image(systemName: "sos")
                            .font(.system(size: 48, weight: .black))
                            .foregroundStyle(.white)

                        if isActive {
                            Text(String(localized: "emergency.sos.active"))
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                                .tracking(2)
                                .opacity(sosTextPulse)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive
                ? String(localized: "emergency.sos.activeAccessibility")
                : String(localized: "emergency.sos.inactiveAccessibility"))
            .accessibilityHint(isActive
                ? String(localized: "emergency.sos.activeHint")
                : String(localized: "emergency.sos.inactiveHint"))
            .accessibilityIdentifier(AccessibilityID.sosActivateButton)
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
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            innerGlow = 0.6
        }
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            sosTextPulse = 0.4
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

// MARK: - Broadcasting Dots Label

/// Animated "Broadcasting to mesh..." with trailing dots.
private struct BroadcastingDotsLabel: View {
    let peerCount: Int
    let color: Color

    @State private var dotCount = 0
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        let dots = String(repeating: ".", count: dotCount)
        Text(String(localized: "emergency.status.broadcastingToMesh \(peerCount)") + dots)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .onAppear { startDotAnimation() }
            .onDisappear { animationTask?.cancel() }
    }

    private func startDotAnimation() {
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { break }
                dotCount = (dotCount + 1) % 4
            }
        }
    }
}

// MARK: - Emergency SOS View

struct EmergencySOSView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isCountingDown = false
    @State private var countdownSeconds = 3
    @State private var countdownTask: Task<Void, Never>?
    @State private var vignetteOpacity: Double = 0.0
    @State private var emergencyHoldProgress: CGFloat = 0.0
    @State private var emergencyHoldTask: Task<Void, Never>?
    @State private var isHoldingForEmergency = false
    @State private var sosActiveTextPulse: Double = 1.0

    private let red = Constants.Colors.emergencyRed
    private let amber = Constants.Colors.amber

    private var beacon: EmergencyBeacon { EmergencyBeacon.shared }
    private var emergencyMode: EmergencyMode { EmergencyMode.shared }

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
                    // Tap: toggle SOS beacon. Long-press (3s): toggle emergency mode.
                    SOSButton(isActive: beacon.isActive) {
                        if beacon.isActive {
                            beacon.deactivate()
                        } else {
                            startCountdown()
                        }
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 3.0)
                            .onChanged { _ in
                                startEmergencyHold()
                            }
                            .onEnded { _ in
                                completeEmergencyHold()
                            }
                    )
                    .overlay(alignment: .bottom) {
                        if isHoldingForEmergency {
                            VStack(spacing: 4) {
                                ProgressView(value: emergencyHoldProgress)
                                    .tint(Constants.Colors.emergencyRed)
                                    .frame(width: 120)
                                Text(String(localized: "emergency.holdForEmergencyMode"))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Constants.Colors.emergencyRed.opacity(0.8))
                            }
                            .offset(y: 100)
                        }
                    }
                    .padding(.vertical, 16)

                    // Status info.
                    if beacon.isActive {
                        activeStatusSection
                    } else {
                        inactiveInfoSection
                    }

                    // Emergency Mode toggle section.
                    emergencyModeSection

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
        .navigationTitle(String(localized: "emergency.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if beacon.isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "emergency.deactivate")) {
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

            Text(String(localized: "emergency.header.beacon"))
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(red.opacity(0.8))
                .tracking(3)

            Text(beacon.isActive
                 ? String(localized: "emergency.header.broadcasting")
                 : String(localized: "emergency.header.tapToActivate"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Active Status

    private var activeStatusSection: some View {
        VStack(spacing: 16) {
            // SOS ACTIVE pulsing header
            Text(String(localized: "emergency.sos.active"))
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundStyle(Constants.Colors.emergencyRed)
                .tracking(4)
                .opacity(sosActiveTextPulse)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        sosActiveTextPulse = 0.4
                    }
                }

            // GPS coordinates displayed prominently
            if let location = beacon.lastLocation {
                VStack(spacing: 4) {
                    Text(String(
                        format: "%.6f, %.6f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    ))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .accessibilityLabel(String(localized: "emergency.coordinates.label \(String(format: "%.6f", location.coordinate.latitude)) \(String(format: "%.6f", location.coordinate.longitude))"))
                }
            }

            // Broadcasting to mesh with animated dots
            BroadcastingDotsLabel(
                peerCount: appState.connectedPeerCount,
                color: Constants.Colors.emergencyRed
            )

            // Broadcast count + mesh node count.
            HStack(spacing: 20) {
                statusPill(
                    icon: "antenna.radiowaves.left.and.right",
                    label: String(localized: "emergency.status.broadcasts"),
                    value: "\(beacon.broadcastCount)",
                    color: Constants.Colors.emergencyRed
                )

                statusPill(
                    icon: "point.3.connected.trianglepath.dotted",
                    label: String(localized: "emergency.status.meshNodes"),
                    value: "\(appState.connectedPeerCount)",
                    color: amber
                )
            }

            // Battery level.
            let battery = UIDevice.current.batteryLevel
            if battery >= 0 {
                HStack(spacing: 8) {
                    Image(systemName: batteryIconForLevel(battery))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(battery > 0.2 ? Constants.Colors.electricGreen : Constants.Colors.emergencyRed)

                    Text(String(localized: "emergency.status.batteryRemaining \(Int(battery * 100))"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Large CANCEL SOS button
            Button {
                beacon.deactivate()
            } label: {
                Text(String(localized: "emergency.cancelSOS"))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Constants.Colors.emergencyRed.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Constants.Colors.emergencyRed.opacity(0.5), lineWidth: 1.5)
                            )
                    )
            }
            .accessibilityLabel(String(localized: "emergency.cancelSOS"))
            .accessibilityIdentifier(AccessibilityID.sosCancelButton)
            .padding(.top, 8)
        }
    }

    // MARK: - Inactive Info

    private var inactiveInfoSection: some View {
        VStack(spacing: 16) {
            infoRow(icon: "antenna.radiowaves.left.and.right",
                    text: String(localized: "emergency.info.broadcastFrequency"))
            infoRow(icon: "location.fill",
                    text: String(localized: "emergency.info.includesGPS"))
            infoRow(icon: "bell.badge.fill",
                    text: String(localized: "emergency.info.alertDevices"))
            infoRow(icon: "moon.fill",
                    text: String(localized: "emergency.info.backgroundBroadcast"))
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

                Text(String(localized: "emergency.coordinates.currentPosition"))
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

                Text(String(localized: "emergency.coordinates.altitudeAccuracy \(Int(location.altitude)) \(Int(location.horizontalAccuracy))"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                Text(String(localized: "emergency.coordinates.acquiringGPS"))
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

                Text(String(localized: "emergency.alerts.incoming"))
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

        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                countdownSeconds -= 1
                if countdownSeconds <= 0 {
                    countdownTask = nil
                    isCountingDown = false
                    beacon.activate(
                        senderID: appState.localPeerID,
                        senderName: appState.callsign
                    )
                    break
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        isCountingDown = false
        countdownSeconds = 3
    }

    private func batteryIconForLevel(_ level: Float) -> String {
        switch level {
        case 0.75...: return "battery.100"
        case 0.50...: return "battery.75"
        case 0.25...: return "battery.50"
        case 0.10...: return "battery.25"
        default: return "battery.0"
        }
    }

    private func startVignetteAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            vignetteOpacity = 0.3
        }
    }

    // MARK: - Emergency Mode Section

    private var emergencyModeSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Constants.Colors.emergencyRed)

                Text(String(localized: "emergency.emergencyMode.title"))
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Constants.Colors.emergencyRed.opacity(0.8))
                    .tracking(2)

                Spacer()

                // Toggle
                Toggle("", isOn: Binding(
                    get: { emergencyMode.isActive },
                    set: { newValue in
                        if newValue {
                            emergencyMode.activate()
                        } else {
                            emergencyMode.deactivate()
                        }
                    }
                ))
                .tint(Constants.Colors.emergencyRed)
                .labelsHidden()
            }

            if emergencyMode.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    emergencyInfoRow(
                        icon: "bolt.fill",
                        text: String(localized: "emergency.emergencyMode.maxTTL \(emergencyMode.maxTTL)")
                    )
                    emergencyInfoRow(
                        icon: "waveform",
                        text: String(localized: "emergency.emergencyMode.lowBandwidth")
                    )
                    emergencyInfoRow(
                        icon: "location.fill",
                        text: String(localized: "emergency.emergencyMode.locationBroadcast \(Int(emergencyMode.locationBroadcastInterval))")
                    )
                    emergencyInfoRow(
                        icon: "antenna.radiowaves.left.and.right",
                        text: String(localized: "emergency.emergencyMode.beaconInterval \(Int(emergencyMode.beaconInterval))")
                    )
                }
            } else {
                Text(String(localized: "emergency.emergencyMode.description"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(emergencyMode.isActive
                      ? Constants.Colors.emergencyRed.opacity(0.08)
                      : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            emergencyMode.isActive
                                ? Constants.Colors.emergencyRed.opacity(0.3)
                                : Color.white.opacity(0.08),
                            lineWidth: emergencyMode.isActive ? 1.0 : 0.5
                        )
                )
        )
    }

    private func emergencyInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Constants.Colors.emergencyRed.opacity(0.7))
                .frame(width: 18)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
        }
    }

    // MARK: - Emergency Mode Hold Gesture

    private func startEmergencyHold() {
        guard !isHoldingForEmergency else { return }
        isHoldingForEmergency = true
        emergencyHoldProgress = 0

        let interval: Duration = .milliseconds(50)
        let totalDuration: TimeInterval = 3.0
        let steps = totalDuration / 0.05

        emergencyHoldTask = Task { @MainActor in
            var currentStep: Double = 0
            while !Task.isCancelled, currentStep < steps {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                currentStep += 1
                let progress = CGFloat(currentStep / steps)
                withAnimation(.linear(duration: 0.05)) {
                    emergencyHoldProgress = min(progress, 1.0)
                }
            }
        }
    }

    private func completeEmergencyHold() {
        emergencyHoldTask?.cancel()
        emergencyHoldTask = nil
        isHoldingForEmergency = false
        emergencyHoldProgress = 0

        // Toggle emergency mode
        if emergencyMode.isActive {
            emergencyMode.deactivate()
        } else {
            emergencyMode.activate()
        }
    }
}

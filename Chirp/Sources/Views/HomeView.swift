import CoreLocation
import SwiftUI

// MARK: - Compact Header

private struct CompactHeader: View {
    let callsign: String
    let peerCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(callsign)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Circle()
                        .fill(peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500)
                        .frame(width: 7, height: 7)

                    Text(peerCount > 0
                         ? String(localized: "home.header.nodesInMesh \(peerCount)")
                         : String(localized: "home.header.noMesh")
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate400)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Inline Status Strip

private struct InlineStatusStrip: View {
    let peerCount: Int
    let threatCount: Int
    let isScanning: Bool
    let isEmergencyActive: Bool

    private var threatColor: Color {
        if threatCount == 0 { return Constants.Colors.electricGreen }
        if threatCount <= 2 { return Constants.Colors.amber }
        return Constants.Colors.hotRed
    }

    private var modeText: String {
        if isEmergencyActive { return String(localized: "home.status.emergency") }
        if isScanning { return String(localized: "home.status.scanning") }
        return String(localized: "home.status.normal")
    }

    private var modeColor: Color {
        if isEmergencyActive { return Constants.Colors.emergencyRed }
        if isScanning { return Constants.Colors.amber }
        return Constants.Colors.electricGreen
    }

    var body: some View {
        HStack(spacing: 16) {
            statusPill(
                icon: "antenna.radiowaves.left.and.right",
                text: String(localized: "home.status.peerCount \(peerCount)"),
                color: peerCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500
            )

            statusPill(
                icon: "shield.fill",
                text: String(localized: "home.status.threatCount \(threatCount)"),
                color: threatColor
            )

            statusPill(
                icon: "circle.fill",
                text: modeText,
                color: modeColor,
                iconSize: 6
            )

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func statusPill(icon: String, text: String, color: Color, iconSize: CGFloat = 11) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)
        }
    }
}

// MARK: - Friend Avatar Bubble

private struct FriendAvatarBubble: View {
    let friend: ChirpFriend
    let action: () -> Void

    @State private var isPressed = false
    @State private var onlineDotScale: CGFloat = 1.0

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    colorForName(friend.name),
                                    colorForName(friend.name).opacity(0.6),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(friend.name.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )
                        .shadow(
                            color: friend.isOnline ? colorForName(friend.name).opacity(0.4) : .clear,
                            radius: friend.isOnline ? 8 : 0,
                            y: friend.isOnline ? 2 : 0
                        )

                    if friend.isOnline {
                        Circle()
                            .fill(Constants.Colors.electricGreen)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Constants.Colors.slate900, lineWidth: 2)
                            )
                            .scaleEffect(onlineDotScale)
                            .offset(x: 1, y: 1)
                    }
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)

                Text(friend.name.split(separator: " ").first.map(String.init) ?? friend.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Constants.Colors.slate400)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
        .accessibilityLabel("\(friend.name), \(friend.isOnline ? "online" : "offline")")
        .frame(width: 60)
        .onAppear {
            if friend.isOnline {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    onlineDotScale = 1.2
                }
            }
        }
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Channel Card (Liquid Glass)

private struct ChannelCard: View {
    let channel: ChirpChannel
    let isActive: Bool
    let friends: [ChirpFriend]
    let unreadCount: Int
    var lastMessageText: String?
    var lastMessageDate: Date?
    var isReceiving: Bool = false

    @State private var badgeScale: CGFloat = 0.5
    @State private var liveOpacity: Double = 1.0

    private var channelAccessibilityLabel: String {
        var parts = [channel.name]
        parts.append("\(channel.activePeerCount) peer\(channel.activePeerCount == 1 ? "" : "s")")
        if channel.accessMode == .locked {
            parts.append("locked")
        }
        if isActive {
            parts.append("currently active")
        }
        if isReceiving {
            parts.append("live audio")
        }
        if unreadCount > 0 {
            parts.append("\(unreadCount) unread")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            // Channel icon with peer badge
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? Constants.Colors.blue500.opacity(0.15) : Constants.Colors.slate700.opacity(0.6))
                        .frame(width: 50, height: 50)

                    Image(systemName: channel.accessMode == .locked ? "lock.fill" : "waveform")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isActive ? Constants.Colors.blue500 : Constants.Colors.slate400)
                }

                // Live peer-count badge
                if channel.activePeerCount > 0 {
                    Text("\(channel.activePeerCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(
                            Circle()
                                .fill(Constants.Colors.electricGreen)
                        )
                        .offset(x: 6, y: -6)
                }
            }

            // Channel info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if isReceiving {
                        // LIVE badge
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(localized: "home.channel.live"))
                                .font(.system(size: 9, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Constants.Colors.hotRed)
                        )
                        .opacity(liveOpacity)
                    } else if isActive {
                        Circle()
                            .fill(Constants.Colors.electricGreen)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 8) {
                    Text(String(localized: "home.status.peerCount \(channel.activePeerCount)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.slate400)

                    Text("\u{00B7}")
                        .foregroundStyle(Constants.Colors.slate600)

                    if let lastDate = lastMessageDate {
                        Text(lastDate.relativeDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Constants.Colors.slate500)
                    } else {
                        Text(channel.createdAt.relativeDisplay)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Constants.Colors.slate500)
                    }
                }

                // Last message preview
                if let preview = lastMessageText {
                    Text(preview)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Constants.Colors.slate500)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(String(localized: "home.channel.noMessages"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Constants.Colors.slate600)
                        .italic()
                }
            }

            Spacer()

            // Right side: unread badge or chevron
            VStack(alignment: .trailing, spacing: 6) {
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))\(unreadCount > 99 ? "+" : "")")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Constants.Colors.blue500)
                        )
                        .scaleEffect(badgeScale)
                        .onAppear {
                            withAnimation(
                                .spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0)
                            ) {
                                badgeScale = 1.0
                            }
                        }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.Colors.slate600)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(channelAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.channelCard)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isActive ? Constants.Colors.blue500.opacity(0.3) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .onAppear {
            if isReceiving {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    liveOpacity = 0.4
                }
            }
        }
        .onChange(of: unreadCount) { oldValue, newValue in
            if newValue > oldValue && newValue > 0 {
                badgeScale = 0.5
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.5, blendDuration: 0)
                ) {
                    badgeScale = 1.0
                }
            }
        }
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeDisplay: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return String(localized: "time.justNow") }
        if interval < 3600 { return String(localized: "time.minutesAgo \(Int(interval / 60))") }
        if interval < 86400 { return String(localized: "time.hoursAgo \(Int(interval / 3600))") }
        return String(localized: "time.daysAgo \(Int(interval / 86400))")
    }
}

// MARK: - Empty State (Redesigned)

private struct ChannelEmptyState: View {
    let peerCount: Int
    let onTap: () -> Void

    @State private var meshSearchPulse: CGFloat = 1.0
    @State private var buttonGlow: Bool = false

    private var meshReady: Bool { peerCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 48)

            // Device readiness card
            VStack(spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Constants.Colors.slate500)

                VStack(spacing: 8) {
                    Text(String(localized: "home.emptyState.title"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(String(localized: "home.emptyState.subtitle"))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.Colors.slate400)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    Text(String(localized: "home.emptyState.tagline"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Constants.Colors.amber.opacity(0.7))
                        .padding(.top, 2)
                }

                // Readiness indicators
                VStack(spacing: 12) {
                    readinessRow(icon: "wifi", label: String(localized: "home.readiness.wifiDirect"), ready: true)
                    meshNetworkRow
                    readinessRow(icon: "lock.shield.fill", label: String(localized: "home.readiness.encryption"), ready: true)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Constants.Colors.slate800.opacity(0.5))
                )
            }
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 32)

            // Create channel button with glow
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))

                    Text(String(localized: "home.emptyState.createChannel"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Constants.Colors.blue500, Constants.Colors.blue600],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(
                    color: Constants.Colors.blue500.opacity(buttonGlow ? 0.5 : 0.2),
                    radius: buttonGlow ? 16 : 8,
                    y: 2
                )
            }
            .padding(.horizontal, 40)
            .accessibilityLabel("Create your first channel")
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                ) {
                    buttonGlow = true
                }
            }

            Spacer()
        }
    }

    /// Mesh network row with searching pulse when not connected
    private var meshNetworkRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(meshReady ? Constants.Colors.slate400 : Constants.Colors.amber.opacity(0.7))
                .scaleEffect(meshReady ? 1.0 : meshSearchPulse)
                .frame(width: 20)

            Text(String(localized: "home.readiness.meshNetwork"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)

            if !meshReady {
                Text(String(localized: "home.readiness.searching"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Constants.Colors.amber.opacity(0.5))
            }

            Spacer()

            Image(systemName: meshReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(meshReady ? Constants.Colors.electricGreen : Constants.Colors.amber.opacity(0.6))
                .scaleEffect(meshReady ? 1.0 : meshSearchPulse)
        }
        .onAppear {
            if !meshReady {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    meshSearchPulse = 1.15
                }
            }
        }
    }

    private func readinessRow(icon: String, label: String, ready: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Constants.Colors.slate400)

            Spacer()

            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ready ? Constants.Colors.electricGreen : Constants.Colors.slate600)
        }
    }
}

// MARK: - SOS Toolbar Button

/// A long-press-activated SOS button that prevents accidental triggers.
/// Shows red only when held; requires deliberate press to confirm.
private struct SOSToolbarButton: View {
    @Binding var showConfirm: Bool

    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    private let holdDuration: TimeInterval = 1.5

    var body: some View {
        Button {
            // Tap does nothing -- must long press
        } label: {
            ZStack {
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Constants.Colors.hotRed, lineWidth: 2.5)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30, height: 30)

                Text("SOS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(isHolding ? .white : Constants.Colors.hotRed.opacity(0.6))
            }
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(isHolding ? Constants.Colors.hotRed.opacity(0.3) : Color.clear)
            )
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onChanged { _ in
                    startHold()
                }
                .onEnded { _ in
                    completeHold()
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    cancelHold()
                }
        )
        .accessibilityLabel("SOS Emergency Beacon")
        .accessibilityHint("Long press for \(String(format: "%.1f", holdDuration)) seconds to activate emergency beacon")
    }

    private func startHold() {
        isHolding = true
        holdProgress = 0
        holdTask?.cancel()

        let interval: Duration = .milliseconds(50)
        let totalSteps = holdDuration / 0.05

        holdTask = Task { @MainActor in
            var currentStep: Double = 0
            while !Task.isCancelled, currentStep < totalSteps {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                currentStep += 1
                let progress = CGFloat(currentStep / totalSteps)
                withAnimation(.linear(duration: 0.05)) {
                    holdProgress = progress
                }
            }
        }
    }

    private func completeHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        holdProgress = 0
        showConfirm = true
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.2)) {
            isHolding = false
            holdProgress = 0
        }
    }
}

// MARK: - Ambient Mesh Background

/// Lightweight particle field that gives the Talk tab a living, breathing feel.
/// Uses TimelineView + Canvas for minimal CPU (~24fps, simple geometry).
private struct AmbientMeshBackground: View {
    let peerCount: Int

    private let nodeCount = 7
    private let connectionDistance: CGFloat = 140

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                var nodes: [CGPoint] = []
                for i in 0..<nodeCount {
                    let seed = Double(i)
                    let x = size.width * (0.15 + 0.7 * fract(seed * 0.3713 + sin(time * 0.08 + seed * 1.2) * 0.12))
                    let y = size.height * (0.1 + 0.8 * fract(seed * 0.6173 + cos(time * 0.06 + seed * 0.9) * 0.10))
                    nodes.append(CGPoint(x: x, y: y))
                }

                // Connecting lines between nearby nodes
                let lineOpacity = peerCount > 0 ? 0.08 : 0.04
                for i in 0..<nodes.count {
                    for j in (i + 1)..<nodes.count {
                        let dx = nodes[i].x - nodes[j].x
                        let dy = nodes[i].y - nodes[j].y
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist < connectionDistance {
                            let fade = 1.0 - (dist / connectionDistance)
                            var path = Path()
                            path.move(to: nodes[i])
                            path.addLine(to: nodes[j])
                            context.stroke(
                                path,
                                with: .color(Constants.Colors.amber.opacity(lineOpacity * fade)),
                                lineWidth: 0.5
                            )
                        }
                    }
                }

                // Nodes as small glowing dots
                let dotOpacity = peerCount > 0 ? 0.25 : 0.12
                for i in 0..<nodes.count {
                    let pulse = 1.0 + 0.3 * sin(time * 0.5 + Double(i) * 1.7)
                    let radius: CGFloat = CGFloat(1.5 + 1.0 * pulse)

                    let glowRect = CGRect(
                        x: nodes[i].x - radius * 3,
                        y: nodes[i].y - radius * 3,
                        width: radius * 6,
                        height: radius * 6
                    )
                    context.fill(
                        Circle().path(in: glowRect),
                        with: .color(Constants.Colors.amber.opacity(dotOpacity * 0.3))
                    )

                    let dotRect = CGRect(
                        x: nodes[i].x - radius,
                        y: nodes[i].y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Circle().path(in: dotRect),
                        with: .color(Constants.Colors.amber.opacity(dotOpacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

// MARK: - Channel Info Card

private struct ChannelInfoCard: View {
    let channel: ChirpChannel?
    let peerCount: Int
    let channels: [ChirpChannel]
    let onSelect: (ChirpChannel) -> Void
    let onCreate: () -> Void

    @State private var showPicker = false

    private var isEncrypted: Bool {
        channel?.encryptionKeyData != nil || channel?.accessMode == .locked
    }

    private var subtitle: String {
        guard let ch = channel else { return String(localized: "home.channel.noChannelSelected") }
        if peerCount > 0 {
            return String(localized: "home.channel.peersOn \(peerCount) \(ch.name)")
        }
        return String(localized: "home.channel.listeningOn \(ch.name)")
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    if isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Constants.Colors.electricGreen)
                    }

                    Text(channel?.name ?? String(localized: "home.channel.noChannel"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Constants.Colors.slate500)
                }

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.slate400)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Constants.Colors.slate800.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Channel: \(channel?.name ?? "None"), \(subtitle). Tap to switch.")
        .confirmationDialog(String(localized: "home.channel.switchChannel"), isPresented: $showPicker) {
            ForEach(channels) { ch in
                Button(ch.name) {
                    onSelect(ch)
                }
            }
            Button(String(localized: "home.channel.newChannel")) {
                onCreate()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }
}

// MARK: - Mesh Signal Ring

private struct MeshSignalRing: View {
    let peerCount: Int
    let maxHops: UInt8

    private var strength: CGFloat {
        if peerCount == 0 { return 0 }
        if peerCount >= 5 { return 1.0 }
        return CGFloat(peerCount) / 5.0
    }

    private var ringColor: Color {
        if peerCount == 0 { return Constants.Colors.slate700 }
        if peerCount >= 3 { return Constants.Colors.electricGreen }
        return Constants.Colors.amber
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Constants.Colors.slate800.opacity(0.6), lineWidth: 1.5)
                .frame(width: 220, height: 220)

            Circle()
                .trim(from: 0, to: strength)
                .stroke(
                    ringColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 220, height: 220)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: strength)

            ForEach(0..<12, id: \.self) { i in
                let isMajor = i % 3 == 0
                Rectangle()
                    .fill(Constants.Colors.slate700.opacity(isMajor ? 0.5 : 0.25))
                    .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 8 : 5)
                    .offset(y: -110)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scanning Peers Indicator

private struct ScanningPeersView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Constants.Colors.slate600)
                    .frame(width: 5, height: 5)
                    .opacity(pulse ? 0.6 : 0.15)
                    .animation(
                        .easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.25),
                        value: pulse
                    )
            }

            Text(String(localized: "home.scanning.peers"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Constants.Colors.slate600)
        }
        .onAppear { pulse = true }
        .accessibilityLabel("Scanning for nearby peers")
    }
}

// MARK: - Peer Bubbles Arc

private struct PeerBubblesArc: View {
    let peers: [ChirpPeer]

    private let maxVisible = 5
    private let arcRadius: CGFloat = 130

    var body: some View {
        let visible = Array(peers.filter(\.isConnected).prefix(maxVisible))
        let count = visible.count
        if count > 0 {
            let totalArc: Double = min(Double(count - 1) * 25.0, 120.0)
            let startAngle: Double = -90.0 - totalArc / 2.0

            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, peer in
                    let angle: Double = count == 1
                        ? -90.0
                        : startAngle + (totalArc * Double(index) / max(Double(count - 1), 1.0))
                    let rad = angle * .pi / 180.0

                    PeerBubble(name: peer.name, signalStrength: peer.signalStrength)
                        .offset(
                            x: cos(rad) * arcRadius,
                            y: sin(rad) * arcRadius
                        )
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: visible.map(\.id))
        }
    }
}

private struct PeerBubble: View {
    let name: String
    let signalStrength: Int

    private var borderColor: Color {
        switch signalStrength {
        case 3: return Constants.Colors.electricGreen
        case 2: return Constants.Colors.amber
        default: return Constants.Colors.slate600
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(colorForName(name))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .overlay(
                    Circle()
                        .strokeBorder(borderColor.opacity(0.6), lineWidth: 1.5)
                )

            Text(name.split(separator: " ").first.map(String.init) ?? name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Constants.Colors.slate500)
                .lineLimit(1)
        }
        .frame(width: 44)
        .accessibilityLabel("\(name), signal \(signalStrength) of 3")
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.55)
    }
}

// MARK: - Mesh Status Strip

private struct MeshStatusStrip: View {
    let peerCount: Int
    let meshStats: MeshStats?
    let isEncrypted: Bool
    let isEmergencyActive: Bool

    private var meshLabel: String {
        guard let stats = meshStats, peerCount > 0 else { return String(localized: "home.mesh.noMesh") }
        if stats.maxHops >= 3 { return String(localized: "home.mesh.hops \(stats.maxHops)") }
        if stats.maxHops >= 1 { return String(localized: "home.mesh.hops \(stats.maxHops)") }
        return String(localized: "home.mesh.direct")
    }

    private var meshColor: Color {
        if peerCount == 0 { return Constants.Colors.slate600 }
        guard let stats = meshStats else { return Constants.Colors.slate500 }
        if stats.maxHops >= 3 { return Constants.Colors.electricGreen }
        if stats.maxHops >= 1 { return Constants.Colors.amber }
        return Constants.Colors.electricGreen
    }

    private var relayActive: Bool {
        guard let stats = meshStats else { return false }
        return stats.relayed > 0
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(meshColor)

                Text(meshLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Constants.Colors.slate400)
            }
            .accessibilityLabel(String(localized: "home.mesh.statusLabel \(meshLabel)"))

            HStack(spacing: 4) {
                Circle()
                    .fill(relayActive ? Constants.Colors.electricGreen : Constants.Colors.slate700)
                    .frame(width: 6, height: 6)

                Text(String(localized: "home.mesh.relay"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(relayActive ? Constants.Colors.slate400 : Constants.Colors.slate600)
            }
            .accessibilityLabel(relayActive ? String(localized: "home.mesh.relayActive") : String(localized: "home.mesh.relayInactive"))

            if isEncrypted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))

                    Text("E2E")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Constants.Colors.electricGreen.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Constants.Colors.electricGreen.opacity(0.1))
                        .overlay(
                            Capsule()
                                .strokeBorder(Constants.Colors.electricGreen.opacity(0.2), lineWidth: 0.5)
                        )
                )
                .accessibilityLabel(String(localized: "home.mesh.e2eEncrypted"))
            }

            Spacer()

            if isEmergencyActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Constants.Colors.emergencyRed)
                        .frame(width: 6, height: 6)

                    Text(String(localized: "home.mesh.sos"))
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(Constants.Colors.emergencyRed)
                }
                .accessibilityLabel(String(localized: "home.mesh.emergencyActive"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Constants.Colors.slate800.opacity(0.4))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 0.5)
                }
        )
    }
}

// MARK: - Home Tab Enum

enum HomeTab: String, CaseIterable {
    case talk = "Talk"
    case messages = "Messages"
    case map = "Map"
    case more = "More"

    var icon: String {
        switch self {
        case .talk: return "waveform"
        case .messages: return "bubble.left.and.bubble.right"
        case .map: return "map"
        case .more: return "ellipsis"
        }
    }
}

// MARK: - Bottom Navigation Bar

private struct BottomNavBar: View {
    @Binding var selectedTab: HomeTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Constants.Colors.amber : Constants.Colors.slate500)

                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? Constants.Colors.amber : Constants.Colors.slate500)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Constants.Colors.slate700.opacity(0.5))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }
}

// MARK: - Channel Selector Pill

private struct ChannelSelectorPill: View {
    let channels: [ChirpChannel]
    let activeChannel: ChirpChannel?
    let onSelect: (ChirpChannel) -> Void
    let onCreate: () -> Void

    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)

                Text(activeChannel?.name ?? "No Channel")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Constants.Colors.slate400)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Constants.Colors.slate800)
                    .overlay(
                        Capsule()
                            .stroke(Constants.Colors.slate700, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Channel: \(activeChannel?.name ?? "None"). Tap to switch.")
        .confirmationDialog("Switch Channel", isPresented: $showPicker) {
            ForEach(channels) { channel in
                Button(channel.name) {
                    onSelect(channel)
                }
            }
            Button("New Channel") {
                onCreate()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState

    @State private var showChannelCreation = false
    @State private var showPairing = false
    @State private var showGatewayMessage = false
    @State private var showDiagnostics = false
    @State private var toast: ToastItem?
    @State private var connectedPeerCount = 0
    @State private var isRefreshing = false
    @State private var showSOSConfirm = false
    @State private var showPermissionAlert = false
    @State private var permissionAlert: AppState.PermissionDeniedAlert?
    @State private var selectedTab: HomeTab = .talk
    @State private var pttState: PTTState = .idle
    @State private var inputLevel: Float = 0.0
    @State private var transmitStartTime: Date?

    private var connectionStatus: ConnectionStatus {
        let mpPeers = appState.connectedPeerCount

        if mpPeers > 0 {
            return .connected(peerCount: mpPeers)
        }

        return .searching
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Dark blue-black background
                Constants.Colors.slate900
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Compact header with callsign + mesh status
                    CompactHeader(
                        callsign: appState.callsign,
                        peerCount: appState.connectedPeerCount
                    )

                    // Tab content
                    tabContent

                    // Bottom navigation bar
                    BottomNavBar(selectedTab: $selectedTab)
                }

                // FAB for new channel (messages tab only)
                if selectedTab == .messages {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                showChannelCreation = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Constants.Colors.blue500)
                                            .shadow(color: Constants.Colors.blue500.opacity(0.4), radius: 12, y: 4)
                                    )
                            }
                            .accessibilityLabel("New Channel")
                            .padding(.trailing, 20)
                            .padding(.bottom, 80) // space for bottom nav
                        }
                    }
                }

                // Emergency mode overlay -- always on top
                EmergencyModeOverlay(emergencyMode: EmergencyMode.shared)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            MeshMapView()
                        } label: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Constants.Colors.slate400)
                        }
                        .accessibilityLabel("Mesh Map")
                        .accessibilityIdentifier(AccessibilityID.meshMapButton)

                        if MeshGateway.shared.gatewayAvailable {
                            Button {
                                showGatewayMessage = true
                            } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Constants.Colors.electricGreen)
                            }
                            .accessibilityLabel("Gateway")
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SOSToolbarButton(showConfirm: $showSOSConfirm)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showChannelCreation) {
                ChannelCreationView()
            }
            .sheet(isPresented: $showPairing) {
                PairingView()
                    .onAppearAnimations()
            }
            .sheet(isPresented: $showGatewayMessage) {
                GatewayMessageView(
                    localPeerID: appState.localPeerID,
                    localPeerName: appState.localPeerName
                )
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .alert(String(localized: "home.sos.alertTitle"), isPresented: $showSOSConfirm) {
                Button(String(localized: "home.sos.sendButton"), role: .destructive) {
                    activateSOS()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "home.sos.alertMessage"))
            }
            .chirpToast($toast)
            .onChange(of: appState.permissionDeniedAlert) { _, newAlert in
                if let alert = newAlert {
                    permissionAlert = alert
                    showPermissionAlert = true
                    appState.permissionDeniedAlert = nil
                }
            }
            .alert(permissionAlert?.title ?? "", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    appState.openAppSettings()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(permissionAlert?.message ?? "")
            }
            .onChange(of: appState.proximityAlert.recentAlerts.count) { _, _ in
                if let latest = appState.proximityAlert.recentAlerts.last {
                    toast = ToastItem(message: "\(latest.friendName) is \(latest.distance)!", type: .info)
                }
            }
            .task {
                while !Task.isCancelled {
                    let peers = await appState.peerTracker.connectedPeers
                    connectedPeerCount = peers.count
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .chirpPTTShortcutTriggered)) { _ in
                // Action Button / Shortcut triggered — switch to Talk tab
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = .talk
                }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .talk:
            pttHomeContent

        case .messages:
            // Inline status strip
            InlineStatusStrip(
                peerCount: appState.connectedPeerCount,
                threatCount: appState.bleScanner.threatDevices.count,
                isScanning: appState.bleScanner.isScanning,
                isEmergencyActive: EmergencyMode.shared.isActive
            )

            // Friends quick-access row
            if !appState.friendsManager.friends.isEmpty {
                friendsQuickAccess
            }

            // Channel list or empty state
            channelListView

        case .map:
            GeoMapView(
                userLocation: appState.locationService.currentLocation?.coordinate,
                peers: mapPeerPins
            )
            .ignoresSafeArea(edges: .bottom)

        case .more:
            MoreView()
        }
    }

    // MARK: - PTT Home Content

    private var activePeers: [ChirpPeer] {
        appState.channelManager.activeChannel?.peers.filter(\.isConnected) ?? []
    }

    /// Build peer pins from beacon data for the map tab.
    private var mapPeerPins: [PeerPin] {
        let beaconNodes = appState.meshBeacon.sortedNodes
        let peers = appState.channelManager.activeChannel?.peers ?? []
        let peerTransport: [String: ChirpPeer.TransportType] = Dictionary(
            peers.map { ($0.id, $0.transportType) },
            uniquingKeysWith: { _, last in last }
        )
        return beaconNodes.compactMap { beacon in
            guard let lat = beacon.latitude, let lon = beacon.longitude else { return nil }
            let isStale = Date().timeIntervalSince(beacon.lastSeen) > 10
            let transport = peerTransport[beacon.id] ?? .multipeer
            return PeerPin(
                id: beacon.id,
                name: beacon.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                transportType: transport,
                isStale: isStale
            )
        }
    }

    private var channelIsEncrypted: Bool {
        let ch = appState.channelManager.activeChannel
        return ch?.encryptionKeyData != nil || ch?.accessMode == .locked
    }

    private var pttHomeContent: some View {
        ZStack {
            // 1. Ambient mesh particle background
            AmbientMeshBackground(peerCount: appState.connectedPeerCount)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 2. Channel info card (replaces plain pill)
                ChannelInfoCard(
                    channel: appState.channelManager.activeChannel,
                    peerCount: appState.connectedPeerCount,
                    channels: appState.channelManager.channels,
                    onSelect: { channel in
                        appState.channelManager.joinChannel(id: channel.id)
                    },
                    onCreate: {
                        showChannelCreation = true
                    }
                )
                .padding(.top, 12)

                Spacer()

                // 3. PTT zone: signal ring + peer bubbles + button
                ZStack {
                    // Mesh signal ring (compass rose)
                    MeshSignalRing(
                        peerCount: appState.connectedPeerCount,
                        maxHops: appState.meshStats?.maxHops ?? 0
                    )

                    // Peer bubbles arc (above PTT) or scanning indicator
                    if !activePeers.isEmpty {
                        PeerBubblesArc(peers: appState.channelManager.activeChannel?.peers ?? [])
                    } else {
                        ScanningPeersView()
                            .offset(y: -120)
                    }

                    // PTT button (untouched)
                    PTTButtonView(
                        pttState: $pttState,
                        onPressDown: {
                            guard appState.micPermissionGranted else {
                                Task { await appState.requestMicPermission() }
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

                    // Peer count badge (when peers > 0)
                    if appState.connectedPeerCount > 0 {
                        Text("\(appState.connectedPeerCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Constants.Colors.electricGreen)
                            )
                            .offset(x: 85, y: -70)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel("\(appState.connectedPeerCount) connected peers")
                    }
                }

                Spacer()

                // 4. Bottom mesh status strip
                MeshStatusStrip(
                    peerCount: appState.connectedPeerCount,
                    meshStats: appState.meshStats,
                    isEncrypted: channelIsEncrypted,
                    isEmergencyActive: EmergencyMode.shared.isActive
                )
                .onLongPressGesture {
                    showDiagnostics = true
                }
            }
        }
        .onChange(of: appState.pttState) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) {
                pttState = newValue
            }
        }
        .onChange(of: appState.inputLevel) { _, newValue in
            inputLevel = newValue
        }
    }

    // MARK: - Friends Quick Access

    private var friendsQuickAccess: some View {
        VStack(spacing: 0) {
            // Section header with "See All" link
            HStack {
                Text(String(localized: "home.friends.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.Colors.slate400)
                    .textCase(.uppercase)
                    .tracking(0.5)

                if !appState.friendsManager.onlineFriends.isEmpty {
                    Text(String(localized: "home.friends.online \(appState.friendsManager.onlineFriends.count)"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Constants.Colors.electricGreen.opacity(0.8))
                }

                Spacer()

                NavigationLink {
                    FriendsView()
                } label: {
                    Text(String(localized: "home.friends.seeAll"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.blue500)
                }
                .accessibilityLabel("See all friends")
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(
                        appState.friendsManager.friends.sorted { a, b in
                            if a.isOnline != b.isOnline { return a.isOnline }
                            return a.name < b.name
                        }
                    ) { friend in
                        FriendAvatarBubble(friend: friend) {
                            showChannelCreation = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Channel List

    /// Whether the active channel is currently receiving audio from a peer.
    private var activeChannelReceiving: Bool {
        if case .receiving = appState.pttState { return true }
        return false
    }

    private var channelListView: some View {
        ScrollView {
            if appState.channelManager.channels.isEmpty {
                ChannelEmptyState(peerCount: appState.connectedPeerCount) {
                    showChannelCreation = true
                }
            } else {
                // Scanning mesh indicator during refresh
                if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Constants.Colors.amber)
                        Text("Scanning mesh...")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Constants.Colors.amber.opacity(0.8))
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }

                LazyVStack(spacing: 8) {
                    ForEach(appState.channelManager.channels) { channel in
                        let isActive = appState.channelManager.activeChannel?.id == channel.id
                        let isLive = isActive && activeChannelReceiving

                        NavigationLink {
                            ChannelView(channel: channel)
                        } label: {
                            ChannelCard(
                                channel: channel,
                                isActive: isActive,
                                friends: appState.friendsManager.friends,
                                unreadCount: appState.textMessageService.unreadCount(for: channel.id),
                                lastMessageText: appState.textMessageService.lastMessageText(for: channel.id),
                                lastMessageDate: appState.textMessageService.lastMessageDate(for: channel.id),
                                isReceiving: isLive
                            )
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    appState.channelManager.deleteChannel(id: channel.id)
                                }
                            } label: {
                                Label(String(localized: "home.channel.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 80) // space for FAB
            }
        }
        .refreshable {
            await refreshPeerDiscovery()
        }
    }

    // MARK: - Refresh

    private func refreshPeerDiscovery() async {
        isRefreshing = true

        // Restart multipeer advertising + browsing to force fresh discovery
        appState.multipeerTransport.stop()
        appState.multipeerTransport.start()

        // Brief pause so peers have time to reconnect
        try? await Task.sleep(for: .seconds(1))

        // Refresh local peer count
        let peers = await appState.peerTracker.connectedPeers
        connectedPeerCount = peers.count

        isRefreshing = false
    }

    // MARK: - SOS

    private func activateSOS() {
        let sosPayload: [String: String] = [
            "type": "SOS",
            "from": appState.callsign,
            "peerID": appState.localPeerID,
            "time": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONEncoder().encode(sosPayload) else { return }

        Task {
            let packet = await appState.meshRouter.createPacket(
                type: .control,
                payload: data,
                channelID: "",
                sequenceNumber: 0,
                priority: .critical
            )
            appState.multipeerTransport.forwardPacket(packet.serialize(), excludePeer: "")
        }

        toast = ToastItem(message: "SOS beacon activated", type: .error)
    }
}

import SwiftUI

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color

    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = 0.2
                }
            }
    }
}

// MARK: - Pending Message Row

private struct PendingMessageRow: View {
    let message: VoiceMessageQueue.PendingMessage

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    var body: some View {
        HStack(spacing: 14) {
            // Recipient avatar.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [colorForName(message.recipientName),
                                     colorForName(message.recipientName).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Text(String(message.recipientName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.recipientName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if message.delivered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(green)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(amber.opacity(0.7))

                    Text(message.durationDisplay)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))

                    Text(message.timestamp, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                if message.delivered {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(green)

                        Text("Delivered")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(green.opacity(0.8))

                        if let deliveredAt = message.deliveredAt {
                            Text(deliveredAt, style: .relative)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        PulsingDot(color: amber)

                        Text("Waiting for \(message.recipientName) to come in range...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(amber.opacity(0.7))
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            message.delivered
                                ? green.opacity(0.15)
                                : amber.opacity(0.1),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Received Message Row

private struct ReceivedMessageRow: View {
    let message: VoiceMessageQueue.PendingMessage
    /// Who sent it, as a callsign when one is known.
    let senderLabel: String
    let isPlaying: Bool
    let progress: Double
    let onPlay: () -> Void

    private let amber = Constants.Colors.amber

    var body: some View {
        HStack(spacing: 14) {
            // Sender avatar.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [colorForName(senderLabel),
                                     colorForName(senderLabel).opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)

                Text(String(senderLabel.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(senderLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(amber.opacity(0.7))

                    Text(message.durationDisplay)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))

                    Text(message.timestamp, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()

            // Play / stop button, with a ring that fills as the clip plays.
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(amber.opacity(0.15))
                        .frame(width: 44, height: 44)

                    if isPlaying {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(amber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 42, height: 42)
                    }

                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(amber)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.voiceMessagePlayButton)
            .accessibilityLabel(isPlaying
                ? String(localized: "voiceMessages.stop")
                : String(localized: "voiceMessages.play \(senderLabel)"))
            .accessibilityValue(isPlaying ? String(localized: "voiceMessages.playing") : "")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(amber.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private func colorForName(_ name: String) -> Color {
        let hash = abs(name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.65)
    }
}

// MARK: - Empty State

private struct VoiceMessageEmptyState: View {
    let isPending: Bool

    private let amber = Constants.Colors.amber

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(amber.opacity(0.06))
                    .frame(width: 100, height: 100)

                Image(systemName: isPending ? "paperplane" : "tray")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(amber.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }

            Text(isPending ? "No pending messages" : "No received messages")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            Text(isPending
                 ? "Record a voice message for a friend\nwho is out of range"
                 : "Voice messages from others will\nappear here")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
        }
    }
}

// MARK: - Voice Messages View

struct VoiceMessagesView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab = 0
    /// Resolved Block/Report target for a voice message's sender.
    @State private var peerActionTarget: PeerActionTarget?

    private let amber = Constants.Colors.amber
    private let red = Constants.Colors.hotRed

    private var queue: VoiceMessageQueue { VoiceMessageQueue.shared }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom segmented control.
                tabSelector

                // Content.
                TabView(selection: $selectedTab) {
                    pendingTab
                        .tag(0)

                    receivedTab
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationTitle("Voice Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Open on whichever list has something in it.
            if queue.pendingMessages.isEmpty && !queue.receivedMessages.isEmpty {
                selectedTab = 1
            }
        }
        .onDisappear { player.stop() }
        .sheet(item: $peerActionTarget) { target in
            PeerActionSheet(
                target: target,
                onBlock: { appState.applyBlock($0) },
                onReport: { reported, reason, includeText in
                    appState.applyReport(
                        reported,
                        reason: reason,
                        message: nil,
                        includeMessageText: includeText
                    )
                }
            )
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            tabButton(title: "Pending", count: queue.undeliveredCount, index: 0)
            tabButton(title: "Received", count: queue.receivedMessages.count, index: 1)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func tabButton(title: String, count: Int, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(selectedTab == index ? .black : amber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(selectedTab == index ? amber : amber.opacity(0.2))
                        )
                }
            }
            .foregroundStyle(selectedTab == index ? .black : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedTab == index ? amber : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pending Tab

    private var pendingTab: some View {
        Group {
            if queue.pendingMessages.isEmpty {
                VoiceMessageEmptyState(isPending: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(queue.pendingMessages.reversed()) { message in
                            PendingMessageRow(message: message)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            queue.deletePendingMessage(id: message.id)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        queue.deletePendingMessage(id: message.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Received Tab

    private var receivedTab: some View {
        Group {
            if queue.receivedMessages.isEmpty {
                VoiceMessageEmptyState(isPending: false)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(queue.receivedMessages) { message in
                            ReceivedMessageRow(
                                message: message,
                                senderLabel: senderLabel(for: message),
                                isPlaying: player.isPlaying(message.id),
                                progress: player.isPlaying(message.id) ? player.progress : 0
                            ) {
                                togglePlayback(message)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        queue.deleteReceivedMessage(id: message.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                // Guideline 1.2 wants the sender of a voice
                                // message blockable from where it appears.
                                // `senderID` is the routing UUID the router
                                // enforces on, so this one needs no lookup.
                                Button {
                                    peerActionTarget = appState.peerActionTarget(
                                        routingID: message.senderID,
                                        name: senderLabel(for: message)
                                    )
                                } label: {
                                    Label(
                                        String(localized: "moderation.blockOrReport"),
                                        systemImage: "hand.raised"
                                    )
                                }
                                .accessibilityIdentifier(AccessibilityID.blockOrReportMenuItem)
                                Button(role: .destructive) {
                                    queue.deleteReceivedMessage(id: message.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Playback

    private var player: VoiceClipPlayer { appState.voiceClipPlayer }

    private func togglePlayback(_ message: VoiceMessageQueue.PendingMessage) {
        if player.isPlaying(message.id) {
            player.stop()
            return
        }
        guard let frames = queue.loadOpusFrames(for: message) else { return }
        player.play(id: message.id, frames: frames)
    }

    /// The sender's callsign: from the message itself, else from anyone
    /// nearby with that ID, else a short form of the ID.
    private func senderLabel(for message: VoiceMessageQueue.PendingMessage) -> String {
        if let name = message.senderName, !name.isEmpty { return name }
        if let peer = appState.nearbyPeers.first(where: { $0.id == message.senderID }) {
            return peer.name
        }
        return String(message.senderID.prefix(8))
    }
}

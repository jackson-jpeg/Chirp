import SwiftUI

/// Translucent overlay showing live captions during PTT reception.
/// Slides down from the top of ChannelView when someone is speaking,
/// auto-hides 3 seconds after speech ends. Tap to expand and see
/// recent transcript history.
struct TranscriptOverlayView: View {
    @Environment(AppState.self) private var appState

    let transcription: LiveTranscription

    @State private var isExpanded = false
    @State private var isVisible = false
    @State private var hideTask: Task<Void, Never>?

    /// How long after speech ends before the overlay auto-hides.
    private let autoHideDelay: TimeInterval = 3.0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                VStack(spacing: 0) {
                    // Live caption bar
                    liveCaptionBar
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        }

                    // Expandable history
                    if isExpanded {
                        historyList
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(overlayBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Live transcript")
            }

            Spacer()
        }
        .onChange(of: transcription.isTranscribing) { _, isTranscribing in
            if isTranscribing {
                showOverlay()
            } else {
                scheduleHide()
            }
        }
        .onChange(of: transcription.currentTranscript) { _, _ in
            // Keep visible while text is updating
            if transcription.isTranscribing {
                cancelHide()
            }
        }
    }

    // MARK: - Live Caption Bar

    private var liveCaptionBar: some View {
        HStack(spacing: 10) {
            // Speaker indicator
            HStack(spacing: 6) {
                // Pulsing dot when live
                if transcription.isTranscribing {
                    Circle()
                        .fill(Constants.Colors.electricGreen)
                        .frame(width: 8, height: 8)
                        .modifier(PulsingModifier())
                }

                Text(transcription.currentSpeaker)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Constants.Colors.electricGreen)
                    .lineLimit(1)
            }

            // Transcript text
            Text(displayTranscript)
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textPrimary)
                .lineLimit(isExpanded ? 4 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: transcription.currentTranscript)

            // Expand chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.Colors.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transcription.currentSpeaker) says: \(displayTranscript)")
        .accessibilityHint("Tap to \(isExpanded ? "collapse" : "expand") transcript history")
    }

    /// Text to display: current live transcript, or last entry if not transcribing.
    private var displayTranscript: String {
        if !transcription.currentTranscript.isEmpty {
            return transcription.currentTranscript
        }
        if let last = transcription.history.last {
            return last.text
        }
        return "Listening..."
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Show last 10 entries max in the overlay
                    let recentEntries = transcription.history.suffix(10)
                    ForEach(recentEntries) { entry in
                        historyRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 200)
            .onChange(of: transcription.history.count) { _, _ in
                if let lastID = transcription.history.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: LiveTranscription.TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.speakerName)
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(Constants.Colors.amber)

                Text(entry.timestamp, style: .time)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)

                Text(String(format: "%.0fs", entry.duration))
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Text(entry.text)
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.speakerName) at \(entry.timestamp.formatted(date: .omitted, time: .shortened)): \(entry.text)")
    }

    // MARK: - Background

    private var overlayBackground: some View {
        ZStack {
            // Glass material
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)

            // Subtle green tint when transcribing
            if transcription.isTranscribing {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Constants.Colors.electricGreen.opacity(0.06))
            }

            // Border
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            (transcription.isTranscribing
                                ? Constants.Colors.electricGreen
                                : Color.white
                            ).opacity(0.2),
                            Constants.Colors.surfaceBorder
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: Constants.Layout.glassBorderWidth
                )
        }
    }

    // MARK: - Show / Hide Logic

    private func showOverlay() {
        cancelHide()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isVisible = true
        }
    }

    private func scheduleHide() {
        cancelHide()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(autoHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = false
                isExpanded = false
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}

// MARK: - Pulsing Animation Modifier

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

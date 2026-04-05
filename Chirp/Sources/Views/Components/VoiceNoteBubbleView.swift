import SwiftUI
import AVFoundation

/// Renders a voice note message inside the chat with a waveform visualization,
/// play/pause control, and duration label. Matches the bubble shape of
/// ``MessageBubbleView`` for visual consistency.
struct VoiceNoteBubbleView: View {

    let audioData: Data
    let duration: TimeInterval
    let isFromSelf: Bool
    var clusterPosition: MessageBubbleView.ClusterPosition = .solo

    @State private var isPlaying: Bool = false
    @State private var playbackProgress: Double = 0
    @State private var player: AVAudioPlayer?
    @State private var playbackTimer: Timer?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isFromSelf ? Constants.Colors.amber : Constants.Colors.blue500)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause voice note" : "Play voice note")

            // Waveform bars
            waveformBars
                .frame(height: 28)

            // Duration
            Text(formatDuration(isPlaying ? duration * playbackProgress : duration))
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice note, \(formatDuration(duration))")
        .accessibilityIdentifier(AccessibilityID.chatVoiceNoteBubble)
    }

    // MARK: - Waveform Bars

    private var waveformBars: some View {
        GeometryReader { geometry in
            let barCount = min(Int(geometry.size.width / 4), 30)
            let bars = generateWaveformBars(count: barCount)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let progress = Double(index) / Double(barCount)
                    let isPlayed = progress <= playbackProgress

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isPlayed
                              ? (isFromSelf ? Constants.Colors.amber : Constants.Colors.blue500)
                              : Constants.Colors.textTertiary.opacity(0.4))
                        .frame(width: 2, height: geometry.size.height * bars[index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Generate pseudo-random waveform bar heights from the audio data hash.
    private func generateWaveformBars(count: Int) -> [CGFloat] {
        let hash = audioData.hashValue
        var bars: [CGFloat] = []
        for i in 0..<count {
            let seed = abs(hash &+ i &* 31)
            let height = CGFloat(seed % 80 + 20) / 100.0
            bars.append(height)
        }
        return bars
    }

    // MARK: - Playback

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        do {
            player = try AVAudioPlayer(data: audioData)
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            playbackProgress = 0

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    guard let player = player, player.duration > 0 else { return }
                    playbackProgress = player.currentTime / player.duration
                    if !player.isPlaying {
                        stopPlayback()
                    }
                }
            }
        } catch {
            isPlaying = false
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        playbackProgress = 0
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

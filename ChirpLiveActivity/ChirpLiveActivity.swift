import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Color Helpers

extension Color {
    static let chirpAmber = Color(red: 1.0, green: 0.75, blue: 0.0)
    static let chirpRed = Color(red: 1.0, green: 0.25, blue: 0.2)
    static let chirpGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
}

// MARK: - Waveform Bar View

/// A single animated bar for the waveform visualizer.
private struct WaveformBar: View {
    let index: Int
    let barCount: Int
    let inputLevel: Double
    let isActive: Bool

    var body: some View {
        let baseHeight: CGFloat = 4
        let maxAdditional: CGFloat = 28
        // Each bar gets a phase-shifted height based on index for a wave look
        let phase = Double(index) / Double(barCount) * .pi * 2
        let levelFactor = isActive ? inputLevel : 0.15
        let animated = (sin(phase + levelFactor * .pi * 3) + 1) / 2
        let height = baseHeight + maxAdditional * CGFloat(levelFactor) * CGFloat(animated)

        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 4, height: height)
            .animation(.interpolatingSpring(stiffness: 200, damping: 8), value: inputLevel)
    }

    private var barColor: some ShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [barTopColor, barTopColor.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.chirpAmber.opacity(0.4))
    }

    private var barTopColor: Color {
        isActive ? Color.chirpAmber : Color.chirpAmber.opacity(0.4)
    }
}

// MARK: - Waveform View

/// A row of animated waveform bars.
private struct WaveformView: View {
    let inputLevel: Double
    let isActive: Bool
    let barCount: Int

    init(inputLevel: Double, isActive: Bool, barCount: Int = 7) {
        self.inputLevel = inputLevel
        self.isActive = isActive
        self.barCount = barCount
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    index: index,
                    barCount: barCount,
                    inputLevel: inputLevel,
                    isActive: isActive
                )
            }
        }
    }
}

// MARK: - Status Text View

private struct StatusTextView: View {
    let pttState: String
    let speakerName: String?

    var body: some View {
        switch pttState {
        case "transmitting":
            Label("Transmitting...", systemImage: "mic.fill")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.chirpRed)
        case "receiving":
            Label(
                "Listening to \(speakerName ?? "someone")",
                systemImage: "speaker.wave.2.fill"
            )
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.chirpGreen)
            .lineLimit(1)
        case "denied":
            Label("Channel busy", systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            Label("Ready", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(Color.chirpAmber)
        }
    }
}

// MARK: - Compact Radio Wave Icon

private struct RadioWaveIcon: View {
    let isTransmitting: Bool

    var body: some View {
        Image(systemName: isTransmitting
              ? "antenna.radiowaves.left.and.right"
              : "antenna.radiowaves.left.and.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isTransmitting ? Color.chirpRed : Color.chirpAmber)
            .symbolEffect(.pulse, options: .repeating, isActive: isTransmitting)
    }
}

// MARK: - Live Activity Widget

struct ChirpLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChirpActivityAttributes.self) { context in
            // MARK: Lock Screen Banner
            lockScreenBanner(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded Regions
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(stateColor(context.state.pttState))
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: context.state.pttState == "transmitting"
                            )
                        Text(context.state.channelName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(context.state.peerCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        WaveformView(
                            inputLevel: context.state.inputLevel,
                            isActive: context.state.pttState == "transmitting"
                                || context.state.pttState == "receiving",
                            barCount: 7
                        )
                        .frame(height: 32)

                        StatusTextView(
                            pttState: context.state.pttState,
                            speakerName: context.state.speakerName
                        )
                    }
                    .padding(.top, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                // MARK: Compact Leading
                RadioWaveIcon(isTransmitting: context.state.pttState == "transmitting")
            } compactTrailing: {
                // MARK: Compact Trailing
                Group {
                    if context.state.pttState == "receiving",
                       let speaker = context.state.speakerName {
                        Text(speaker)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.chirpGreen)
                            .lineLimit(1)
                    } else {
                        Text(context.state.channelName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.chirpAmber)
                            .lineLimit(1)
                    }
                }
            } minimal: {
                // MARK: Minimal
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(stateColor(context.state.pttState))
                    .symbolEffect(
                        .pulse,
                        options: .repeating.speed(0.5),
                        isActive: true
                    )
            }
            .contentMargins(.horizontal, 8, for: .compactLeading)
            .contentMargins(.horizontal, 8, for: .compactTrailing)
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func lockScreenBanner(
        context: ActivityViewContext<ChirpActivityAttributes>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(stateColor(context.state.pttState))
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: context.state.pttState == "transmitting"
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.state.channelName)
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("\(context.state.peerCount)")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.secondary)
                }

                WaveformView(
                    inputLevel: context.state.inputLevel,
                    isActive: context.state.pttState == "transmitting"
                        || context.state.pttState == "receiving",
                    barCount: 7
                )
                .frame(height: 24)

                StatusTextView(
                    pttState: context.state.pttState,
                    speakerName: context.state.speakerName
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .activityBackgroundTint(Color.black.opacity(0.6))
    }

    // MARK: - Helpers

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "transmitting": return .chirpRed
        case "receiving": return .chirpGreen
        case "denied": return .secondary
        default: return .chirpAmber
        }
    }
}

import AVFoundation
import SwiftUI

struct DebugOverlayView: View {
    @Environment(AppState.self) private var appState

    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Constants.Colors.amberInk)

                    Text("DEBUG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Constants.Colors.amberInk)

                    Spacer()

                    Text("tap to close")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Constants.Colors.textTertiary)
                }

                Divider()
                    .background(Constants.Colors.ink.opacity(0.2))

                // PTT State
                HStack(spacing: 6) {
                    Circle()
                        .fill(pttDotColor)
                        .frame(width: 6, height: 6)

                    Text("PTT")
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()

                    Text(pttLabel)
                        .foregroundStyle(pttDotColor)
                }

                // Input level bar
                HStack(spacing: 6) {
                    Text("IN")
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .frame(width: 22, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Constants.Colors.ink.opacity(0.15))

                            RoundedRectangle(cornerRadius: 2)
                                .fill(levelGradient)
                                .frame(width: max(0, geo.size.width * CGFloat(min(appState.inputLevel, 1.0))))
                        }
                    }
                    .frame(height: 5)

                    Text(String(format: "%2.0f", appState.inputLevel * 100))
                        .foregroundStyle(Constants.Colors.amberInk)
                        .frame(width: 22, alignment: .trailing)
                }

                // Audio format
                HStack(spacing: 6) {
                    Text("FMT")
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()

                    let session = AVAudioSession.sharedInstance()
                    Text("\(Int(session.sampleRate))Hz / \(Int(session.outputNumberOfChannels))ch")
                        .foregroundStyle(Constants.Colors.ink.opacity(0.8))
                }

                // Peers
                HStack(spacing: 6) {
                    Text("PEERS")
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()

                    let peerCount = appState.channelManager.activeChannel?.peers.filter(\.isConnected).count ?? 0
                    Text("\(peerCount)")
                        .foregroundStyle(
                            peerCount > 0
                                ? Constants.Colors.electricGreen
                                : Constants.Colors.textTertiary
                        )
                }

                // Channels
                HStack(spacing: 6) {
                    Text("CH")
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()

                    if let active = appState.channelManager.activeChannel {
                        Text(active.name)
                            .foregroundStyle(Constants.Colors.amberInk)
                    } else {
                        Text("none")
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                }

                // FPS counter (using TimelineView for frame counting)
                FPSCounterRow()
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(10)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Constants.Colors.surfaceHover)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Constants.Colors.ink.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    isVisible = false
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
        }
    }

    // MARK: - Computed

    private var pttDotColor: Color {
        switch appState.pttState {
        case .idle: return .gray
        case .transmitting: return Constants.Colors.hotRed
        case .receiving: return Constants.Colors.electricGreen
        case .denied: return Constants.Colors.hotRed.opacity(0.5)
        }
    }

    private var pttLabel: String {
        switch appState.pttState {
        case .idle: return "IDLE"
        case .transmitting: return "TX"
        case .receiving(let name, _): return "RX:\(name)"
        case .denied: return "DENY"
        }
    }

    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [Constants.Colors.electricGreen, Constants.Colors.amber, Constants.Colors.hotRed],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - FPS Counter

private struct FPSCounterRow: View {
    @State private var fps: Int = 0
    @State private var lastTimestamp: Date?
    @State private var frameCount: Int = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil)) { timeline in
            HStack(spacing: 6) {
                Text("FPS")
                    .foregroundStyle(Constants.Colors.textSecondary)

                Spacer()

                Text("\(fps)")
                    .foregroundStyle(fpsColor)
            }
            .onChange(of: timeline.date) { _, newDate in
                frameCount += 1
                guard let last = lastTimestamp else {
                    lastTimestamp = newDate
                    return
                }
                let elapsed = newDate.timeIntervalSince(last)
                if elapsed >= 1.0 {
                    fps = Int(Double(frameCount) / elapsed)
                    frameCount = 0
                    lastTimestamp = newDate
                }
            }
        }
    }

    private var fpsColor: Color {
        if fps >= 55 { return Constants.Colors.electricGreen }
        if fps >= 30 { return Constants.Colors.amberInk }
        return Constants.Colors.hotRed
    }
}

// MARK: - Triple-tap overlay modifier

struct DebugOverlayModifier: ViewModifier {
    @State private var showDebug = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                DebugOverlayView(isVisible: $showDebug)
                    .padding(.top, 60)
                    .padding(.trailing, 12)
                    .animation(.easeInOut(duration: 0.2), value: showDebug)
            }
            .onTapGesture(count: 3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDebug.toggle()
                }
            }
    }
}

extension View {
    func debugOverlay() -> some View {
        modifier(DebugOverlayModifier())
    }
}

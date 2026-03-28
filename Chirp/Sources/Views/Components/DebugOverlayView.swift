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
                        .foregroundStyle(Color(hex: 0xFFB800))

                    Text("DEBUG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFB800))

                    Spacer()

                    Text("tap to close")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // PTT State
                HStack(spacing: 6) {
                    Circle()
                        .fill(pttDotColor)
                        .frame(width: 6, height: 6)

                    Text("PTT")
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Text(pttLabel)
                        .foregroundStyle(pttDotColor)
                }

                // Input level bar
                HStack(spacing: 6) {
                    Text("IN")
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.15))

                            RoundedRectangle(cornerRadius: 2)
                                .fill(levelGradient)
                                .frame(width: max(0, geo.size.width * CGFloat(min(appState.inputLevel, 1.0))))
                        }
                    }
                    .frame(height: 5)

                    Text(String(format: "%2.0f", appState.inputLevel * 100))
                        .foregroundStyle(Color(hex: 0xFFB800))
                        .frame(width: 22, alignment: .trailing)
                }

                // Audio format
                HStack(spacing: 6) {
                    Text("FMT")
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    let session = AVAudioSession.sharedInstance()
                    Text("\(Int(session.sampleRate))Hz / \(Int(session.outputNumberOfChannels))ch")
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Peers
                HStack(spacing: 6) {
                    Text("PEERS")
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Text("\(appState.wifiAwareManager.pairedDevices.count)")
                        .foregroundStyle(
                            appState.wifiAwareManager.pairedDevices.count > 0
                                ? Color(hex: 0x30D158)
                                : .white.opacity(0.5)
                        )
                }

                // Channels
                HStack(spacing: 6) {
                    Text("CH")
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    if let active = appState.channelManager.activeChannel {
                        Text(active.name)
                            .foregroundStyle(Color(hex: 0xFFB800))
                    } else {
                        Text("none")
                            .foregroundStyle(.white.opacity(0.4))
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
                            .fill(Color.black.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
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
        case .transmitting: return Color(hex: 0xFF3B30)
        case .receiving: return Color(hex: 0x30D158)
        case .denied: return Color(hex: 0xFF3B30).opacity(0.5)
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
            colors: [Color(hex: 0x30D158), Color(hex: 0xFFB800), Color(hex: 0xFF3B30)],
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
                    .foregroundStyle(.white.opacity(0.6))

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
        if fps >= 55 { return Color(hex: 0x30D158) }
        if fps >= 30 { return Color(hex: 0xFFB800) }
        return Color(hex: 0xFF3B30)
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

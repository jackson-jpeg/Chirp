import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("chirp.speakerOutput") private var speakerOutput = true
    @AppStorage("chirp.hapticFeedback") private var hapticFeedback = true
    @AppStorage("chirp.chirpSounds") private var chirpSounds = true

    @State private var showUnpairConfirm = false
    @State private var deviceToUnpair: String?
    @State private var debugExpanded = false
    @State private var howItWorksExpanded = false
    @State private var copiedID = false

    var body: some View {
        List {
            // MARK: - Your Device

            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: 0xFFB800).opacity(0.15))
                            .frame(width: 40, height: 40)

                        Image(systemName: "iphone")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFFB800))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.localPeerName)
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(.white)

                        Text(truncatedPeerID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        UIPasteboard.general.string = appState.localPeerID
                        withAnimation(.easeInOut(duration: 0.2)) {
                            copiedID = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copiedID = false }
                        }
                    } label: {
                        Image(systemName: copiedID ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(copiedID ? Color(hex: 0x30D158) : Color(hex: 0xFFB800))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        copiedID
                                            ? Color(hex: 0x30D158).opacity(0.15)
                                            : Color(hex: 0xFFB800).opacity(0.12)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.white.opacity(0.05))
            } header: {
                Label("Your Device", systemImage: "person.crop.circle")
            }

            // MARK: - Audio

            Section {
                Toggle(isOn: $speakerOutput) {
                    settingsRow(icon: "speaker.wave.2.fill", title: "Speaker Output")
                }
                .tint(Color(hex: 0xFFB800))

                Toggle(isOn: $hapticFeedback) {
                    settingsRow(icon: "hand.tap.fill", title: "Haptic Feedback")
                }
                .tint(Color(hex: 0xFFB800))

                Toggle(isOn: $chirpSounds) {
                    settingsRow(icon: "waveform", title: "Chirp Sounds")
                }
                .tint(Color(hex: 0xFFB800))
            } header: {
                Label("Audio", systemImage: "waveform.circle")
            }
            .listRowBackground(Color.white.opacity(0.05))

            // MARK: - Paired Devices

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFB800))
                        .frame(width: 24)

                    let count = appState.wifiAwareManager.pairedDevices.count
                    Text("\(count) paired device\(count == 1 ? "" : "s")")
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Manage")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0xFFB800).opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Label("Paired Devices", systemImage: "antenna.radiowaves.left.and.right")
            }
            .listRowBackground(Color.white.opacity(0.05))

            // MARK: - About

            Section {
                HStack {
                    settingsRow(icon: "info.circle", title: "Version")
                    Spacer()
                    Text(appVersion)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // How Chirp Works - expandable inline
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        howItWorksExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("How Chirp Works")
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(howItWorksExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if howItWorksExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        infoItem(icon: "wifi", title: "Wi-Fi Aware",
                                 text: "Connects devices directly without a router, cell tower, or internet.")
                        infoItem(icon: "mic.fill", title: "Push-to-Talk",
                                 text: "Hold to talk, release to listen. Like a real walkie-talkie.")
                        infoItem(icon: "person.2.fill", title: "Channels",
                                 text: "Create or join channels. Everyone on the same channel hears each other.")
                        infoItem(icon: "lock.shield.fill", title: "Privacy",
                                 text: "All communication stays device-to-device. No servers. Ever.")
                    }
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Rate Chirp
                Button {
                    // TODO: Open App Store review URL
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("Rate Chirp")
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Privacy Policy
                Button {
                    // TODO: Open privacy policy URL
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("Privacy Policy")
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Label("About", systemImage: "info.circle")
            }
            .listRowBackground(Color.white.opacity(0.05))

            // MARK: - Debug

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        debugExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "ladybug.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        Text("Debug Info")
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(debugExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if debugExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        // PTT State with colored dot
                        HStack(spacing: 8) {
                            Circle()
                                .fill(pttStateColor)
                                .frame(width: 8, height: 8)

                            Text("PTT State")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(pttStateLabel)
                                .foregroundStyle(pttStateColor)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Audio session sample rate
                        debugRow("Sample Rate",
                                 value: "\(Int(AVAudioSession.sharedInstance().sampleRate)) Hz")

                        // Input level meter
                        HStack(spacing: 8) {
                            Text("Input Level")
                                .foregroundStyle(.secondary)

                            Spacer()

                            inputLevelBar
                                .frame(width: 100, height: 8)

                            Text(String(format: "%.0f%%", appState.inputLevel * 100))
                                .foregroundStyle(Color(hex: 0xFFB800))
                                .frame(width: 40, alignment: .trailing)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Peer ID (full, copyable)
                        HStack(spacing: 8) {
                            Text("Peer ID")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(appState.localPeerID)
                                .foregroundStyle(Color(hex: 0xFFB800))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .trailing)
                                .textSelection(.enabled)
                        }

                        // Channel count
                        debugRow("Channels",
                                 value: "\(appState.channelManager.channels.count)")

                        // Active channel
                        if let active = appState.channelManager.activeChannel {
                            debugRow("Active Channel", value: active.name)
                        }

                        // Wi-Fi Aware support
                        debugRow("Wi-Fi Aware",
                                 value: appState.wifiAwareManager.isSupported ? "Supported" : "Unsupported")

                        // Paired devices
                        debugRow("Paired Devices",
                                 value: "\(appState.wifiAwareManager.pairedDevices.count)")

                        // Jitter buffer stats
                        debugRow("Jitter Buffer",
                                 value: "init \(Constants.JitterBuffer.initialDepthMs)ms / max \(Constants.JitterBuffer.maxDepthMs)ms")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                Label("Debug", systemImage: "ladybug")
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Computed Properties

    private var truncatedPeerID: String {
        let id = appState.localPeerID
        if id.count > 12 {
            return String(id.prefix(6)) + "..." + String(id.suffix(4))
        }
        return id
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var pttStateColor: Color {
        switch appState.pttState {
        case .idle: return .secondary
        case .transmitting: return Color(hex: 0xFF3B30)
        case .receiving: return Color(hex: 0x30D158)
        case .denied: return Color(hex: 0xFF3B30).opacity(0.6)
        }
    }

    private var pttStateLabel: String {
        switch appState.pttState {
        case .idle: return "Idle"
        case .transmitting: return "Transmitting"
        case .receiving(let name, _): return "Receiving (\(name))"
        case .denied: return "Denied"
        }
    }

    // MARK: - Subviews

    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: 0xFFB800))
                .frame(width: 24)

            Text(title)
        }
    }

    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color(hex: 0xFFB800))
        }
    }

    private var inputLevelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))

                RoundedRectangle(cornerRadius: 4)
                    .fill(inputLevelGradient)
                    .frame(width: max(0, geo.size.width * CGFloat(min(appState.inputLevel, 1.0))))
            }
        }
    }

    private var inputLevelGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x30D158), Color(hex: 0xFFB800), Color(hex: 0xFF3B30)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func infoItem(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0xFFB800))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(.white)

                Text(text)
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

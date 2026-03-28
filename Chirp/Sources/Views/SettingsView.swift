import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var speakerOutput = true
    @State private var hapticFeedback = true
    @State private var showUnpairConfirm = false
    @State private var deviceToUnpair: String?

    var body: some View {
        List {
            // MARK: - Paired Devices
            Section {
                let devices = appState.wifiAwareManager.pairedDevices
                if devices.isEmpty {
                    HStack {
                        Image(systemName: "iphone.slash")
                            .foregroundStyle(.secondary)
                        Text("No paired devices")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(devices.enumerated()), id: \.offset) { index, device in
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(Color(hex: 0x30D158))

                            Text(String(describing: device))
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                deviceToUnpair = String(describing: device)
                                showUnpairConfirm = true
                            } label: {
                                Text("Unpair")
                                    .font(.system(.caption, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xFF3B30))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(hex: 0xFF3B30).opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Paired Devices")
            }

            // MARK: - Audio
            Section {
                Toggle(isOn: $speakerOutput) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("Speaker Output")
                    }
                }
                .tint(Color(hex: 0xFFB800))

                Toggle(isOn: $hapticFeedback) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("Haptic Feedback")
                    }
                }
                .tint(Color(hex: 0xFFB800))
            } header: {
                Text("Audio")
            }

            // MARK: - About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    howChirpWorksView
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Color(hex: 0xFFB800))
                            .frame(width: 24)

                        Text("How Chirp Works")
                    }
                }
            } header: {
                Text("About")
            }

            // MARK: - Debug
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    debugRow("PTT State", value: "\(appState.pttState)")
                    debugRow("Input Level", value: String(format: "%.2f", appState.inputLevel))

                    debugRow("Paired Devices", value: "\(appState.wifiAwareManager.pairedDevices.count)")
                    debugRow("Wi-Fi Aware", value: appState.wifiAwareManager.isSupported ? "Supported" : "Unsupported")

                    debugRow("Channels", value: "\(appState.channelManager.channels.count)")

                    if let active = appState.channelManager.activeChannel {
                        debugRow("Active Channel", value: active.name)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            } header: {
                Text("Debug")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unpair Device?", isPresented: $showUnpairConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Unpair", role: .destructive) {
                // TODO: Implement unpair
            }
        } message: {
            if let device = deviceToUnpair {
                Text("Remove \(device) from paired devices?")
            }
        }
    }

    // MARK: - Debug Row

    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color(hex: 0xFFB800))
        }
    }

    // MARK: - How Chirp Works

    private var howChirpWorksView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    infoSection(
                        icon: "wifi",
                        title: "Wi-Fi Aware",
                        body: "Chirp uses Wi-Fi Aware (Neighbor Awareness Networking) to connect devices directly without a router, cell tower, or internet connection."
                    )

                    infoSection(
                        icon: "mic.fill",
                        title: "Push-to-Talk",
                        body: "Press and hold the talk button to transmit your voice. Release to listen. Just like a walkie-talkie."
                    )

                    infoSection(
                        icon: "person.2.fill",
                        title: "Channels",
                        body: "Create or join a channel to talk with a group. Everyone on the same channel hears each other."
                    )

                    infoSection(
                        icon: "lock.shield.fill",
                        title: "Privacy",
                        body: "All communication stays between paired devices. No data is sent to any server. Ever."
                    )
                }
            }
            .padding(24)
        }
        .background(Color.black)
        .navigationTitle("How Chirp Works")
    }

    private func infoSection(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0xFFB800))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(.white)

                Text(body)
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

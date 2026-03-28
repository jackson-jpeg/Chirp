import SwiftUI
#if canImport(WiFiAware)
import WiFiAware
#endif
#if canImport(DeviceDiscoveryUI)
import DeviceDiscoveryUI
#endif

struct PairingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var searchRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                supportedPairingContent

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .navigationTitle("Pair Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color(hex: 0xFFB800))
                }
            }
        }
    }

    // MARK: - Supported Pairing Content

    @ViewBuilder
    private var supportedPairingContent: some View {
        // Searching animation
        ZStack {
            // Outer pulse rings
            Circle()
                .stroke(Color(hex: 0xFFB800).opacity(pulseOpacity), lineWidth: 1.5)
                .frame(width: 160, height: 160)
                .scaleEffect(pulseScale)

            Circle()
                .stroke(Color(hex: 0xFFB800).opacity(pulseOpacity * 0.6), lineWidth: 1)
                .frame(width: 160, height: 160)
                .scaleEffect(pulseScale * 1.3)

            // Rotating radar sweep
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    AngularGradient(
                        colors: [Color(hex: 0xFFB800).opacity(0), Color(hex: 0xFFB800).opacity(0.5)],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(searchRotation))

            // Center device icon
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFB800))
        }

        Text("Searching for nearby devices...")
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(.white)

        Text("Open Chirp on the other device too")
            .font(.system(.subheadline))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 40)
            .multilineTextAlignment(.center)

        // Paired devices list
        if !appState.wifiAwareManager.pairedDevices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("PAIRED DEVICES")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ForEach(Array(appState.wifiAwareManager.pairedDevices.enumerated()), id: \.offset) { _, device in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundStyle(Color(hex: 0x30D158))

                        Text(String(describing: device))
                            .foregroundStyle(.white)

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: 0x30D158))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
            }
        }

        #if canImport(DeviceDiscoveryUI) && canImport(WiFiAware)
        // Device picker for Wi-Fi Aware pairing
        DevicePairingView(
            .wifiAware(.connecting(to: .chirpPTT, from: .selected([])))
        ) {
            Text("Waiting for nearby devices...")
                .foregroundStyle(.secondary)
        } fallback: {
            Text("Wi-Fi Aware pairing not supported on this device.")
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
        .padding(.horizontal, 16)
        #endif

        Spacer()
    }

    // MARK: - Unsupported Content

    private var unsupportedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color(hex: 0xFF3B30).opacity(0.7))

            Text("Wi-Fi Aware Not Supported")
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(.white)

            Text("This device doesn't support Wi-Fi Aware.\nChirp requires iOS 26+ and compatible hardware.")
                .font(.system(.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Animations

    fileprivate func startAnimations() {
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            searchRotation = 360
        }

        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
            pulseOpacity = 0.1
        }
    }
}

extension PairingView {
    func onAppearAnimations() -> some View {
        self.onAppear {
            startAnimations()
        }
    }
}

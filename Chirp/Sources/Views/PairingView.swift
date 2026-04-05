import SwiftUI
import WiFiAware
import DeviceDiscoveryUI

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
            .navigationTitle(String(localized: "Pair Devices"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                    .foregroundStyle(Constants.Colors.amber)
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
                .stroke(Constants.Colors.amber.opacity(pulseOpacity), lineWidth: 1.5)
                .frame(width: 160, height: 160)
                .scaleEffect(pulseScale)

            Circle()
                .stroke(Constants.Colors.amber.opacity(pulseOpacity * 0.6), lineWidth: 1)
                .frame(width: 160, height: 160)
                .scaleEffect(pulseScale * 1.3)

            // Rotating radar sweep
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(
                    AngularGradient(
                        colors: [Constants.Colors.amber.opacity(0), Constants.Colors.amber.opacity(0.5)],
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(searchRotation))

            // Center device icon
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Constants.Colors.amber)
        }

        Text(String(localized: "Searching for nearby devices..."))
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(.white)

        Text(String(localized: "Open Chirp on the other device too"))
            .font(.system(.subheadline))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 40)
            .multilineTextAlignment(.center)

        // Paired devices list
        if let waTransport = appState.wifiAwareTransport, waTransport.pairedDeviceCount > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "PAIRED DEVICES"))
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(Constants.Colors.electricGreen)

                    Text(String(localized: "\(waTransport.pairedDeviceCount) paired device\(waTransport.pairedDeviceCount == 1 ? "" : "s")"))
                        .foregroundStyle(.white)

                    Spacer()

                    if waTransport.connectedPeerCount > 0 {
                        Text(String(localized: "\(waTransport.connectedPeerCount) connected"))
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Constants.Colors.electricGreen)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }
        }

        if let service = WAPublishableService.chirpPTT {
            DevicePairingView(
                .wifiAware(.connecting(to: service, from: .selected([])))
            ) {
                Text(String(localized: "Waiting for nearby devices..."))
                    .foregroundStyle(.secondary)
            } fallback: {
                Text(String(localized: "Wi-Fi Aware pairing not supported on this device."))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 200)
            .padding(.horizontal, 16)
        }

        Spacer()
    }

    // MARK: - Unsupported Content

    private var unsupportedContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Constants.Colors.hotRed.opacity(0.7))

            Text(String(localized: "Wi-Fi Aware Not Supported"))
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(.white)

            Text(String(localized: "This device doesn't support Wi-Fi Aware.\nChirp requires iOS 26+ and compatible hardware."))
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

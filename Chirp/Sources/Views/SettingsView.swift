import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @AppStorage("chirp.speakerOutput") private var speakerOutput = true
    @AppStorage("chirp.hapticFeedback") private var hapticFeedback = true
    @AppStorage("chirp.chirpSounds") private var chirpSounds = true

    @State private var debugExpanded = false
    @State private var howItWorksExpanded = false
    @State private var copiedID = false
    @State private var showActionButtonSetup = false

    // MARK: - Color shortcuts

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen
    private let red = Constants.Colors.hotRed

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeroCard
                meshNetworkSection
                LinkHealthSection()
                audioHapticsSection
                quickAccessSection
                emergencySection
                privacySecuritySection
                meshCloudSection
                aboutSection
                debugSection

                // Version footer
                Text("ChirpChirp \(appVersion)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.top, 4)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .accessibilityIdentifier(AccessibilityID.settingsView)
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showActionButtonSetup) {
            ActionButtonSetupView()
        }
    }

    // MARK: - Profile Hero Card

    private var profileHeroCard: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [amber, amber.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Text(avatarInitial)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }
            .shadow(color: amber.opacity(0.3), radius: 12, y: 4)

            // Callsign (editable)
            VStack(spacing: 6) {
                TextField(String(localized: "settings.profile.callsign"), text: Bindable(appState).callsign)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                // Peer ID fingerprint
                HStack(spacing: 8) {
                    Image(systemName: "fingerprint")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))

                    Text(truncatedPeerID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    Button {
                        UIPasteboard.general.string = appState.localPeerID
                        withAnimation(.easeInOut(duration: 0.2)) {
                            copiedID = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copiedID = false }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedID ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(copiedID ? String(localized: "settings.profile.copied") : String(localized: "settings.profile.copyID"))
                                .font(.system(.caption2, weight: .semibold))
                        }
                        .foregroundStyle(copiedID ? green : amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill((copiedID ? green : amber).opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Mesh Network

    private var meshNetworkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "point.3.connected.trianglepath.dotted", title: String(localized: "settings.meshNetwork.title"))

            VStack(spacing: 1) {
                // Wi-Fi Aware status
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi")
                            .foregroundStyle(appState.wifiAwareTransport != nil ? green : .secondary)
                            .frame(width: 24)
                        Text(String(localized: "settings.meshNetwork.wifiAware"))
                            .foregroundStyle(.white)
                        Spacer()
                        statusBadge(
                            text: appState.wifiAwareTransport != nil ? String(localized: "settings.status.active") : String(localized: "settings.status.unavailable"),
                            color: appState.wifiAwareTransport != nil ? green : .secondary
                        )
                    }
                }

                // Nearby peers
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(appState.connectedPeerCount > 0 ? green : amber)
                            .frame(width: 24)
                        Text(String(localized: "settings.meshNetwork.nearbyPeers"))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(appState.connectedPeerCount)")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(appState.connectedPeerCount > 0 ? green : .secondary)
                    }
                }

                // Paired devices
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .foregroundStyle(amber)
                            .frame(width: 24)
                        Text(String(localized: "settings.meshNetwork.pairedDevices"))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(appState.wifiAwareTransport?.pairedDeviceCount ?? 0)")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Mesh stats
                meshStatsRows

                // Local network permission
                glassRow {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "network")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.meshNetwork.localNetworkPermission"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(String(localized: "settings.meshNetwork.localNetworkHint"))
                .font(.system(.caption2))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var meshStatsRows: some View {
        let stats = appState.meshStats

        glassRow {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(amber)
                    .frame(width: 24)
                Text(String(localized: "settings.meshNetwork.packetsRelayed"))
                    .foregroundStyle(.white)
                Spacer()
                meshStatValue(stats.map { "\($0.relayed)" } ?? "\u{2014}",
                              color: stats.map { $0.relayed > 0 ? green : amber } ?? .secondary)
            }
        }

        glassRow {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(amber)
                    .frame(width: 24)
                Text(String(localized: "settings.meshNetwork.delivered"))
                    .foregroundStyle(.white)
                Spacer()
                meshStatValue(stats.map { "\($0.delivered)" } ?? "\u{2014}",
                              color: stats.map { $0.delivered > 0 ? green : amber } ?? .secondary)
            }
        }

        glassRow {
            HStack(spacing: 12) {
                Image(systemName: "arrow.3.trianglepath")
                    .foregroundStyle(amber)
                    .frame(width: 24)
                Text(String(localized: "settings.meshNetwork.deduplicated"))
                    .foregroundStyle(.white)
                Spacer()
                meshStatValue(stats.map { "\($0.deduplicated)" } ?? "\u{2014}",
                              color: .secondary)
            }
        }

        glassRow {
            HStack(spacing: 12) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(amber)
                    .frame(width: 24)
                Text(String(localized: "settings.meshNetwork.maxHops"))
                    .foregroundStyle(.white)
                Spacer()
                meshStatValue(stats.map { "\($0.maxHops)" } ?? "\u{2014}",
                              color: stats.map { $0.maxHops > 1 ? green : amber } ?? .secondary)
            }
        }

        glassRow {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .foregroundStyle(amber)
                    .frame(width: 24)
                Text(String(localized: "settings.meshNetwork.estRange"))
                    .foregroundStyle(.white)
                Spacer()
                meshStatValue(stats.map { "\($0.estimatedRangeMeters)m" } ?? "\u{2014}",
                              color: stats.map { $0.estimatedRangeMeters > 100 ? green : amber } ?? .secondary)
            }
        }
    }

    private func meshStatValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(.body, design: .monospaced, weight: .medium))
            .foregroundStyle(color)
    }

    // MARK: - Audio & Haptics

    private var audioHapticsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "waveform.circle", title: String(localized: "settings.audioHaptics.title"))

            VStack(spacing: 1) {
                glassRow {
                    Toggle(isOn: $speakerOutput) {
                        settingsRow(icon: "speaker.wave.2.fill", title: String(localized: "settings.audioHaptics.speakerOutput"))
                    }
                    .tint(amber)
                }

                glassRow {
                    Toggle(isOn: $hapticFeedback) {
                        settingsRow(icon: "hand.tap.fill", title: String(localized: "settings.audioHaptics.hapticFeedback"))
                    }
                    .tint(amber)
                }

                glassRow {
                    Toggle(isOn: $chirpSounds) {
                        settingsRow(icon: "waveform", title: String(localized: "settings.audioHaptics.chirpSounds"))
                    }
                    .tint(amber)
                }

                glassRow {
                    Toggle(isOn: Binding(
                        get: { appState.pttEngine.loopbackMode },
                        set: { appState.pttEngine.loopbackMode = $0 }
                    )) {
                        settingsRow(icon: "arrow.triangle.2.circlepath", title: String(localized: "settings.audioHaptics.loopbackTest"))
                    }
                    .tint(amber)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(String(localized: "settings.audioHaptics.loopbackDescription"))
                .font(.system(.caption2))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
    }

    // MARK: - Quick Access

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "bolt.fill", title: String(localized: "settings.quickAccess.title"))

            VStack(spacing: 1) {
                glassRow {
                    Button {
                        showActionButtonSetup = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "button.horizontal.top.press.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.quickAccess.actionButton"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.circle")
                            .foregroundStyle(amber)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.quickAccess.siriShortcut"))
                                .foregroundStyle(.white)
                            Text(String(localized: "settings.quickAccess.siriShortcutHint"))
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Emergency

    private var emergencySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "sos", title: String(localized: "settings.emergency.title"))

            VStack(spacing: 1) {
                glassRow {
                    Toggle(isOn: Binding(
                        get: { EmergencyMode.shared.isActive },
                        set: { newValue in
                            if newValue {
                                EmergencyMode.shared.activate()
                            } else {
                                EmergencyMode.shared.deactivate()
                            }
                        }
                    )) {
                        settingsRow(icon: "exclamationmark.octagon.fill", title: String(localized: "settings.emergency.emergencyMode"))
                    }
                    .tint(Constants.Colors.emergencyRed)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(String(localized: "settings.emergency.emergencyModeDescription"))
                .font(.system(.caption2))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
    }


    // MARK: - Privacy & Security

    private var privacySecuritySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "lock.shield.fill", title: String(localized: "settings.privacySecurity.title"))

            VStack(spacing: 1) {
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(green)
                            .frame(width: 24)
                        Text(String(localized: "settings.privacySecurity.e2eEncryption"))
                            .foregroundStyle(.white)
                        Spacer()
                        statusBadge(text: String(localized: "settings.status.on"), color: green)
                    }
                }

                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "fingerprint")
                            .foregroundStyle(amber)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.privacySecurity.yourFingerprint"))
                                .foregroundStyle(.white)
                            Text(formattedFingerprint)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }

                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.privacySecurity.zeroServers"))
                                .foregroundStyle(.white)
                            Text(String(localized: "settings.privacySecurity.zeroServersDescription"))
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                    }
                }

                glassRow {
                    Toggle(isOn: Binding(
                        get: { appState.cicadaService.isEnabled },
                        set: { appState.cicadaService.isEnabled = $0 }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "eye.slash.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CICADA")
                                    .foregroundStyle(.white)
                                Text("Hidden messages in plain sight")
                                    .font(.system(.caption2))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .tint(amber)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Mesh Cloud

    private var meshCloudSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "cloud.fill", title: "Mesh Cloud")

            VStack(spacing: 1) {
                glassRow {
                    NavigationLink {
                        MeshCloudView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cloud.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Distributed Backup")
                                    .foregroundStyle(.white)
                                Text(meshCloudStatusText)
                                    .font(.system(.caption2))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var meshCloudStatusText: String {
        let service = appState.meshCloudService
        if service.isDonating {
            let usedMB = Double(service.storageDonated) / (1024.0 * 1024.0)
            return String(format: "Donating %.1f / %d MB", usedMB, service.storageQuotaMB)
        } else {
            return "Storage donation paused"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "info.circle", title: String(localized: "settings.about.title"))

            VStack(spacing: 1) {
                // How Chirp Works
                glassRow {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            howItWorksExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.about.howItWorks"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(howItWorksExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                }

                if howItWorksExpanded {
                    glassRow {
                        VStack(alignment: .leading, spacing: 14) {
                            infoItem(icon: "wifi", title: String(localized: "settings.about.wifiAware.title"),
                                     text: String(localized: "settings.about.wifiAware.description"))
                            infoItem(icon: "mic.fill", title: String(localized: "settings.about.pushToTalk.title"),
                                     text: String(localized: "settings.about.pushToTalk.description"))
                            infoItem(icon: "person.2.fill", title: String(localized: "settings.about.channels.title"),
                                     text: String(localized: "settings.about.channels.description"))
                            infoItem(icon: "lock.shield.fill", title: String(localized: "settings.about.privacy.title"),
                                     text: String(localized: "settings.about.privacy.description"))
                        }
                        .padding(.vertical, 4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Rate
                glassRow {
                    Button {
                        if let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.about.rateApp"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Privacy Policy
                glassRow {
                    Button {
                        if let url = URL(string: "https://chirpchirp.app/privacy") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.about.privacyPolicy"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Open Source
                glassRow {
                    Button {
                        if let url = URL(string: "https://chirpchirp.app/credits") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text(String(localized: "settings.about.openSourceCredits"))
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Debug

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "ladybug.fill", title: "Debug", dimmed: true)

            VStack(spacing: 1) {
                glassRow {
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
                }

                if debugExpanded {
                    glassRow {
                        VStack(alignment: .leading, spacing: 10) {
                            // PTT State
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

                            thinDivider

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
                                    .foregroundStyle(amber)
                                    .frame(width: 40, alignment: .trailing)
                            }

                            thinDivider

                            HStack(spacing: 8) {
                                Text("Peer ID")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(appState.localPeerID)
                                    .foregroundStyle(amber)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 160, alignment: .trailing)
                                    .textSelection(.enabled)
                            }

                            debugRow("Channels",
                                     value: "\(appState.channelManager.channels.count)")

                            if let active = appState.channelManager.activeChannel {
                                debugRow("Active Channel", value: active.name)
                            }

                            debugRow("Wi-Fi Aware",
                                     value: appState.wifiAwareTransport != nil ? "Active" : "Unsupported")

                            debugRow("Paired Devices (WA)",
                                     value: "\(appState.wifiAwareTransport?.pairedDeviceCount ?? 0)")

                            debugRow("Connected (WA)",
                                     value: "\(appState.wifiAwareTransport?.connectedPeerCount ?? 0)")

                            debugRow("Jitter Buffer",
                                     value: "init \(Constants.JitterBuffer.initialDepthMs)ms / max \(Constants.JitterBuffer.maxDepthMs)ms")

                            thinDivider

                            if let stats = appState.meshStats {
                                HStack(spacing: 6) {
                                    Image(systemName: "point.3.connected.trianglepath.dotted")
                                        .foregroundStyle(amber)
                                        .font(.system(size: 10))
                                    Text("Mesh Network")
                                        .foregroundStyle(.white)
                                        .font(.system(.caption, weight: .semibold))
                                }

                                debugRow("Seen Packets", value: "\(stats.seenPacketCount)")
                                debugRow("Relayed", value: "\(stats.relayed)")
                                debugRow("Delivered", value: "\(stats.delivered)")
                                debugRow("Deduplicated", value: "\(stats.deduplicated)")
                                debugRow("Max Hops", value: "\(stats.maxHops)")
                                debugRow("Est. Range", value: "\(stats.estimatedRangeMeters)m")
                            } else {
                                debugRow("Mesh Stats", value: "No data")
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .padding(.vertical, 4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Computed Properties

    private var avatarInitial: String {
        let callsign = appState.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = callsign.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var truncatedPeerID: String {
        let id = appState.localPeerID
        if id.count > 12 {
            return String(id.prefix(6)) + "\u{2022}\u{2022}\u{2022}" + String(id.suffix(4))
        }
        return id
    }

    private var formattedFingerprint: String {
        let id = appState.localPeerID
        // Format as groups of 4 chars separated by colons for fingerprint look
        let cleaned = id.replacingOccurrences(of: "-", with: "")
        var result: [String] = []
        var current = ""
        for (i, char) in cleaned.enumerated() {
            current.append(char)
            if (i + 1) % 4 == 0 {
                result.append(current)
                current = ""
                if result.count >= 4 { break }
            }
        }
        if !current.isEmpty && result.count < 4 {
            result.append(current)
        }
        return result.joined(separator: ":")
    }

    // Replace with actual App Store ID after creating the listing
    private let appID = "6743210000"

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var pttStateColor: Color {
        switch appState.pttState {
        case .idle: return .secondary
        case .transmitting: return red
        case .receiving: return green
        case .denied: return red.opacity(0.6)
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

    // MARK: - Reusable Components

    private func sectionHeader(icon: String, title: String, dimmed: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dimmed ? .secondary : amber)

            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white.opacity(dimmed ? 0.35 : 0.6))
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    private func glassRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
    }

    private var glassBackground: some View {
        ZStack {
            Color.white.opacity(0.06)
            // Subtle inner glow at top
            LinearGradient(
                colors: [.white.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.caption2, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(amber)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.white)
        }
    }

    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(amber)
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
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
            colors: [green, amber, red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func infoItem(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(amber)
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

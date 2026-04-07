import SwiftUI

/// Network diagnostics sheet showing mesh peers, packet stats, dedup rate, and hops observed.
/// Presented via long-press on the MeshStatusStrip in HomeView.
struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState

    @State private var peers: [ChirpPeer] = []
    @State private var meshStats: MeshStats?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    meshOverviewSection
                    peersSection
                    packetStatsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Constants.Colors.backgroundPrimary)
            .navigationTitle(String(localized: "diagnostics.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                while !Task.isCancelled {
                    peers = await appState.peerTracker.allPeers
                    meshStats = appState.meshStats
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    // MARK: - Mesh Overview

    private var meshOverviewSection: some View {
        VStack(spacing: 12) {
            sectionHeader(String(localized: "diagnostics.meshOverview"), icon: "antenna.radiowaves.left.and.right")

            let stats = meshStats
            let connectedCount = peers.filter(\.isConnected).count

            HStack(spacing: 12) {
                statCard(
                    label: String(localized: "diagnostics.peersConnected"),
                    value: "\(connectedCount)",
                    color: connectedCount > 0 ? Constants.Colors.electricGreen : Constants.Colors.slate500
                )
                statCard(
                    label: String(localized: "diagnostics.totalPeers"),
                    value: "\(peers.count)",
                    color: Constants.Colors.amber
                )
                statCard(
                    label: String(localized: "diagnostics.maxHops"),
                    value: "\(stats?.maxHops ?? 0)",
                    color: (stats?.maxHops ?? 0) >= 1 ? Constants.Colors.amber : Constants.Colors.slate500
                )
                statCard(
                    label: String(localized: "diagnostics.estRange"),
                    value: stats.map { "\($0.estimatedRangeMeters)m" } ?? "—",
                    color: Constants.Colors.slate400
                )
            }
        }
    }

    // MARK: - Peers

    private var peersSection: some View {
        VStack(spacing: 12) {
            sectionHeader(String(localized: "diagnostics.peersInRange"), icon: "person.2.fill")

            if peers.isEmpty {
                HStack {
                    Text(String(localized: "diagnostics.noPeers"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.slate500)
                    Spacer()
                }
                .padding(16)
                .background(glassBackground)
            } else {
                VStack(spacing: 0) {
                    ForEach(peers) { peer in
                        peerRow(peer)

                        if peer.id != peers.last?.id {
                            Divider()
                                .background(Constants.Colors.slate700)
                        }
                    }
                }
                .background(glassBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func peerRow(_ peer: ChirpPeer) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(peer.isConnected ? Constants.Colors.electricGreen : Constants.Colors.slate600)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text(peer.transportType.rawValue)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Constants.Colors.slate500)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                signalBars(strength: peer.signalStrength)

                Text(heartbeatAge(peer.lastHeartbeat))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Constants.Colors.slate500)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(peer.name), \(peer.isConnected ? "connected" : "disconnected"), signal \(peer.signalStrength) of 3")
    }

    // MARK: - Packet Stats

    private var packetStatsSection: some View {
        VStack(spacing: 12) {
            sectionHeader(String(localized: "diagnostics.packetStats"), icon: "arrow.triangle.swap")

            if let stats = meshStats {
                VStack(spacing: 0) {
                    statRow(
                        label: String(localized: "diagnostics.delivered"),
                        value: "\(stats.delivered)",
                        icon: "checkmark.circle.fill",
                        color: Constants.Colors.electricGreen
                    )
                    Divider().background(Constants.Colors.slate700)
                    statRow(
                        label: String(localized: "diagnostics.relayed"),
                        value: "\(stats.relayed)",
                        icon: "arrow.triangle.branch",
                        color: Constants.Colors.amber
                    )
                    Divider().background(Constants.Colors.slate700)
                    statRow(
                        label: String(localized: "diagnostics.deduplicated"),
                        value: "\(stats.deduplicated)",
                        icon: "doc.on.doc.fill",
                        color: Constants.Colors.slate400
                    )
                    Divider().background(Constants.Colors.slate700)
                    statRow(
                        label: String(localized: "diagnostics.dedupRate"),
                        value: dedupRate(stats),
                        icon: "percent",
                        color: Constants.Colors.slate400
                    )
                    Divider().background(Constants.Colors.slate700)
                    statRow(
                        label: String(localized: "diagnostics.seenPackets"),
                        value: "\(stats.seenPacketCount)",
                        icon: "eye.fill",
                        color: Constants.Colors.slate500
                    )
                }
                .background(glassBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    Text(String(localized: "diagnostics.noStats"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Constants.Colors.slate500)
                    Spacer()
                }
                .padding(16)
                .background(glassBackground)
            }
        }
    }

    // MARK: - Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.Colors.amber)

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Constants.Colors.slate400)
                .textCase(.uppercase)

            Spacer()
        }
    }

    private func statCard(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Constants.Colors.slate500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Constants.Colors.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Constants.Colors.slate400)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func signalBars(strength: Int) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < strength ? Constants.Colors.electricGreen : Constants.Colors.slate700)
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }

    private var glassBackground: some ShapeStyle {
        Constants.Colors.slate800.opacity(0.5)
    }

    // MARK: - Helpers

    private func dedupRate(_ stats: MeshStats) -> String {
        let total = stats.delivered + stats.deduplicated
        guard total > 0 else { return "0%" }
        let rate = Double(stats.deduplicated) / Double(total) * 100
        return String(format: "%.1f%%", rate)
    }

    private func heartbeatAge(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 1 { return "now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        return "\(Int(elapsed / 60))m ago"
    }
}

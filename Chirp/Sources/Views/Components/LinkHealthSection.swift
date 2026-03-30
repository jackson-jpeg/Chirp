import SwiftUI

/// WiFi Aware per-peer link health dashboard, designed as a section for SettingsView.
struct LinkHealthSection: View {
    @Environment(AppState.self) private var appState

    // MARK: - Colors

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen
    private let red = Constants.Colors.hotRed

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            VStack(spacing: 1) {
                aggregateRow
                peerCards
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(amber)

            Text("LINK HEALTH")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Aggregate Row

    private var aggregateRow: some View {
        glassRow {
            if appState.wifiAwareTransport == nil {
                // Device does not support WiFi Aware
                HStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WiFi Aware Unavailable")
                            .foregroundStyle(.white.opacity(0.5))
                        Text("This device does not support WiFi Aware")
                            .font(.system(.caption2))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Spacer()
                }
            } else {
                let metrics = Array(appState.wifiAwareLinkMetrics.values)
                let peerCount = appState.wifiAwareTransport?.connectedPeerCount ?? 0

                HStack(spacing: 16) {
                    // Peers connected
                    aggregateStat(
                        value: "\(peerCount)",
                        label: "Peers",
                        color: peerCount > 0 ? green : .secondary
                    )

                    dividerBar

                    // Average signal
                    aggregateStat(
                        value: averageSignalText(metrics),
                        label: "Avg Signal",
                        color: averageSignalColor(metrics)
                    )

                    dividerBar

                    // Capacity
                    aggregateStat(
                        value: capacityText,
                        label: "Capacity",
                        color: amber
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Per-Peer Cards

    @ViewBuilder
    private var peerCards: some View {
        let metrics = appState.wifiAwareLinkMetrics

        if appState.wifiAwareTransport != nil {
            if metrics.isEmpty {
                glassRow {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(amber.opacity(0.5))
                            .scaleEffect(0.8)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No peers connected")
                                .foregroundStyle(.white.opacity(0.5))
                            Text("Waiting for WiFi Aware devices\u{2026}")
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                        Spacer()
                    }
                }
            } else {
                ForEach(Array(metrics.values).sorted(by: { $0.deviceName < $1.deviceName })) { peer in
                    peerCard(peer)
                }
            }
        }
    }

    // MARK: - Single Peer Card

    private func peerCard(_ peer: WALinkMetrics) -> some View {
        glassRow {
            VStack(alignment: .leading, spacing: 10) {
                // Header: name + signal bars + uptime
                HStack(spacing: 10) {
                    SignalStrengthIndicator(level: peer.signalBars)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(peer.deviceName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let uptime = peer.connectionUptime {
                            Text("Up \(formatDuration(uptime))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }

                    Spacer()

                    // Quality badge
                    qualityBadge(peer.qualityLabel)
                }

                thinDivider

                // Latency row
                HStack(spacing: 0) {
                    metricBlock(
                        icon: "mic.fill",
                        label: "Voice",
                        value: peer.voiceLatency.map { formatLatency($0) } ?? "\u{2014}",
                        color: latencyColor(peer.voiceLatency)
                    )

                    Spacer()

                    metricBlock(
                        icon: "ellipsis.circle",
                        label: "Best Effort",
                        value: peer.bestEffortLatency.map { formatLatency($0) } ?? "\u{2014}",
                        color: .secondary
                    )

                    Spacer()

                    // Throughput
                    metricBlock(
                        icon: "arrow.up.arrow.down",
                        label: "Throughput",
                        value: throughputText(peer),
                        color: amber
                    )
                }

                // Bandwidth usage bar
                if let ratio = peer.capacityRatio {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Bandwidth")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                            Spacer()
                            Text(String(format: "%.0f%%", ratio * 100))
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                .foregroundStyle(bandwidthColor(ratio))
                        }
                        capacityBar(ratio: ratio)
                    }
                }
            }
        }
    }

    // MARK: - Capacity Bar

    private func capacityBar(ratio: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [green, amber, red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(min(ratio, 1.0))))
            }
        }
        .frame(height: 6)
    }

    // MARK: - Metric Block

    private func metricBlock(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.7))
                Text(label)
                    .font(.system(.caption2))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Aggregate Stat

    private func aggregateStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerBar: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 32)
    }

    // MARK: - Quality Badge

    private func qualityBadge(_ label: String) -> some View {
        let color = qualityColor(label)
        return Text(label)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    // MARK: - Helpers

    private func glassRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
    }

    // MARK: - Formatting

    private func formatDuration(_ d: Duration) -> String {
        let total = Int(d.components.seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    private func formatLatency(_ d: Duration) -> String {
        let ms = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
        if ms < 1 {
            return "<1ms"
        }
        return String(format: "%.0fms", ms)
    }

    private func throughputText(_ peer: WALinkMetrics) -> String {
        guard let capacity = peer.throughputCapacity else { return "\u{2014}" }
        let capMbps = capacity / 1_000_000
        if let ceiling = peer.throughputCeiling {
            let ceilMbps = ceiling / 1_000_000
            return String(format: "%.0f/%.0f", capMbps, ceilMbps)
        }
        return String(format: "%.0f Mbps", capMbps)
    }

    // MARK: - Colors

    private func latencyColor(_ d: Duration?) -> Color {
        guard let d else { return .secondary }
        let ms = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
        if ms < 30 { return green }
        if ms < 80 { return amber }
        return red
    }

    private func bandwidthColor(_ ratio: Double) -> Color {
        if ratio < 0.5 { return green }
        if ratio < 0.8 { return amber }
        return red
    }

    private func qualityColor(_ label: String) -> Color {
        switch label {
        case "Excellent": return green
        case "Good": return green.opacity(0.8)
        case "Fair": return amber
        case "Poor": return red
        default: return .secondary
        }
    }

    private func averageSignalText(_ metrics: [WALinkMetrics]) -> String {
        let measured = metrics.compactMap(\.signalStrength)
        guard !measured.isEmpty else { return "\u{2014}" }
        let avg = measured.reduce(0, +) / Double(measured.count)
        return String(format: "%.0f dBm", avg)
    }

    private func averageSignalColor(_ metrics: [WALinkMetrics]) -> Color {
        let measured = metrics.compactMap(\.signalStrength)
        guard !measured.isEmpty else { return .secondary }
        let avg = measured.reduce(0, +) / Double(measured.count)
        if avg > -50 { return green }
        if avg > -70 { return amber }
        return red
    }

    private var capacityText: String {
        let connected = appState.wifiAwareTransport?.connectedPeerCount ?? 0
        // WACapabilities.maximumConnectableDevices is not yet available at runtime,
        // so we show count only or a placeholder max.
        return "\(connected)"
    }
}

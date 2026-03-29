import SwiftUI

/// Full privacy dashboard showing privacy score, tracking alerts, and broadcast analysis.
struct PrivacyShieldView: View {
    @Environment(AppState.self) private var appState
    @State private var expandedBroadcastID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Layout.spacing) {
                // MARK: - Privacy Score Gauge
                privacyScoreCard

                // MARK: - Scanner Status
                scannerStatusCard

                // MARK: - Tracking Alerts
                if !appState.privacyShield.trackingAlerts.isEmpty {
                    trackingAlertsSection
                }

                // MARK: - What You Broadcast
                broadcastSection

                Spacer(minLength: 40)
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.top, 12)
        }
        .background(Constants.Colors.backgroundPrimary)
        .navigationTitle("Privacy Shield")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Privacy Score

    private var privacyScoreCard: some View {
        let score = appState.privacyShield.privacyScore
        let scoreColor = scoreColor(for: score)

        return VStack(spacing: 16) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Constants.Colors.surfaceGlass, lineWidth: 10)
                    .frame(width: 160, height: 160)

                // Score ring
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(
                        scoreColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping), value: score)

                // Score text
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(scoreColor)
                        .contentTransition(.numericText())
                    Text("Privacy Score")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }

            Text(scoreDescription(for: score))
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(scoreColor.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Privacy score: \(score) out of 100. \(scoreDescription(for: score))")
        .accessibilityIdentifier(AccessibilityID.privacyScoreGauge)
    }

    // MARK: - Scanner Status

    private var scannerStatusCard: some View {
        let scanner = appState.bleScanner
        let shield = appState.privacyShield

        return VStack(spacing: 12) {
            if scanner.isScanning {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Constants.Colors.amber)
                        .scaleEffect(0.8)
                    Text("Analyzing environment... \(scanner.discoveredDevices.count) devices detected")
                        .font(Constants.Typography.body)
                        .foregroundStyle(Constants.Colors.textSecondary)
                }

                Button {
                    shield.analyze()
                } label: {
                    Text("Refresh Analysis")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.amber)
                }
                .buttonStyle(.plain)
            } else {
                Text("Start a room scan to analyze your environment")
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textSecondary)

                Button {
                    scanner.startScanning()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Start Scanning")
                            .font(Constants.Typography.body)
                    }
                    .foregroundStyle(Constants.Colors.amber)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                            .fill(Constants.Colors.amber.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                                    .stroke(Constants.Colors.amber.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(Constants.Colors.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Tracking Alerts

    private var trackingAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Constants.Colors.hotRed)
                Text("Tracking Alerts")
                    .font(Constants.Typography.sectionTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)
            }

            ForEach(appState.privacyShield.trackingAlerts) { alert in
                trackingAlertRow(alert)
            }
        }
    }

    private func trackingAlertRow(_ alert: TrackingAlert) -> some View {
        let isHighConfidence = alert.confidence >= 0.7
        let tintColor = isHighConfidence ? Constants.Colors.hotRed : Constants.Colors.amber

        return VStack(alignment: .leading, spacing: 10) {
            // Device name and alert type
            HStack {
                Image(systemName: iconForAlertType(alert.alertType))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tintColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tintColor.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.device.name ?? alert.device.manufacturerName ?? "Unknown Device")
                        .font(Constants.Typography.cardTitle)
                        .foregroundStyle(Constants.Colors.textPrimary)

                    Text(alert.alertType.rawValue)
                        .font(Constants.Typography.caption)
                        .foregroundStyle(tintColor)
                }

                Spacer()

                // Distance estimate from RSSI
                VStack(alignment: .trailing, spacing: 2) {
                    Text(estimateDistance(rssi: alert.device.rssi))
                        .font(Constants.Typography.mono)
                        .foregroundStyle(Constants.Colors.textSecondary)
                    Text("est. distance")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }
            }

            // Confidence bar
            HStack(spacing: 8) {
                Text("Confidence")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Constants.Colors.surfaceGlass)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tintColor)
                            .frame(width: geometry.size.width * alert.confidence, height: 6)
                    }
                }
                .frame(height: 6)

                Text("\(Int(alert.confidence * 100))%")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(isHighConfidence ? Constants.Colors.hotRed.opacity(0.08) : Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(
                            isHighConfidence ? Constants.Colors.hotRed.opacity(0.3) : Constants.Colors.surfaceBorder,
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - What You Broadcast

    private var broadcastSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What You Broadcast")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            ForEach(appState.privacyShield.ownBroadcasts) { broadcast in
                broadcastRow(broadcast)
            }
        }
    }

    private func broadcastRow(_ broadcast: OwnBroadcast) -> some View {
        let isExpanded = expandedBroadcastID == broadcast.id
        let riskColor = colorForThreatLevel(broadcast.riskLevel)

        return Button {
            withAnimation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping)) {
                expandedBroadcastID = isExpanded ? nil : broadcast.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: broadcast.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(riskColor)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(riskColor.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(broadcast.protocolName)
                                .font(Constants.Typography.cardTitle)
                                .foregroundStyle(Constants.Colors.textPrimary)

                            Text(broadcast.riskLevel.label)
                                .font(Constants.Typography.badge)
                                .foregroundStyle(riskColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(riskColor.opacity(0.15))
                                )
                        }

                        Text(broadcast.description)
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textSecondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Constants.Colors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }

                if isExpanded {
                    Divider()
                        .background(Constants.Colors.surfaceBorder)

                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Constants.Colors.amber)
                        Text(broadcast.recommendation)
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(Constants.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                            .stroke(Constants.Colors.surfaceBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func scoreColor(for score: Int) -> Color {
        if score >= 80 { return Constants.Colors.electricGreen }
        if score >= 50 { return Constants.Colors.amber }
        return Constants.Colors.hotRed
    }

    private func scoreDescription(for score: Int) -> String {
        if score >= 80 { return "Your environment looks safe" }
        if score >= 50 { return "Some potential threats detected nearby" }
        return "Multiple tracking risks detected"
    }

    private func colorForThreatLevel(_ level: BLEDevice.ThreatLevel) -> Color {
        switch level {
        case .none: Constants.Colors.electricGreen
        case .low: Constants.Colors.electricGreen
        case .medium: Constants.Colors.amber
        case .high: Constants.Colors.hotRed
        }
    }

    private func iconForAlertType(_ type: TrackingAlert.AlertType) -> String {
        switch type {
        case .followingDevice: "figure.walk"
        case .hiddenCamera: "video.fill"
        case .stationaryTracker: "mappin.and.ellipse"
        case .surveillanceInfrastructure: "building.2.fill"
        }
    }

    private func estimateDistance(rssi: Int) -> String {
        // Rough RSSI-to-distance estimation
        let distance: Double
        if rssi >= -40 {
            distance = 0.5
        } else if rssi >= -55 {
            distance = 1.0
        } else if rssi >= -65 {
            distance = 3.0
        } else if rssi >= -75 {
            distance = 5.0
        } else if rssi >= -85 {
            distance = 10.0
        } else {
            distance = 15.0
        }

        if distance < 1.0 {
            return "<1m"
        } else {
            return "~\(Int(distance))m"
        }
    }
}

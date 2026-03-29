import SwiftUI

struct ProtectTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Layout.spacing) {
                roomScannerCard
                privacyShieldCard
                soundAlertsCard
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.top, Constants.Layout.horizontalPadding)
            .padding(.bottom, Constants.Layout.horizontalPadding)
        }
    }

    // MARK: - Room Scanner Card

    private var roomScannerCard: some View {
        let scanner = appState.bleScanner
        let deviceCount = scanner.discoveredDevices.count
        let threatCount = scanner.threatDevices.count

        return NavigationLink {
            RoomScannerView()
        } label: {
            protectCard(
                icon: "shield.lefthalf.filled",
                title: "Room Scanner",
                status: scanner.isScanning
                    ? "\(deviceCount) device\(deviceCount == 1 ? "" : "s") detected, \(threatCount) threat\(threatCount == 1 ? "" : "s")"
                    : "Tap to start scanning",
                statusColor: scanner.isScanning
                    ? (threatCount > 0 ? Constants.Colors.amber : Constants.Colors.electricGreen)
                    : Constants.Colors.textSecondary,
                badgeCount: threatCount,
                badgeColor: threatCount >= 3 ? Constants.Colors.hotRed : Constants.Colors.amber
            )
        }
        .accessibilityLabel("Room Scanner: \(scanner.isScanning ? "\(deviceCount) devices, \(threatCount) threats" : "not scanning")")
    }

    // MARK: - Privacy Shield Card

    private var privacyShieldCard: some View {
        let shield = appState.privacyShield
        let score = shield.privacyScore

        return NavigationLink {
            PrivacyShieldView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(scoreColor(score).opacity(0.12))
                        .frame(width: 50, height: 50)

                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(scoreColor(score))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Shield")
                        .font(Constants.Typography.cardTitle)
                        .foregroundStyle(Constants.Colors.textPrimary)

                    HStack(spacing: 8) {
                        // Mini circular score gauge
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 3)
                                .frame(width: 24, height: 24)

                            Circle()
                                .trim(from: 0, to: CGFloat(score) / 100.0)
                                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(-90))

                            Text("\(score)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(scoreColor(score))
                        }

                        Text(scoreLabel(score))
                            .font(Constants.Typography.caption)
                            .foregroundStyle(scoreColor(score).opacity(0.8))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(Constants.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                            .fill(.ultraThinMaterial.opacity(0.3))
                            .environment(\.colorScheme, .dark)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Sound Alerts Card

    private var soundAlertsCard: some View {
        let service = appState.soundAlertService
        let alertCount = service.recentAlerts.count + service.meshAlerts.count

        return NavigationLink {
            SoundAlertsView()
        } label: {
            protectCard(
                icon: "waveform.badge.exclamationmark",
                title: "Sound Alerts",
                status: service.isListening
                    ? (alertCount > 0 ? "\(alertCount) alert\(alertCount == 1 ? "" : "s") detected" : "Listening...")
                    : "Activate Emergency Mode",
                statusColor: service.isListening
                    ? (alertCount > 0 ? Constants.Colors.amber : Constants.Colors.electricGreen)
                    : Constants.Colors.textSecondary,
                badgeCount: alertCount,
                badgeColor: Constants.Colors.amber
            )
        }
        .accessibilityLabel("Sound Alerts: \(service.isListening ? "listening" : "inactive")\(alertCount > 0 ? ", \(alertCount) alerts" : "")")
    }

    // MARK: - Reusable Card

    private func protectCard(
        icon: String,
        title: String,
        status: String,
        statusColor: Color,
        badgeCount: Int,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Constants.Colors.amber.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Constants.Colors.amber)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Constants.Typography.cardTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text(status)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(badgeColor)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .environment(\.colorScheme, .dark)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return Constants.Colors.electricGreen }
        if score >= 50 { return Constants.Colors.amber }
        return Constants.Colors.hotRed
    }

    private func scoreLabel(_ score: Int) -> String {
        if score >= 80 { return "Good" }
        if score >= 50 { return "Fair" }
        return "At Risk"
    }
}

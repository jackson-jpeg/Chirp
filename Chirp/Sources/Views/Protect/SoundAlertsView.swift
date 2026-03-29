import CoreLocation
import SwiftUI

/// Full alert timeline showing local sound detections and mesh alerts from other nodes.
struct SoundAlertsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let service = appState.soundAlertService

        ScrollView {
            VStack(spacing: Constants.Layout.spacing) {
                // MARK: - Status Section
                statusSection

                // MARK: - Local Detections
                if !service.recentAlerts.isEmpty {
                    localAlertsSection
                }

                // MARK: - Mesh Alerts
                if !service.meshAlerts.isEmpty {
                    meshAlertsSection
                }

                // MARK: - Empty State
                if service.recentAlerts.isEmpty && service.meshAlerts.isEmpty && service.isListening {
                    emptyState
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.top, 12)
        }
        .background(Constants.Colors.backgroundPrimary)
        .navigationTitle("Sound Alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !service.recentAlerts.isEmpty || !service.meshAlerts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        service.clearAlerts()
                    }
                    .foregroundStyle(Constants.Colors.amber)
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        let service = appState.soundAlertService

        return HStack(spacing: 12) {
            if service.isListening {
                Circle()
                    .fill(Constants.Colors.electricGreen)
                    .frame(width: 10, height: 10)
                    .shadow(color: Constants.Colors.electricGreen.opacity(0.6), radius: 4)

                Text("Listening for emergency sounds...")
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)
            } else {
                Circle()
                    .fill(Constants.Colors.textTertiary)
                    .frame(width: 10, height: 10)

                NavigationLink {
                    EmergencySOSView()
                } label: {
                    HStack(spacing: 4) {
                        Text("Activate Emergency Mode to enable")
                            .font(Constants.Typography.body)
                            .foregroundStyle(Constants.Colors.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                }
            }

            Spacer()
        }
        .padding(Constants.Layout.cardPadding)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius))
    }

    // MARK: - Local Alerts

    private var localAlertsSection: some View {
        let service = appState.soundAlertService

        return VStack(alignment: .leading, spacing: 12) {
            Text("Local Detections")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            ForEach(service.recentAlerts) { alert in
                alertCard(alert: alert, isMesh: false)
            }
        }
    }

    // MARK: - Mesh Alerts

    private var meshAlertsSection: some View {
        let service = appState.soundAlertService

        return VStack(alignment: .leading, spacing: 12) {
            Text("Mesh Alerts")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            ForEach(service.meshAlerts) { alert in
                alertCard(alert: alert, isMesh: true)
            }
        }
    }

    // MARK: - Alert Card

    private func alertCard(alert: SoundAlert, isMesh: Bool) -> some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: alert.soundClass.icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(alertColor(for: alert.soundClass))
                .frame(width: 40, height: 40)
                .background(alertColor(for: alert.soundClass).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(alert.soundClass.displayName)
                        .font(Constants.Typography.cardTitle)
                        .foregroundStyle(Constants.Colors.textPrimary)

                    Spacer()

                    Text(timeAgo(alert.timestamp))
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }

                // Confidence bar
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Constants.Colors.surfaceGlass)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(alertColor(for: alert.soundClass))
                                .frame(width: geo.size.width * alert.confidence, height: 4)
                        }
                    }
                    .frame(height: 4)

                    Text("\(Int(alert.confidence * 100))%")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }

                // Sender + location info
                HStack(spacing: 8) {
                    if isMesh {
                        Label(alert.senderName, systemImage: "antenna.radiowaves.left.and.right")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.amber)
                    }

                    if let distance = distanceToAlert(alert) {
                        Label(formatDistance(distance), systemImage: "location.fill")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }

                    if let lat = alert.latitude, let lon = alert.longitude {
                        Text(formatCoordinate(lat: lat, lon: lon))
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(Constants.Colors.surfaceGlass)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.soundClass.displayName) detected, \(Int(alert.confidence * 100))% confidence\(isMesh ? ", from \(alert.senderName)" : "")")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Constants.Colors.textTertiary)

            Text("No sounds detected yet")
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textSecondary)

            Text("The classifier is analyzing ambient audio for gunshots, screams, sirens, and other emergency sounds.")
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func alertColor(for soundClass: SoundAlert.SoundClass) -> Color {
        switch soundClass {
        case .gunshot, .explosion:
            return Constants.Colors.emergencyRed
        case .scream:
            return Constants.Colors.hotRed
        case .fireAlarm, .smokeDetector:
            return Constants.Colors.amber
        case .glassBreaking:
            return Constants.Colors.amberLight
        case .siren:
            return Constants.Colors.amberDark
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    private func distanceToAlert(_ alert: SoundAlert) -> CLLocationDistance? {
        guard let lat = alert.latitude,
              let lon = alert.longitude,
              let current = appState.locationService.currentLocation else { return nil }
        let alertLocation = CLLocation(latitude: lat, longitude: lon)
        return current.distance(from: alertLocation)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }

    private func formatCoordinate(lat: Double, lon: Double) -> String {
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f%@ %.4f%@", abs(lat), latDir, abs(lon), lonDir)
    }
}

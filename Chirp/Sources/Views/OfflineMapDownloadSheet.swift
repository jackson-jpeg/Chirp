import CoreLocation
import SwiftUI

struct OfflineMapDownloadSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var radiusKm: Double = 10.0

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen

    private var offlineMapManager: OfflineMapManager {
        appState.offlineMapManager
    }

    private var currentCenter: CLLocationCoordinate2D? {
        appState.locationService.currentLocation?.coordinate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Map preview
                    mapPreview

                    // Download controls
                    downloadControls

                    // Downloaded regions list
                    if !offlineMapManager.downloadedRegions.isEmpty {
                        downloadedRegionsList
                    }
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.bottom, 24)
            }
            .background(
                LinearGradient(
                    colors: [Constants.Colors.backgroundPrimary, Constants.Colors.backgroundSecondary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Offline Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(amber)
                }
            }
        }
    }

    // MARK: - Map Preview

    private var mapPreview: some View {
        VStack(spacing: 12) {
            GeoMapView(
                userLocation: currentCenter,
                peers: [],
                isInteractive: false
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Layout.cornerRadius)
                    .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
            )

            Text("Tiles will be downloaded for the area around your current location.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Download Controls

    private var downloadControls: some View {
        VStack(spacing: 16) {
            // Radius slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Radius")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Constants.Colors.textPrimary)
                    Spacer()
                    Text("\(Int(radiusKm)) km")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(amber)
                }

                Slider(value: $radiusKm, in: 1...50, step: 1)
                    .tint(amber)
            }

            // Size estimate
            let estimatedMB = OfflineMapManager.estimateSizeMB(radiusKm: radiusKm)
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(amber.opacity(0.7))
                Text("Estimated size:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                Spacer()
                Text(formatSize(mb: estimatedMB))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Constants.Colors.textPrimary)
            }

            // Progress bar (when downloading)
            if offlineMapManager.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: offlineMapManager.downloadProgress)
                        .tint(amber)

                    Text("\(Int(offlineMapManager.downloadProgress * 100))% downloaded")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Constants.Colors.textSecondary)
                }
            }

            // Download button
            Button(action: startDownload) {
                HStack(spacing: 8) {
                    if offlineMapManager.isDownloading {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(offlineMapManager.isDownloading ? "Downloading..." : "Download Visible Area")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(offlineMapManager.isDownloading ? amber.opacity(0.5) : amber)
                )
            }
            .disabled(offlineMapManager.isDownloading || currentCenter == nil)
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(Constants.Colors.surfaceBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Downloaded Regions List

    private var downloadedRegionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DOWNLOADED REGIONS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Constants.Colors.textTertiary)
                .tracking(1.0)

            ForEach(offlineMapManager.downloadedRegions) { region in
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(green)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Constants.Colors.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(formatBytes(region.sizeBytes))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Constants.Colors.textTertiary)

                            Text(region.date, style: .date)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Constants.Colors.textTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        offlineMapManager.deleteRegion(id: region.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Constants.Colors.hotRed.opacity(0.8))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Constants.Colors.surfaceGlass)
                )
            }
        }
    }

    // MARK: - Actions

    private func startDownload() {
        guard let center = currentCenter else { return }
        offlineMapManager.downloadRegion(center: center, radiusKm: radiusKm)
    }

    // MARK: - Formatting

    private func formatSize(mb: Double) -> String {
        if mb < 1 {
            return String(format: "%.0f KB", mb * 1024)
        }
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 1 {
            return String(format: "%.0f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", mb)
    }
}

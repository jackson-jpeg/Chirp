import SwiftUI

struct MeshCloudView: View {
    @Environment(AppState.self) private var appState

    // MARK: - Color shortcuts

    private let amber = Constants.Colors.amber
    private let green = Constants.Colors.electricGreen
    private let red = Constants.Colors.hotRed

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                storageStatusCard
                donationSection
                localBackupsSection
                storedShardsSection
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Mesh Cloud")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Storage Status Card

    private var storageStatusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(amber)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mesh Cloud")
                        .font(Constants.Typography.cardTitle)
                        .foregroundStyle(Constants.Colors.textPrimary)

                    Text("Distributed encrypted backup")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)
                }

                Spacer()
            }

            // Storage usage bar
            VStack(alignment: .leading, spacing: 8) {
                storageBar

                HStack {
                    Text(formatBytes(appState.meshCloudService.storageDonated))
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(green)

                    Text("of \(appState.meshCloudService.storageQuotaMB) MB donated")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()
                }
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private var storageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))

                let quotaBytes = appState.meshCloudService.storageQuotaMB * 1024 * 1024
                let fraction = quotaBytes > 0
                    ? min(1.0, CGFloat(appState.meshCloudService.storageDonated) / CGFloat(quotaBytes))
                    : 0

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [green, amber],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 8)
    }

    // MARK: - Donation Section

    private var donationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "heart.fill", title: "Storage Donation")

            VStack(spacing: 1) {
                // Toggle
                glassRow {
                    Toggle(isOn: Binding(
                        get: { appState.meshCloudService.isDonating },
                        set: { appState.meshCloudService.isDonating = $0 }
                    )) {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(amber)
                                .frame(width: 24)
                            Text("Donate Storage")
                                .foregroundStyle(.white)
                        }
                    }
                    .tint(amber)
                    .accessibilityLabel("Donate storage to mesh network")
                    .accessibilityIdentifier(AccessibilityID.storageDonationToggle)
                }

                // Size picker
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive.fill")
                            .foregroundStyle(amber)
                            .frame(width: 24)
                        Text("Quota")
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("Quota", selection: Binding(
                            get: { appState.meshCloudService.storageQuotaMB },
                            set: { appState.meshCloudService.storageQuotaMB = $0 }
                        )) {
                            Text("10 MB").tag(10)
                            Text("50 MB").tag(50)
                            Text("100 MB").tag(100)
                            Text("500 MB").tag(500)
                        }
                        .pickerStyle(.menu)
                        .tint(amber)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Donating storage helps other mesh peers back up their data securely. All stored data is encrypted — you cannot read it.")
                .font(.system(.caption2))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 4)
                .padding(.top, 8)
        }
    }

    // MARK: - Local Backups

    private var localBackupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "arrow.clockwise.icloud.fill", title: "Your Backups")

            if appState.meshCloudService.localBackups.isEmpty {
                glassRow {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text("No backups yet")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 1) {
                    ForEach(appState.meshCloudService.localBackups) { backup in
                        glassRow {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.zipper")
                                    .foregroundStyle(amber)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.fileName)
                                        .font(.system(.body, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text("\(formatBytes(Int(backup.totalSize))) -- \(backup.threshold)-of-\(backup.totalShares) shards")
                                        .font(Constants.Typography.monoSmall)
                                        .foregroundStyle(Constants.Colors.textSecondary)
                                }

                                Spacer()

                                if appState.meshCloudService.isRetrieving {
                                    ProgressView()
                                        .tint(amber)
                                } else {
                                    Button {
                                        Task {
                                            await appState.meshCloudService.requestRetrieval(backupID: backup.id)
                                        }
                                    } label: {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(green)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Retrieval progress
                    if appState.meshCloudService.isRetrieving {
                        glassRow {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Retrieving from mesh...")
                                        .font(Constants.Typography.caption)
                                        .foregroundStyle(amber)
                                    Spacer()
                                    Text("\(Int(appState.meshCloudService.retrievalProgress * 100))%")
                                        .font(Constants.Typography.mono)
                                        .foregroundStyle(amber)
                                }

                                ProgressView(value: appState.meshCloudService.retrievalProgress)
                                    .tint(amber)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Stored Shards

    private var storedShardsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: "square.stack.3d.up.fill", title: "Stored for Others")

            glassRow {
                HStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .foregroundStyle(green)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Encrypted Shards")
                            .foregroundStyle(.white)
                        Text("\(formatBytes(appState.meshCloudService.storageDonated)) stored")
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }

                    Spacer()

                    statusBadge(
                        text: appState.meshCloudService.isDonating ? "Active" : "Paused",
                        color: appState.meshCloudService.isDonating ? green : .secondary
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(amber)

            Text(title.uppercased())
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
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

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

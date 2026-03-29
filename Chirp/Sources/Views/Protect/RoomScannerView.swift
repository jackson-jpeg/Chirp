import SwiftUI

/// Full-featured BLE room scanner UI for detecting nearby devices and assessing threats.
struct RoomScannerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var scanner = appState.bleScanner

        ScrollView {
            VStack(spacing: Constants.Layout.spacing) {
                // MARK: - Scan Toggle Button
                scanButton

                // MARK: - Status
                statusBar

                // MARK: - Threat Summary
                if !scanner.discoveredDevices.isEmpty {
                    threatSummary
                }

                // MARK: - Device List
                if !scanner.discoveredDevices.isEmpty {
                    deviceList
                }

                // MARK: - Share with Mesh
                if !scanner.discoveredDevices.isEmpty {
                    shareButton
                }

                // MARK: - Mesh Reports
                if !scanner.meshReports.isEmpty {
                    meshReportsSection
                }

                // Foreground warning
                if scanner.isScanning {
                    Text("Scanner active while app is open")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.textTertiary)
                        .padding(.top, 4)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, Constants.Layout.horizontalPadding)
            .padding(.top, 12)
        }
        .background(Constants.Colors.backgroundPrimary)
        .navigationTitle("Room Scanner")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Scan Button

    private var scanButton: some View {
        let scanner = appState.bleScanner

        return Button {
            if scanner.isScanning {
                scanner.stopScanning()
            } else {
                scanner.startScanning()
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: scanner.isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40, weight: .medium))
                    .symbolEffect(.variableColor.iterative, isActive: scanner.isScanning)

                Text(scanner.isScanning ? "Scanning" : "Scan")
                    .font(Constants.Typography.cardTitle)
            }
            .foregroundStyle(scanner.isScanning ? .black : Constants.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(
                        scanner.isScanning
                            ? AnyShapeStyle(Constants.Colors.amber.gradient)
                            : AnyShapeStyle(Constants.Colors.surfaceGlass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                            .stroke(
                                scanner.isScanning
                                    ? Constants.Colors.amberLight.opacity(0.5)
                                    : Constants.Colors.surfaceBorder,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(scanner.bluetoothState != .poweredOn && !scanner.isScanning)
        .opacity(scanner.bluetoothState == .poweredOn || scanner.isScanning ? 1.0 : 0.5)
        .animation(.spring(response: Constants.Animations.springResponse, dampingFraction: Constants.Animations.springDamping), value: scanner.isScanning)
        .accessibilityLabel(scanner.isScanning ? "Stop scanning for devices" : "Start scanning for nearby devices")
        .accessibilityIdentifier(AccessibilityID.scanButton)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let scanner = appState.bleScanner
        let count = scanner.discoveredDevices.count

        return HStack(spacing: 8) {
            if scanner.isScanning {
                ProgressView()
                    .tint(Constants.Colors.amber)
                    .scaleEffect(0.8)
            }

            Text(statusText(scanner: scanner, count: count))
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    // MARK: - Threat Summary

    private var threatSummary: some View {
        let scanner = appState.bleScanner
        let devices = scanner.discoveredDevices
        let safe = devices.filter { $0.threatLevel <= .low }.count
        let unknown = devices.filter { $0.threatLevel == .medium }.count
        let suspicious = devices.filter { $0.threatLevel == .high }.count

        return HStack(spacing: 0) {
            threatPill(count: safe, label: "Safe", color: Constants.Colors.electricGreen)
            Spacer()
            threatPill(count: unknown, label: "Unknown", color: Constants.Colors.amber)
            Spacer()
            threatPill(count: suspicious, label: "Suspicious", color: Constants.Colors.hotRed)
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

    private func threatPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Device List

    private var deviceList: some View {
        let scanner = appState.bleScanner

        let suspicious = scanner.discoveredDevices.filter { $0.threatLevel == .high }
        let unknown = scanner.discoveredDevices.filter { $0.threatLevel == .medium }
        let safe = scanner.discoveredDevices.filter { $0.threatLevel <= .low }

        return VStack(spacing: 0) {
            if !suspicious.isEmpty {
                deviceSection(title: "Suspicious", devices: suspicious, color: Constants.Colors.hotRed)
            }
            if !unknown.isEmpty {
                deviceSection(title: "Unknown", devices: unknown, color: Constants.Colors.amber)
            }
            if !safe.isEmpty {
                deviceSection(title: "Safe", devices: safe, color: Constants.Colors.electricGreen)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(Constants.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                        .stroke(Constants.Colors.surfaceBorder, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius))
    }

    private func deviceSection(title: String, devices: [BLEDevice], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("\(devices.count)")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
            .padding(.horizontal, Constants.Layout.cardPadding)
            .padding(.vertical, 10)
            .background(color.opacity(0.05))

            // Device rows
            ForEach(devices) { device in
                DetectedDeviceRow(device: device)

                if device.id != devices.last?.id {
                    Divider()
                        .background(Constants.Colors.surfaceBorder)
                        .padding(.leading, Constants.Layout.cardPadding + 50)
                }
            }
        }
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            let location = appState.locationService
            appState.bleScanner.shareScanWithMesh(
                senderID: appState.localPeerID,
                senderName: appState.callsign,
                latitude: location.currentLocation?.coordinate.latitude,
                longitude: location.currentLocation?.coordinate.longitude
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share with Mesh")
                    .font(Constants.Typography.body)
            }
            .foregroundStyle(Constants.Colors.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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

    // MARK: - Mesh Reports

    private var meshReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mesh Reports")
                .font(Constants.Typography.sectionTitle)
                .foregroundStyle(Constants.Colors.textPrimary)

            ForEach(appState.bleScanner.meshReports, id: \.senderID) { report in
                meshReportCard(report)
            }
        }
    }

    private func statusText(scanner: BLEScanner, count: Int) -> String {
        switch scanner.bluetoothState {
        case .poweredOff: return "Turn on Bluetooth to scan"
        case .unauthorized: return "Bluetooth permission required — check Settings"
        case .unsupported: return "Bluetooth not available on this device"
        case .unknown: return "Checking Bluetooth..."
        case .poweredOn:
            if scanner.isScanning {
                return "Scanning... \(count) device\(count == 1 ? "" : "s") found"
            }
            return "Tap to start scanning"
        }
    }

    private func meshReportCard(_ report: MeshScanReport) -> some View {
        let threats = report.devices.filter { $0.threatLevel >= .medium }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.wave.2")
                    .foregroundStyle(Constants.Colors.amber)
                Text(report.senderName)
                    .font(Constants.Typography.cardTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)
                Spacer()
                Text(report.timestamp, style: .relative)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            HStack(spacing: 12) {
                Label("\(report.devices.count) devices", systemImage: "antenna.radiowaves.left.and.right")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)

                if !threats.isEmpty {
                    Label("\(threats.count) threat\(threats.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                        .font(Constants.Typography.caption)
                        .foregroundStyle(Constants.Colors.hotRed)
                }
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
}

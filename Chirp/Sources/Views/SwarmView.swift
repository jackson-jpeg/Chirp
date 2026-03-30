import SwiftUI
import OSLog

/// Compute donation and distributed job management view for the Swarm feature.
///
/// Allows users to donate background and foreground compute cycles to the mesh,
/// monitor device health, track active/completed jobs, and see capable nodes.
struct SwarmView: View {
    @Environment(AppState.self) private var appState

    private let logger = Logger(subsystem: Constants.subsystem, category: "SwarmView")

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Constants.Layout.spacing) {
                    headerSection
                    donationToggles
                    deviceHealthCard
                    activeJobsSection
                    completedJobsSection
                    knownNodesSection
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Swarm")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [.black, Color(red: 0.02, green: 0.02, blue: 0.12)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swarm Compute")
                    .font(Constants.Typography.heroTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("DISTRIBUTED INFERENCE")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
            }

            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(
                    appState.swarmService.donateForegroundCompute || appState.swarmService.donateBackgroundCompute
                        ? Constants.Colors.electricGreen
                        : Constants.Colors.textTertiary
                )
                .symbolEffect(.pulse, isActive: !appState.swarmService.localWorkQueue.isEmpty)
        }
    }

    // MARK: - Donation Toggles

    private var donationToggles: some View {
        VStack(spacing: 1) {
            // Background compute
            toggleRow(
                icon: "moon.fill",
                title: "Donate Background Compute",
                subtitle: "Use idle CPU when app is backgrounded. Requires external power.",
                isOn: Binding(
                    get: { appState.swarmService.donateBackgroundCompute },
                    set: { appState.swarmService.donateBackgroundCompute = $0 }
                ),
                tint: Constants.Colors.amber
            )

            // Foreground compute
            toggleRow(
                icon: "bolt.fill",
                title: "Donate Foreground Compute",
                subtitle: "Process work units while the app is active. May impact battery.",
                isOn: Binding(
                    get: { appState.swarmService.donateForegroundCompute },
                    set: { appState.swarmService.donateForegroundCompute = $0 }
                ),
                tint: Constants.Colors.electricGreen
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(isOn.wrappedValue ? tint : Constants.Colors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text(subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
    }

    // MARK: - Device Health

    private var deviceHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Constants.Colors.amber)

                Text("DEVICE HEALTH")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            HStack(spacing: 16) {
                // Battery
                healthIndicator(
                    icon: batteryIcon,
                    label: "Battery",
                    value: "\(batteryPercentage)%",
                    color: batteryColor
                )

                // Thermal state
                healthIndicator(
                    icon: thermalIcon,
                    label: "Thermal",
                    value: thermalLabel,
                    color: thermalColor
                )

                // Charging
                healthIndicator(
                    icon: isCharging ? "bolt.fill" : "bolt.slash.fill",
                    label: "Power",
                    value: isCharging ? "Charging" : "Battery",
                    color: isCharging ? Constants.Colors.electricGreen : Constants.Colors.textSecondary
                )
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private func healthIndicator(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            Text(value)
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textPrimary)

            Text(label)
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Active Jobs

    private var activeJobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "gearshape.2.fill", title: "Active Jobs", count: appState.swarmService.activeJobs.count)

            if appState.swarmService.activeJobs.isEmpty {
                emptyState(icon: "tray", message: "No active compute jobs")
            } else {
                ForEach(Array(appState.swarmService.activeJobs.values), id: \.id) { job in
                    jobCard(job)
                }
            }
        }
    }

    private func jobCard(_ job: SwarmJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.description)
                        .font(Constants.Typography.cardTitle)
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .lineLimit(1)

                    Text(job.modelID)
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }

                Spacer()

                priorityBadge(job.priority)
            }

            // Progress bar
            let completedCount = appState.swarmService.completedUnits[job.id]?.count ?? 0
            let totalUnits = Int(job.totalUnits)
            let progress = totalUnits > 0 ? Double(completedCount) / Double(totalUnits) : 0

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Constants.Colors.amber, Constants.Colors.electricGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(completedCount)/\(totalUnits) units")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textSecondary)

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.amber)
                }
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius, style: .continuous))
    }

    private func priorityBadge(_ priority: SwarmJob.SwarmPriority) -> some View {
        let (text, color): (String, Color) = switch priority {
        case .background: ("BG", Constants.Colors.textSecondary)
        case .foreground: ("FG", Constants.Colors.amber)
        }

        return Text(text)
            .font(Constants.Typography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }

    // MARK: - Completed Jobs

    private var completedJobsSection: some View {
        let completedJobs = appState.swarmService.completedUnits.filter { jobID, units in
            guard let job = appState.swarmService.activeJobs[jobID] else { return false }
            return units.count >= Int(job.totalUnits)
        }

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "checkmark.circle.fill", title: "Completed", count: completedJobs.count)

            if completedJobs.isEmpty {
                emptyState(icon: "tray.fill", message: "No completed jobs yet")
            } else {
                ForEach(Array(completedJobs), id: \.key) { jobID, results in
                    if let job = appState.swarmService.activeJobs[jobID] {
                        completedJobRow(job: job, results: results)
                    }
                }
            }
        }
    }

    private func completedJobRow(job: SwarmJob, results: [UInt32: SwarmWorkResult]) -> some View {
        let totalTime = results.values.reduce(0) { $0 + $1.computeTimeMs }
        let avgTime = results.isEmpty ? 0 : totalTime / UInt64(results.count)

        return HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Constants.Colors.electricGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.description)
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                Text("\(results.count) units | avg \(avgTime)ms/unit")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            Text("\(totalTime)ms")
                .font(Constants.Typography.mono)
                .foregroundStyle(Constants.Colors.amber)
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius, style: .continuous))
    }

    // MARK: - Known Nodes

    private var knownNodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "desktopcomputer", title: "Capable Nodes", count: appState.swarmService.knownNodes.count)

            if appState.swarmService.knownNodes.isEmpty {
                emptyState(icon: "network.slash", message: "No compute-capable peers discovered")
            } else {
                ForEach(Array(appState.swarmService.knownNodes), id: \.key) { peerID, capability in
                    nodeRow(peerID: peerID, capability: capability)
                }
            }
        }
    }

    private func nodeRow(peerID: String, capability: SwarmNodeCapability) -> some View {
        HStack(spacing: 12) {
            // Thermal/battery indicator
            Circle()
                .fill(nodeHealthColor(capability))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(peerID.prefix(12) + "...")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(Int(capability.batteryLevel * 100))%", systemImage: "battery.50percent")
                        .font(Constants.Typography.monoSmall)

                    if capability.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Constants.Colors.electricGreen)
                    }

                    Text("\(capability.availableMemoryMB)MB")
                        .font(Constants.Typography.monoSmall)
                }
                .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if capability.acceptsBackground {
                        modeBadge("BG", color: Constants.Colors.textSecondary)
                    }
                    if capability.acceptsForeground {
                        modeBadge("FG", color: Constants.Colors.amber)
                    }
                }

                Text("\(capability.availableModels.count) model\(capability.availableModels.count == 1 ? "" : "s")")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius, style: .continuous))
    }

    private func modeBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Shared Components

    private var glassCard: some View {
        ZStack {
            Color.white.opacity(0.06)
            LinearGradient(
                colors: [.white.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private func sectionHeader(icon: String, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Constants.Colors.amber)

            Text(title.uppercased())
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)

            if count > 0 {
                Text("\(count)")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.amber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Constants.Colors.glassAmber))
            }

            Spacer()
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Constants.Colors.textTertiary)
                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }

    // MARK: - Device Info Helpers

    private var batteryPercentage: Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
    }

    private var batteryColor: Color {
        let level = UIDevice.current.batteryLevel
        if level > 0.5 { return Constants.Colors.electricGreen }
        if level > 0.2 { return Constants.Colors.amber }
        return Constants.Colors.hotRed
    }

    private var batteryIcon: String {
        let level = UIDevice.current.batteryLevel
        if isCharging { return "battery.100percent.bolt" }
        if level > 0.75 { return "battery.100percent" }
        if level > 0.5 { return "battery.75percent" }
        if level > 0.25 { return "battery.50percent" }
        return "battery.25percent"
    }

    private var isCharging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private var thermalColor: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: Constants.Colors.electricGreen
        case .fair: Constants.Colors.amber
        case .serious: Constants.Colors.hotRed
        case .critical: Constants.Colors.hotRed
        @unknown default: Constants.Colors.textTertiary
        }
    }

    private var thermalIcon: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "thermometer.sun.fill"
        @unknown default: "thermometer"
        }
    }

    private func nodeHealthColor(_ capability: SwarmNodeCapability) -> Color {
        if capability.thermalState >= 3 || capability.batteryLevel < 0.1 {
            return Constants.Colors.hotRed
        }
        if capability.thermalState >= 2 || capability.batteryLevel < 0.3 {
            return Constants.Colors.amber
        }
        return Constants.Colors.electricGreen
    }
}

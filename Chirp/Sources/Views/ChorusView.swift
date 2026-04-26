import SwiftUI
import OSLog

/// Pipeline status visualization for distributed model inference (Chorus).
///
/// Displays a pipeline diagram showing nodes and their assigned stages,
/// data flow animations, throughput metrics, active/completed inference counts,
/// and pipeline configuration UI.
struct ChorusView: View {
    @Environment(AppState.self) private var appState

    @State private var showConfigSheet = false
    @State private var selectedModelID = "llama-7b"
    @State private var isNegotiating = false
    @State private var animationPhase: Double = 0

    private let logger = Logger(subsystem: Constants.subsystem, category: "ChorusView")

    // Available models for pipeline
    private let availableModels = [
        ("llama-7b", "LLaMA 7B"),
        ("llama-13b", "LLaMA 13B"),
        ("whisper-medium", "Whisper Medium"),
        ("stable-diffusion", "Stable Diffusion"),
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Constants.Layout.spacing) {
                    headerSection
                    pipelineStatusCard
                    activePipelinesSection
                    throughputCard
                    peerOffersSection
                    startPipelineButton
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Chorus")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConfigSheet) {
            pipelineConfigSheet
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [.black, Constants.Colors.backgroundDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chorus Pipeline")
                    .font(Constants.Typography.heroTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("DISTRIBUTED INFERENCE")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
            }

            Spacer()

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(
                    appState.chorusService.activePipelines.isEmpty
                        ? Constants.Colors.textTertiary
                        : Constants.Colors.electricGreen
                )
                .symbolEffect(.pulse, isActive: !appState.chorusService.activePipelines.isEmpty)
        }
    }

    // MARK: - Pipeline Status Card

    private var pipelineStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(pipelineStatusColor)
                    .frame(width: 10, height: 10)

                Text(pipelineStatusText)
                    .font(Constants.Typography.monoStatus)
                    .foregroundStyle(pipelineStatusColor)

                Spacer()

                Text("\(appState.chorusService.activePipelines.count) active")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            // Pipeline diagram
            if let pipeline = appState.chorusService.activePipelines.values.first {
                pipelineDiagram(pipeline)
            } else {
                emptyPipelineDiagram
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private func pipelineDiagram(_ config: ChorusPipelineConfig) -> some View {
        VStack(spacing: 12) {
            // Model label
            HStack {
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.Colors.amber)
                Text(config.modelID)
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
                Spacer()
                Text("\(config.totalLayers) layers")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            // Stage nodes with flow arrows
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(config.stages.enumerated()), id: \.offset) { index, stage in
                        if index > 0 {
                            // Flow arrow with animation
                            flowArrow
                        }
                        stageNode(stage: stage, index: index, totalStages: config.stages.count)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyPipelineDiagram: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Constants.Colors.surfaceGlass)
                            .frame(width: 70, height: 50)
                            .overlay(
                                Image(systemName: "questionmark")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(Constants.Colors.textTertiary)
                            )

                        Text("Stage \(i)")
                            .font(Constants.Typography.badge)
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }

                    if i < 2 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Constants.Colors.textTertiary)
                            .padding(.bottom, 16)
                    }
                }
            }

            Text("No active pipeline. Configure one below.")
                .font(Constants.Typography.caption)
                .foregroundStyle(Constants.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func stageNode(stage: ChorusPipelineConfig.PipelineStage, index: Int, totalStages: Int) -> some View {
        let layerRange = "\(stage.startLayer)-\(stage.endLayer)"
        let isLocal = stage.peerID == appState.localPeerID

        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isLocal ? Constants.Colors.glassAmber : Constants.Colors.surfaceGlass)
                .frame(width: 80, height: 56)
                .overlay(
                    VStack(spacing: 2) {
                        Image(systemName: isLocal ? "iphone" : "desktopcomputer")
                            .font(.system(size: 14))
                            .foregroundStyle(isLocal ? Constants.Colors.amber : Constants.Colors.textSecondary)

                        Text("L\(layerRange)")
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textPrimary)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isLocal ? Constants.Colors.glassAmberBorder : Constants.Colors.surfaceBorder,
                            lineWidth: 1
                        )
                )

            Text(stage.peerID.prefix(6) + "...")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Constants.Colors.textTertiary)
                .lineLimit(1)

            if isLocal {
                Text("YOU")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.amber)
            }
        }
    }

    private var flowArrow: some View {
        ZStack {
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Constants.Colors.amber.opacity(0.6))

            // Animated activation dot
            Circle()
                .fill(Constants.Colors.electricGreen)
                .frame(width: 6, height: 6)
                .offset(x: -10 + 20 * animationPhase)
                .opacity(0.8)
        }
        .frame(width: 28)
        .padding(.bottom, 16)
    }

    // MARK: - Active Pipelines

    private var activePipelinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "point.3.connected.trianglepath.dotted", title: "Active Pipelines")

            if appState.chorusService.activePipelines.isEmpty {
                emptyState(icon: "point.3.connected.trianglepath.dotted", message: "No pipelines running")
            } else {
                ForEach(Array(appState.chorusService.activePipelines), id: \.key) { pipelineID, config in
                    pipelineRow(id: pipelineID, config: config)
                }
            }
        }
    }

    private func pipelineRow(id: UUID, config: ChorusPipelineConfig) -> some View {
        let completedCount = appState.chorusService.completedResults[id]?.count ?? 0

        return HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18))
                .foregroundStyle(Constants.Colors.electricGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.modelID)
                    .font(Constants.Typography.body)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("\(config.stages.count) stages | \(config.totalLayers) layers")
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(completedCount)")
                    .font(Constants.Typography.monoDisplay)
                    .foregroundStyle(Constants.Colors.amber)

                Text("inferences")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius, style: .continuous))
    }

    // MARK: - Throughput

    private var throughputCard: some View {
        let totalInferences = appState.chorusService.completedResults.values
            .reduce(0) { $0 + $1.count }

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "gauge.with.dots.needle.67percent", title: "Throughput")

            HStack(spacing: 24) {
                metricColumn(value: "\(totalInferences)", label: "Total Inferences", color: Constants.Colors.electricGreen)
                metricColumn(value: "\(appState.chorusService.activePipelines.count)", label: "Pipelines", color: Constants.Colors.amber)
                metricColumn(value: "\(appState.chorusService.peerOffers.count)", label: "Peers Available", color: Constants.Colors.textSecondary)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private func metricColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Constants.Typography.monoDisplay)
                .foregroundStyle(color)

            Text(label)
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Peer Offers

    private var peerOffersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "person.2.fill", title: "Available Peers")

            if appState.chorusService.peerOffers.isEmpty {
                emptyState(icon: "person.2.slash", message: "No peers offering pipeline participation")
            } else {
                ForEach(Array(appState.chorusService.peerOffers), id: \.key) { peerID, offer in
                    peerOfferRow(peerID: peerID, offer: offer)
                }
            }
        }
    }

    private func peerOfferRow(peerID: String, offer: ChorusPipelineOffer) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(offer.batteryLevel > 0.3 ? Constants.Colors.electricGreen : Constants.Colors.amber)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(peerID.prefix(12) + "...")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(offer.availableMemoryMB)MB")
                        .font(Constants.Typography.monoSmall)
                    Text("|\(offer.computeCapability) TFLOPS")
                        .font(Constants.Typography.monoSmall)
                    Text("|\(Int(offer.batteryLevel * 100))%")
                        .font(Constants.Typography.monoSmall)
                }
                .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            if offer.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.Colors.electricGreen)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .fill(Constants.Colors.surfaceGlass)
        )
    }

    // MARK: - Start Pipeline Button

    private var startPipelineButton: some View {
        Button {
            showConfigSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Start Pipeline")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.amber)
            )
            .shadow(color: Constants.Colors.amber.opacity(0.4), radius: 16, y: 4)
        }
    }

    // MARK: - Config Sheet

    private var pipelineConfigSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Constants.Layout.spacing) {
                        // Model selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MODEL")
                                .font(Constants.Typography.badge)
                                .foregroundStyle(Constants.Colors.textTertiary)

                            ForEach(availableModels, id: \.0) { id, name in
                                Button {
                                    selectedModelID = id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedModelID == id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedModelID == id ? Constants.Colors.amber : Constants.Colors.textTertiary)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(name)
                                                .font(Constants.Typography.body)
                                                .foregroundStyle(Constants.Colors.textPrimary)
                                            Text(id)
                                                .font(Constants.Typography.monoSmall)
                                                .foregroundStyle(Constants.Colors.textTertiary)
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                            .fill(selectedModelID == id ? Constants.Colors.glassAmber : Constants.Colors.surfaceGlass)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                            .strokeBorder(
                                                selectedModelID == id ? Constants.Colors.glassAmberBorder : Constants.Colors.surfaceBorder,
                                                lineWidth: 1
                                            )
                                    )
                                }
                            }
                        }

                        // Available peers summary
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AVAILABLE PEERS")
                                .font(Constants.Typography.badge)
                                .foregroundStyle(Constants.Colors.textTertiary)

                            HStack(spacing: 12) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Constants.Colors.amber)

                                Text("\(appState.chorusService.peerOffers.count) peers ready")
                                    .font(Constants.Typography.body)
                                    .foregroundStyle(Constants.Colors.textPrimary)

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                    .fill(Constants.Colors.surfaceGlass)
                            )
                        }

                        // Info
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(Constants.Colors.textTertiary)

                            Text("The pipeline will automatically partition model layers across available peers based on their compute capabilities.")
                                .font(Constants.Typography.caption)
                                .foregroundStyle(Constants.Colors.textSecondary)
                        }
                        .padding(12)
                    }
                    .padding(.horizontal, Constants.Layout.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Configure Pipeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showConfigSheet = false
                    }
                    .foregroundStyle(Constants.Colors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        startPipeline()
                    } label: {
                        if isNegotiating {
                            ProgressView()
                                .tint(Constants.Colors.amber)
                        } else {
                            Text("Start")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Constants.Colors.amber)
                        }
                    }
                    .disabled(isNegotiating)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func startPipeline() {
        isNegotiating = true

        appState.chorusService.requestPipeline(
            modelID: selectedModelID,
            channelID: appState.channelManager.activeChannel?.id ?? ""
        )

        // Give time for offers to come in, then close
        Task {
            try? await Task.sleep(for: .seconds(3))
            isNegotiating = false
            showConfigSheet = false
        }
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

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Constants.Colors.amber)

            Text(title.uppercased())
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)

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

    // MARK: - Status Helpers

    private var pipelineStatusColor: Color {
        if !appState.chorusService.activePipelines.isEmpty {
            return Constants.Colors.electricGreen
        }
        if !appState.chorusService.peerOffers.isEmpty {
            return Constants.Colors.amber
        }
        return Constants.Colors.textTertiary
    }

    private var pipelineStatusText: String {
        if !appState.chorusService.activePipelines.isEmpty {
            return "PIPELINE ACTIVE"
        }
        if !appState.chorusService.peerOffers.isEmpty {
            return "PEERS AVAILABLE"
        }
        return "IDLE"
    }
}

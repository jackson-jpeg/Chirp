import PhotosUI
import SwiftUI
import OSLog

/// Camera/audio capture view for the Mesh Witness feature.
///
/// Allows the user to capture a photo (via image picker) and broadcast a
/// witness request to nearby mesh peers for cryptographic attestation.
struct WitnessCaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImageData: Data?
    @State private var capturedImage: UIImage?
    @State private var isCapturing = false
    @State private var activeSessionID: UUID?
    @State private var showExportSheet = false
    @State private var exportJSON: Data?
    @State private var showError = false
    @State private var errorMessage = ""

    private let channelID: String

    private let logger = Logger(subsystem: Constants.subsystem, category: "WitnessCaptureView")

    // MARK: - Init

    init(channelID: String) {
        self.channelID = channelID
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: Constants.Layout.spacing) {
                        captureSection
                        if activeSessionID != nil {
                            attestationStatusSection
                        }
                        completedAttestationsSection
                    }
                    .padding(.horizontal, Constants.Layout.horizontalPadding)
                    .padding(.vertical, 12)
                }
            }
        }
        .alert("Capture Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showExportSheet) {
            if let exportJSON {
                ShareSheetView(data: exportJSON)
            }
        }
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

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mesh Witness")
                    .font(Constants.Typography.heroTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("CAPTURE & ATTEST")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
            }

            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Constants.Colors.amber)
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Capture Section

    private var captureSection: some View {
        VStack(spacing: Constants.Layout.spacing) {
            // Preview area
            ZStack {
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.cardBackground)
                    .frame(height: 240)

                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius))
                        .frame(height: 230)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Constants.Colors.textTertiary)

                        Text("Select a photo to witness")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: Constants.Layout.glassBorderWidth)
            )

            // Photo picker
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .bold))
                    Text("Select Photo")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Constants.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 1)
                )
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadPhoto(from: newItem)
                }
            }

            // Capture & Witness button
            Button {
                Task {
                    await startWitnessSession()
                }
            } label: {
                HStack(spacing: 10) {
                    if isCapturing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text("Capture & Witness")
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
            .disabled(capturedImageData == nil || isCapturing)
            .opacity(capturedImageData == nil ? 0.5 : 1.0)
        }
    }

    // MARK: - Attestation Status

    private var attestationStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guard let sessionID = activeSessionID,
                  let attestation = appState.meshWitnessService.activeAttestations[sessionID] else {
                return AnyView(EmptyView())
            }

            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    // Status header
                    HStack(spacing: 10) {
                        Circle()
                            .fill(attestation.isVerified ? Constants.Colors.electricGreen : Constants.Colors.amber)
                            .frame(width: 10, height: 10)
                            .modifier(PulseModifier(isActive: !attestation.isVerified))

                        Text(attestation.isVerified ? "VERIFIED" : "COLLECTING SIGNATURES...")
                            .font(Constants.Typography.monoStatus)
                            .foregroundStyle(attestation.isVerified ? Constants.Colors.electricGreen : Constants.Colors.amber)

                        Spacer()

                        Text("\(attestation.countersignCount) peer\(attestation.countersignCount == 1 ? "" : "s") witnessed")
                            .font(Constants.Typography.monoSmall)
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }

                    // Verified badge
                    if attestation.isVerified {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Constants.Colors.electricGreen)

                            Text("Cryptographically Verified")
                                .font(Constants.Typography.cardTitle)
                                .foregroundStyle(Constants.Colors.electricGreen)
                        }
                        .padding(.vertical, 4)
                    }

                    // Countersign list
                    ForEach(attestation.countersigns) { countersign in
                        countersignRow(countersign)
                    }

                    // Export button
                    if attestation.isVerified {
                        Button {
                            exportAttestation(sessionID)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Export Attestation")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Constants.Colors.amber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                    .fill(Constants.Colors.glassAmber)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                                    .strokeBorder(Constants.Colors.glassAmberBorder, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(Constants.Layout.cardPadding)
                .background(glassCard)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
            )
        }
    }

    private func countersignRow(_ countersign: WitnessCountersign) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Constants.Colors.electricGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(countersign.counterSignerPeerID.prefix(12) + "...")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                Text(countersign.timestamp, style: .time)
                    .font(Constants.Typography.monoSmall)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }

            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(Constants.Colors.electricGreen)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .fill(Constants.Colors.glassGreen)
        )
    }

    // MARK: - Completed Attestations

    private var completedAttestationsSection: some View {
        let verified = appState.meshWitnessService.activeAttestations.values
            .filter { $0.isVerified && $0.id != activeSessionID }

        return Group {
            if !verified.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("COMPLETED")
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.textTertiary)

                    ForEach(Array(verified), id: \.id) { attestation in
                        NavigationLink {
                            AttestationDetailView(attestation: attestation)
                        } label: {
                            completedRow(attestation)
                        }
                    }
                }
            }
        }
    }

    private func completedRow(_ attestation: WitnessAttestation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(Constants.Colors.electricGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(attestation.mediaHash.prefix(8).map { String(format: "%02x", $0) }.joined())
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("\(attestation.countersignCount) witnesses")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)
            }

            Spacer()

            Text(attestation.createdAt, style: .relative)
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textTertiary)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Constants.Colors.textTertiary)
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius, style: .continuous))
    }

    // MARK: - Glass Card

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

    // MARK: - Actions

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                capturedImageData = data
                capturedImage = UIImage(data: data)
            }
        } catch {
            errorMessage = "Failed to load photo: \(error.localizedDescription)"
            showError = true
        }
    }

    private func startWitnessSession() async {
        guard let imageData = capturedImageData else { return }
        isCapturing = true
        defer { isCapturing = false }

        await appState.meshWitnessService.startWitnessSession(
            mediaData: imageData,
            mediaType: .photo,
            channelID: channelID
        )

        // Find the most recent session we just created
        if let latest = appState.meshWitnessService.activeAttestations.values
            .sorted(by: { $0.createdAt > $1.createdAt }).first {
            activeSessionID = latest.id
        }

        logger.info("Witness session started")
    }

    private func exportAttestation(_ id: UUID) {
        guard let json = appState.meshWitnessService.exportAttestation(id) else {
            errorMessage = "Failed to export attestation"
            showError = true
            return
        }
        exportJSON = json
        showExportSheet = true
    }
}

// MARK: - Pulse Animation Modifier

private struct PulseModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.symbolEffect(.pulse, isActive: true)
        } else {
            content
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheetView: UIViewControllerRepresentable {
    let data: Data

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("attestation_\(UUID().uuidString.prefix(8)).json")
        try? data.write(to: tempURL)
        return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

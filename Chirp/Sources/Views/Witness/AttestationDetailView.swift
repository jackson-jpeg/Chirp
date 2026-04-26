import MapKit
import SwiftUI

/// Detail view for a completed cryptographic attestation.
///
/// Shows the full proof chain: media hash, origin peer, all countersigners
/// with their verification status, locations, and timestamps.
struct AttestationDetailView: View {
    @Environment(AppState.self) private var appState

    let attestation: WitnessAttestation

    @State private var showExportSheet = false
    @State private var exportJSON: Data?

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Constants.Layout.spacing) {
                    verificationBadge
                    mediaInfoCard
                    originCard
                    countersignersCard
                    locationMapCard
                    exportButton
                }
                .padding(.horizontal, Constants.Layout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Attestation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportSheet) {
            if let exportJSON {
                AttestationShareSheet(data: exportJSON)
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

    // MARK: - Verification Badge

    private var verificationBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: attestation.isVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(attestation.isVerified ? Constants.Colors.electricGreen : Constants.Colors.amber)

            VStack(alignment: .leading, spacing: 2) {
                Text(attestation.isVerified ? "Verified Attestation" : "Pending Verification")
                    .font(Constants.Typography.sectionTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("\(attestation.countersignCount) independent witness\(attestation.countersignCount == 1 ? "" : "es")")
                    .font(Constants.Typography.caption)
                    .foregroundStyle(Constants.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .fill(attestation.isVerified ? Constants.Colors.glassGreen : Constants.Colors.glassAmber)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                .strokeBorder(
                    attestation.isVerified ? Constants.Colors.glassGreenBorder : Constants.Colors.glassAmberBorder,
                    lineWidth: Constants.Layout.glassBorderWidth
                )
        )
    }

    // MARK: - Media Info Card

    private var mediaInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("MEDIA HASH")

            Text(attestation.mediaHash.map { String(format: "%02x", $0) }.joined())
                .font(Constants.Typography.mono)
                .foregroundStyle(Constants.Colors.amber)
                .lineLimit(2)
                .truncationMode(.middle)

            Divider().background(Constants.Colors.surfaceBorder)

            HStack(spacing: 24) {
                infoColumn(label: "TYPE", value: attestation.mediaType.rawValue.uppercased())
                infoColumn(label: "CREATED", value: formatDate(attestation.createdAt))
                infoColumn(label: "WITNESSES", value: "\(attestation.countersignCount)")
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    // MARK: - Origin Card

    private var originCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ORIGIN PEER")

            HStack(spacing: 12) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Constants.Colors.amber)

                VStack(alignment: .leading, spacing: 4) {
                    Text(attestation.originPeerID.prefix(16) + "...")
                        .font(Constants.Typography.mono)
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .lineLimit(1)

                    Text(formatDate(attestation.originTimestamp))
                        .font(Constants.Typography.monoSmall)
                        .foregroundStyle(Constants.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Constants.Colors.electricGreen)
            }

            if let loc = attestation.originLocation {
                locationRow(latitude: loc.latitude, longitude: loc.longitude, accuracy: loc.horizontalAccuracy)
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    // MARK: - Countersigners Card

    private var countersignersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("COUNTERSIGNERS")

            if attestation.countersigns.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Constants.Colors.textTertiary)
                        Text("No countersigns yet")
                            .font(Constants.Typography.caption)
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(attestation.countersigns) { countersign in
                    countersignerRow(countersign)
                }
            }
        }
        .padding(Constants.Layout.cardPadding)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
    }

    private func countersignerRow(_ countersign: WitnessCountersign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Constants.Colors.electricGreen)

                Text(countersign.counterSignerPeerID.prefix(16) + "...")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Verification status
                let isValid = appState.meshWitnessService.verifyAttestation(attestation)
                Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(isValid ? Constants.Colors.electricGreen : Constants.Colors.hotRed)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(formatDate(countersign.timestamp))
                        .font(Constants.Typography.monoSmall)
                }
                .foregroundStyle(Constants.Colors.textTertiary)

                if let loc = countersign.location {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.system(size: 10))
                        Text(String(format: "%.4f, %.4f", loc.latitude, loc.longitude))
                            .font(Constants.Typography.monoSmall)
                    }
                    .foregroundStyle(Constants.Colors.textTertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .fill(Constants.Colors.glassGreen)
        )
    }

    // MARK: - Location Map

    private var locationMapCard: some View {
        let locations = collectLocations()

        return Group {
            if !locations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("WITNESS LOCATIONS")

                    Map {
                        ForEach(locations, id: \.id) { pin in
                            Marker(pin.label, coordinate: pin.coordinate)
                                .tint(pin.isOrigin ? Color(Constants.Colors.amber) : Color(Constants.Colors.electricGreen))
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius))
                    .allowsHitTesting(false)
                }
                .padding(Constants.Layout.cardPadding)
                .background(glassCard)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius, style: .continuous))
            }
        }
    }

    // MARK: - Export

    private var exportButton: some View {
        Button {
            if let json = appState.meshWitnessService.exportAttestation(attestation.id) {
                exportJSON = json
                showExportSheet = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                Text("Export Proof Chain")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Constants.Layout.cardCornerRadius)
                    .fill(Constants.Colors.amber)
            )
            .shadow(color: Constants.Colors.amber.opacity(0.4), radius: 16, y: 4)
        }
    }

    // MARK: - Helpers

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Constants.Typography.badge)
            .foregroundStyle(Constants.Colors.textTertiary)
    }

    private func infoColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Constants.Typography.badge)
                .foregroundStyle(Constants.Colors.textTertiary)
            Text(value)
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textPrimary)
        }
    }

    private func locationRow(latitude: Double, longitude: Double, accuracy: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 11))
                .foregroundStyle(Constants.Colors.amber)

            Text(String(format: "%.5f, %.5f", latitude, longitude))
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textSecondary)

            Text("(\(Int(accuracy))m)")
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textTertiary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private struct MapPin: Identifiable {
        let id = UUID()
        let label: String
        let coordinate: CLLocationCoordinate2D
        let isOrigin: Bool
    }

    private func collectLocations() -> [MapPin] {
        var pins: [MapPin] = []

        if let loc = attestation.originLocation {
            pins.append(MapPin(
                label: "Origin",
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                isOrigin: true
            ))
        }

        for (index, cs) in attestation.countersigns.enumerated() {
            if let loc = cs.location {
                pins.append(MapPin(
                    label: "Witness \(index + 1)",
                    coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                    isOrigin: false
                ))
            }
        }

        return pins
    }
}

// MARK: - Share Sheet

private struct AttestationShareSheet: UIViewControllerRepresentable {
    let data: Data

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("proof_chain_\(UUID().uuidString.prefix(8)).json")
        try? data.write(to: tempURL)
        return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

import CoreLocation
import MapKit
import SwiftUI
import OSLog

/// Map view for dropping and finding location-anchored encrypted messages.
///
/// Supports tap-to-drop with message composition, time-lock, expiry, and
/// scavenger-hunt chain creation. Also provides a "Scan Here" button to
/// attempt decryption of nearby drops.
struct DeadDropMapView: View {
    @Environment(AppState.self) private var appState

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var showComposeSheet = false
    @State private var showScanResult = false
    @State private var scanResultMessage = ""
    @State private var isScanning = false

    // Compose state
    @State private var composeText = ""
    @State private var composeTimeLock = false
    @State private var composeTimeLockDate = Date()
    @State private var composeExpiryHours: Double = 24
    @State private var composeIsChainLink = false
    @State private var composeNextHint = ""

    private let channelID: String

    private let logger = Logger(subsystem: Constants.subsystem, category: "DeadDropMapView")

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
                mapContent
                controlBar
                pickedUpSection
            }
        }
        .sheet(isPresented: $showComposeSheet) {
            composeSheet
        }
        .alert("Scan Result", isPresented: $showScanResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanResultMessage)
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
                Text("Dead Drop")
                    .font(Constants.Typography.heroTitle)
                    .foregroundStyle(Constants.Colors.textPrimary)

                Text("LOCATION MESSAGES")
                    .font(Constants.Typography.mono)
                    .foregroundStyle(Constants.Colors.amber)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(appState.deadDropService.storedDrops.count)")
                    .font(Constants.Typography.monoDisplay)
                    .foregroundStyle(Constants.Colors.amber)
                Text("nearby drops")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.textTertiary)
            }
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Map

    private var mapContent: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            // Show user location
            UserAnnotation()

            // Show stored drops as markers (coarse position from geohash prefix)
            ForEach(Array(appState.deadDropService.myDrops), id: \.id) { drop in
                Annotation("My Drop", coordinate: approximateCoordinate(from: drop.geohashPrefix)) {
                    dropPin(isOwn: true, isPickedUp: false)
                }
            }

            // Show found/decrypted drops
            ForEach(Array(appState.deadDropService.pickedUpMessages.keys), id: \.self) { dropID in
                if let drop = appState.deadDropService.storedDrops[dropID] {
                    Annotation("Found", coordinate: approximateCoordinate(from: drop.geohashPrefix)) {
                        dropPin(isOwn: false, isPickedUp: true)
                    }
                }
            }

            // Show tap-selected coordinate
            if let coord = selectedCoordinate {
                Annotation("Drop Here", coordinate: coord) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 28))
                        .foregroundStyle(Constants.Colors.amber)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius))
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .overlay(alignment: .topTrailing) {
            // Tap-to-drop instruction
            Text("Tap map to select drop location")
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .padding(.trailing, Constants.Layout.horizontalPadding + 8)
                .padding(.top, 8)
        }
        .onTapGesture { location in
            // Note: In a production app, this would convert the tap location
            // to map coordinates via a MapReader proxy. For now we use the
            // user's current GPS as the drop point.
            if let userLoc = appState.locationService.currentLocation {
                selectedCoordinate = userLoc.coordinate
                showComposeSheet = true
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Drop at current location
            Button {
                if let loc = appState.locationService.currentLocation {
                    selectedCoordinate = loc.coordinate
                    showComposeSheet = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Drop Here")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(Constants.Colors.amber)
                )
            }

            // Scan for drops
            Button {
                scanForDrops()
            } label: {
                HStack(spacing: 8) {
                    if isScanning {
                        ProgressView()
                            .tint(Constants.Colors.electricGreen)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text("Scan Here")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Constants.Colors.electricGreen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(Constants.Colors.glassGreen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .strokeBorder(Constants.Colors.glassGreenBorder, lineWidth: 1)
                )
            }
            .disabled(isScanning)
        }
        .padding(.horizontal, Constants.Layout.horizontalPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Picked Up Messages

    private var pickedUpSection: some View {
        let messages = appState.deadDropService.pickedUpMessages

        return Group {
            if !messages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FOUND MESSAGES")
                        .font(Constants.Typography.badge)
                        .foregroundStyle(Constants.Colors.textTertiary)
                        .padding(.horizontal, Constants.Layout.horizontalPadding)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(messages), id: \.key) { dropID, text in
                                foundMessageCard(dropID: dropID, text: text)
                            }
                        }
                        .padding(.horizontal, Constants.Layout.horizontalPadding)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func foundMessageCard(dropID: UUID, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.Colors.electricGreen)

                Text("DECRYPTED")
                    .font(Constants.Typography.badge)
                    .foregroundStyle(Constants.Colors.electricGreen)
            }

            Text(text)
                .font(Constants.Typography.body)
                .foregroundStyle(Constants.Colors.textPrimary)
                .lineLimit(3)

            Text(dropID.uuidString.prefix(8))
                .font(Constants.Typography.monoSmall)
                .foregroundStyle(Constants.Colors.textTertiary)
        }
        .frame(width: 200, alignment: .leading)
        .padding(Constants.Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                .strokeBorder(Constants.Colors.glassGreenBorder, lineWidth: Constants.Layout.glassBorderWidth)
        )
    }

    // MARK: - Compose Sheet

    private var composeSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Constants.Layout.spacing) {
                        // Location info
                        if let coord = selectedCoordinate {
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(Constants.Colors.amber)
                                Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                                    .font(Constants.Typography.mono)
                                    .foregroundStyle(Constants.Colors.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                    .fill(Constants.Colors.surfaceGlass)
                            )
                        }

                        // Message input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MESSAGE")
                                .font(Constants.Typography.badge)
                                .foregroundStyle(Constants.Colors.textTertiary)

                            TextEditor(text: $composeText)
                                .font(Constants.Typography.body)
                                .foregroundStyle(Constants.Colors.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                        .fill(Constants.Colors.surfaceGlass)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                        .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 1)
                                )
                        }

                        // Time lock
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $composeTimeLock) {
                                HStack(spacing: 8) {
                                    Image(systemName: "lock.badge.clock")
                                        .foregroundStyle(Constants.Colors.amber)
                                    Text("Time Lock")
                                        .foregroundStyle(Constants.Colors.textPrimary)
                                }
                            }
                            .tint(Constants.Colors.amber)

                            if composeTimeLock {
                                DatePicker(
                                    "Unlock Date",
                                    selection: $composeTimeLockDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .tint(Constants.Colors.amber)
                                .foregroundStyle(Constants.Colors.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                .fill(Constants.Colors.surfaceGlass)
                        )

                        // Expiry
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "timer")
                                    .foregroundStyle(Constants.Colors.amber)
                                Text("Expires in \(Int(composeExpiryHours))h")
                                    .font(Constants.Typography.caption)
                                    .foregroundStyle(Constants.Colors.textSecondary)
                            }

                            Slider(value: $composeExpiryHours, in: 1...168, step: 1)
                                .tint(Constants.Colors.amber)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                .fill(Constants.Colors.surfaceGlass)
                        )

                        // Scavenger hunt chain
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $composeIsChainLink) {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .foregroundStyle(Constants.Colors.amber)
                                    Text("Scavenger Hunt Chain")
                                        .foregroundStyle(Constants.Colors.textPrimary)
                                }
                            }
                            .tint(Constants.Colors.amber)

                            if composeIsChainLink {
                                TextField("Hint to next drop...", text: $composeNextHint)
                                    .font(Constants.Typography.body)
                                    .foregroundStyle(Constants.Colors.textPrimary)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                            .fill(Constants.Colors.surfaceGlass)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                            .strokeBorder(Constants.Colors.surfaceBorder, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: Constants.Layout.glassCornerRadius)
                                .fill(Constants.Colors.surfaceGlass)
                        )
                    }
                    .padding(.horizontal, Constants.Layout.horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Drop Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showComposeSheet = false
                        resetCompose()
                    }
                    .foregroundStyle(Constants.Colors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Drop") {
                        dropMessage()
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.amber)
                    .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func scanForDrops() {
        isScanning = true

        let beforeCount = appState.deadDropService.pickedUpMessages.count
        appState.deadDropService.scanForDrops()
        let afterCount = appState.deadDropService.pickedUpMessages.count
        let found = afterCount - beforeCount

        isScanning = false

        if found > 0 {
            scanResultMessage = "Found and decrypted \(found) message\(found == 1 ? "" : "s")!"
        } else {
            scanResultMessage = "No drops found at this location."
        }
        showScanResult = true
    }

    private func dropMessage() {
        guard let coord = selectedCoordinate else { return }

        let timeLockDate: String? = composeTimeLock ? formatTimeLockDate(composeTimeLockDate) : nil

        let nextHint: DropChainHint? = composeIsChainLink && !composeNextHint.isEmpty
            ? DropChainHint(hintText: composeNextHint, nextLatitude: nil, nextLongitude: nil, nextTimeLockDate: nil)
            : nil

        appState.deadDropService.dropMessage(
            text: composeText,
            latitude: coord.latitude,
            longitude: coord.longitude,
            channelID: channelID,
            senderID: appState.localPeerID,
            senderName: appState.localPeerName,
            timeLockDate: timeLockDate,
            expiryHours: Int(composeExpiryHours),
            nextHint: nextHint
        )

        showComposeSheet = false
        resetCompose()
    }

    private func resetCompose() {
        composeText = ""
        composeTimeLock = false
        composeTimeLockDate = Date()
        composeExpiryHours = 24
        composeIsChainLink = false
        composeNextHint = ""
        selectedCoordinate = nil
    }

    // MARK: - Helpers

    private func dropPin(isOwn: Bool, isPickedUp: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isPickedUp ? Constants.Colors.electricGreen : (isOwn ? Constants.Colors.amber : Constants.Colors.textTertiary))
                .frame(width: 20, height: 20)

            Circle()
                .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)

            Image(systemName: isPickedUp ? "lock.open.fill" : "envelope.fill")
                .font(.system(size: 9))
                .foregroundStyle(.black)
        }
    }

    /// Approximate a coordinate from a 4-character geohash prefix.
    /// This gives a very rough position for map display purposes only.
    private func approximateCoordinate(from geohashPrefix: String) -> CLLocationCoordinate2D {
        if let decoded = Geohash.decode(geohashPrefix) {
            return CLLocationCoordinate2D(latitude: decoded.latitude, longitude: decoded.longitude)
        }
        // Fallback to 0,0 if geohash cannot be decoded
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    private func formatTimeLockDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

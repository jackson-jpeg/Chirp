import SwiftUI
import UIKit

// MARK: - Animated Mesh Gradient Background

private struct MeshGradientBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

                let centers: [(dx: CGFloat, dy: CGFloat, speed: CGFloat)] = [
                    (0.3, 0.2, 0.4),
                    (0.7, 0.6, 0.3),
                    (0.5, 0.8, 0.5),
                    (0.2, 0.5, 0.35),
                ]

                for (i, c) in centers.enumerated() {
                    let offsetX = sin(t * c.speed + Double(i) * 1.5) * 0.15
                    let offsetY = cos(t * c.speed * 0.8 + Double(i) * 2.0) * 0.12
                    let cx = (c.dx + offsetX) * w
                    let cy = (c.dy + offsetY) * h

                    let colors: [(Color, CGFloat)] = i % 2 == 0
                        ? [
                            (Color(red: 0.08, green: 0.05, blue: 0.25).opacity(0.8), 0),
                            (Color(red: 0.12, green: 0.08, blue: 0.35).opacity(0.4), 0.5),
                            (Color.clear, 1.0),
                        ]
                        : [
                            (Color(red: 0.05, green: 0.08, blue: 0.30).opacity(0.7), 0),
                            (Color(red: 0.10, green: 0.05, blue: 0.28).opacity(0.3), 0.5),
                            (Color.clear, 1.0),
                        ]

                    let gradient = Gradient(stops: colors.map {
                        Gradient.Stop(color: $0.0, location: $0.1)
                    })

                    let radius = max(w, h) * 0.6
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .radialGradient(
                            gradient,
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Animated Network Nodes Background

private struct NetworkNodesBackground: View {
    private let nodeCount = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let w = size.width
                let h = size.height

                // Generate stable animated positions
                var positions: [(CGFloat, CGFloat)] = []
                for i in 0..<nodeCount {
                    let baseX = (CGFloat(i % 4) + 0.5) / 4.0
                    let baseY = (CGFloat(i / 4) + 0.5) / 3.0
                    let dx = sin(t * 0.3 + Double(i) * 1.7) * 0.06
                    let dy = cos(t * 0.25 + Double(i) * 2.1) * 0.05
                    positions.append(((baseX + dx) * w, (baseY + dy) * h))
                }

                // Draw connections between nearby nodes
                let connectDist = w * 0.35
                for i in 0..<positions.count {
                    for j in (i + 1)..<positions.count {
                        let dx = positions[i].0 - positions[j].0
                        let dy = positions[i].1 - positions[j].1
                        let dist = sqrt(dx * dx + dy * dy)
                        if dist < connectDist {
                            let alpha = (1.0 - dist / connectDist) * 0.15
                            var path = Path()
                            path.move(to: CGPoint(x: positions[i].0, y: positions[i].1))
                            path.addLine(to: CGPoint(x: positions[j].0, y: positions[j].1))
                            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 0.8)
                        }
                    }
                }

                // Draw nodes
                for (i, pos) in positions.enumerated() {
                    let pulse = sin(t * 1.5 + Double(i) * 0.8) * 0.5 + 0.5
                    let nodeSize: CGFloat = 3 + pulse * 2
                    let glowSize: CGFloat = nodeSize * 4

                    // Glow
                    let glowRect = CGRect(
                        x: pos.0 - glowSize / 2,
                        y: pos.1 - glowSize / 2,
                        width: glowSize,
                        height: glowSize
                    )
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .color(.white.opacity(0.04 + pulse * 0.03))
                    )

                    // Core
                    let rect = CGRect(
                        x: pos.0 - nodeSize / 2,
                        y: pos.1 - nodeSize / 2,
                        width: nodeSize,
                        height: nodeSize
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.2 + pulse * 0.15))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page Indicator Dots

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == current
                            ? Constants.Colors.amber
                            : Constants.Colors.slate500
                    )
                    .frame(
                        width: index == current ? 24 : 8,
                        height: 8
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
            }
        }
        .accessibilityLabel(String(localized: "Page \(current + 1) of \(count)"))
    }
}

// MARK: - Continue Button

private struct ContinueButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    init(_ title: String = String(localized: "Continue"), disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: Constants.Layout.buttonCornerRadius)
                        .fill(Constants.Colors.amber.opacity(disabled ? 0.3 : 1.0))
                )
        }
        .disabled(disabled)
        .padding(.horizontal, 32)
        .accessibilityLabel(title)
    }
}

// MARK: - Shimmer Start Button

private struct ShimmerStartButton: View {
    let action: () -> Void
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        Button(action: action) {
            Text(String(localized: "Start Chirping"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Constants.Colors.amberDark,
                                        Constants.Colors.amber,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.0),
                                        .white.opacity(0.25),
                                        .white.opacity(0.0),
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Constants.Colors.amber.opacity(0.4), radius: 20, y: 8)
        }
        .padding(.horizontal, 32)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.5)
            ) {
                shimmerOffset = 2.0
            }
        }
        .accessibilityLabel(String(localized: "Start Chirping"))
        .accessibilityIdentifier(AccessibilityID.getStartedButton)
    }
}

// MARK: - Page 1: The Mesh

private struct TheMeshPage: View {
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Small wordmark
            Text("ChirpChirp")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Constants.Colors.amber.opacity(0.6))
                .padding(.bottom, 24)

            // Big bold title
            Text(String(localized: "Communication\nWithout Infrastructure"))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .opacity(titleOpacity)
                .offset(y: titleOffset)

            Spacer().frame(height: 20)

            // Subtitle
            Text(String(localized: "No cell towers. No WiFi. No internet.\nJust you and the mesh."))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .opacity(subtitleOpacity)
                .offset(y: subtitleOffset)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                titleOpacity = 1.0
                titleOffset = 0
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.6)) {
                subtitleOpacity = 1.0
                subtitleOffset = 0
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page 2: How It Works

private struct HowItWorksPage: View {
    @State private var step1Visible = false
    @State private var step2Visible = false
    @State private var step3Visible = false

    private struct StepRow: View {
        let icon: String
        let title: String
        let subtitle: String
        let visible: Bool

        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Constants.Colors.amber)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Constants.Colors.glassAmber)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Constants.Colors.glassAmberBorder, lineWidth: Constants.Layout.glassBorderWidth)
                            )
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 32)
            .opacity(visible ? 1.0 : 0.0)
            .offset(y: visible ? 0 : 20)
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(String(localized: "How It Works"))
                .font(Constants.Typography.heroTitle)
                .foregroundStyle(.white)
                .padding(.bottom, 40)

            VStack(spacing: 28) {
                StepRow(
                    icon: "phone.radiowaves.up",
                    title: String(localized: "Your phone becomes a relay"),
                    subtitle: String(localized: "Bluetooth and WiFi Direct turn every device into a mesh node."),
                    visible: step1Visible
                )

                StepRow(
                    icon: "person.3.fill",
                    title: String(localized: "Every device extends the network"),
                    subtitle: String(localized: "Messages hop from phone to phone, reaching farther with each node."),
                    visible: step2Visible
                )

                StepRow(
                    icon: "globe",
                    title: String(localized: "Communication reaches farther"),
                    subtitle: String(localized: "Five people can cover a kilometer with zero infrastructure."),
                    visible: step3Visible
                )
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                step1Visible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5)) {
                step2Visible = true
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8)) {
                step3Visible = true
            }
        }
    }
}

// MARK: - Page 3: Your Identity

private struct IdentityPage: View {
    @Binding var callsign: String
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(String(localized: "Your Identity"))
                .font(Constants.Typography.heroTitle)
                .foregroundStyle(.white)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

            Spacer().frame(height: 12)

            Text(String(localized: "Your callsign is how others see you on the mesh."))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(contentOpacity)
                .offset(y: contentOffset)

            Spacer().frame(height: 48)

            // Callsign input
            HStack(spacing: 12) {
                TextField(String(localized: "Callsign"), text: $callsign)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(AccessibilityID.callsignField)
                    .accessibilityLabel(String(localized: "Callsign input"))

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        callsign = CallsignGenerator.generate()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Constants.Colors.amber)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Constants.Colors.glassAmber)
                                .overlay(
                                    Circle()
                                        .stroke(Constants.Colors.glassAmberBorder, lineWidth: 1)
                                )
                        )
                }
                .accessibilityLabel(String(localized: "Generate new callsign"))
            }
            .padding(.horizontal, 48)

            // Amber underline
            Rectangle()
                .fill(Constants.Colors.amber)
                .frame(height: 2)
                .padding(.horizontal, 48)
                .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .onAppear {
            if callsign.isEmpty {
                callsign = CallsignGenerator.generate()
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                contentOpacity = 1.0
                contentOffset = 0
            }
        }
    }
}

// MARK: - Page 4: Go Live

private struct GoLivePage: View {
    @Environment(AppState.self) private var appState

    @State private var discoveredPeers: [String] = []
    @State private var searchSeconds: Int = 0
    @State private var micRequested = false
    @State private var micGranted = false
    @State private var titleOpacity: Double = 0
    @State private var statusOpacity: Double = 0
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Title
            Text(String(localized: "Your mesh is ready"))
                .font(Constants.Typography.heroTitle)
                .foregroundStyle(.white)
                .opacity(titleOpacity)
                .accessibilityAddTraits(.isHeader)

            Spacer().frame(height: 8)

            // Radar
            MeshRadarView(discoveredPeers: discoveredPeers)
                .frame(height: 260)
                .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            // Discovery status
            Group {
                if discoveredPeers.isEmpty {
                    if searchSeconds >= 5 {
                        Text(String(localized: "No peers nearby yet \u{2014} you're the first node.\nThe mesh grows when others join."))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Constants.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(Constants.Colors.amber)
                            Text(String(localized: "Scanning for nearby devices..."))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Constants.Colors.textSecondary)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Constants.Colors.electricGreen)
                        Text(String(localized: "Found \(discoveredPeers.count) nearby! The mesh is alive."))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Constants.Colors.electricGreen)
                    }
                }
            }
            .opacity(statusOpacity)
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            // Microphone permission
            if !micGranted {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Constants.Colors.amber)
                        Text(String(localized: "Microphone needed for push-to-talk"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Constants.Colors.textSecondary)
                    }

                    if !micRequested {
                        Button {
                            Task {
                                await appState.requestMicPermission()
                                micGranted = appState.micPermissionGranted
                                micRequested = true
                            }
                        } label: {
                            Text(String(localized: "Enable Microphone"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Constants.Colors.amber)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .stroke(Constants.Colors.amber.opacity(0.5), lineWidth: 1.5)
                                )
                        }
                        .accessibilityLabel(String(localized: "Enable Microphone"))
                    } else {
                        Text(String(localized: "You can enable it later in Settings"))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Constants.Colors.textTertiary)
                    }
                }
                .padding(.horizontal, 32)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Constants.Colors.electricGreen)
                    Text(String(localized: "Microphone enabled"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Constants.Colors.electricGreen)
                }
            }

            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                titleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                statusOpacity = 1.0
            }
            // Check current mic status
            micGranted = appState.micPermissionGranted
            // Start peer discovery polling
            startPeerPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func startPeerPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [appState] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                searchSeconds += 1
                let peers = appState.multipeerTransport.peers
                let names = peers.map(\.name)
                if names != discoveredPeers {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        discoveredPeers = names
                    }
                }
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var currentPage = 0
    @State private var callsign: String = ""
    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background layers
            Constants.Colors.backgroundPrimary.ignoresSafeArea()
            MeshGradientBackground()
            if currentPage == 0 {
                NetworkNodesBackground()
                    .opacity(0.6)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // Skip button (pages 0-2)
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage = totalPages - 1
                            }
                        } label: {
                            Text(String(localized: "Skip"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Constants.Colors.textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        .transition(.opacity)
                        .accessibilityLabel(String(localized: "Skip onboarding"))
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 8)

                // Page content
                TabView(selection: $currentPage) {
                    TheMeshPage()
                        .tag(0)

                    HowItWorksPage()
                        .tag(1)

                    IdentityPage(callsign: $callsign)
                        .tag(2)

                    GoLivePage()
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom controls
                VStack(spacing: 20) {
                    PageDots(count: totalPages, current: currentPage)

                    // Action button per page
                    switch currentPage {
                    case 0, 1:
                        ContinueButton {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                        .transition(.opacity)

                    case 2:
                        ContinueButton(
                            disabled: callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            // Save callsign before proceeding
                            let trimmed = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                appState.callsign = trimmed
                            }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                        .transition(.opacity)

                    case 3:
                        ShimmerStartButton {
                            completeOnboarding()
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))

                    default:
                        EmptyView()
                    }
                }
                .padding(.bottom, 40)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
            }
        }
        .onAppear {
            // Pre-populate with existing callsign or generate one
            let existing = UserDefaults.standard.string(forKey: "com.chirpchirp.callsign") ?? ""
            if existing.isEmpty || existing == UIDevice.current.name {
                callsign = CallsignGenerator.generate()
            } else {
                callsign = existing
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func completeOnboarding() {
        // Save callsign if not already saved
        let trimmed = callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appState.callsign = trimmed
        }
        appState.isOnboardingComplete = true
    }
}

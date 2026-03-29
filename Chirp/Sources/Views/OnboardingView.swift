import SwiftUI

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

// MARK: - Spring Letter Wordmark

private struct SpringWordmark: View {
    let text: String = "ChirpChirp"
    @State private var letterVisible: [Bool] = Array(repeating: false, count: 10)

    var body: some View {
        HStack(spacing: -2) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: 0xFFB800),
                                Color(hex: 0xFFD060),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(letterVisible[index] ? 1.0 : 0.0)
                    .opacity(letterVisible[index] ? 1.0 : 0.0)
            }
        }
        .onAppear {
            for i in 0..<text.count {
                withAnimation(
                    .spring(response: 0.5, dampingFraction: 0.55)
                    .delay(Double(i) * 0.05 + 0.3)
                ) {
                    letterVisible[i] = true
                }
            }
        }
    }
}

// MARK: - Animated Mesh Network Illustration

private struct MeshNetworkIllustration: View {
    @State private var nodeScales: [CGFloat] = Array(repeating: 0, count: 7)
    @State private var lineOpacities: [Double] = Array(repeating: 0, count: 8)
    @State private var pulsePhase: CGFloat = 0

    // Node positions (normalized 0-1)
    private let nodes: [(x: CGFloat, y: CGFloat)] = [
        (0.5, 0.3),   // center top
        (0.2, 0.5),   // left
        (0.8, 0.5),   // right
        (0.35, 0.75), // bottom left
        (0.65, 0.75), // bottom right
        (0.1, 0.3),   // far left
        (0.9, 0.3),   // far right
    ]

    // Connections between nodes (index pairs)
    private let connections: [(Int, Int)] = [
        (0, 1), (0, 2), (1, 3), (2, 4), (1, 5), (2, 6), (3, 4), (0, 4)
    ]

    var body: some View {
        let amber = Constants.Colors.amber

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Connection lines
                ForEach(0..<connections.count, id: \.self) { i in
                    let from = nodes[connections[i].0]
                    let to = nodes[connections[i].1]
                    Path { path in
                        path.move(to: CGPoint(x: from.x * w, y: from.y * h))
                        path.addLine(to: CGPoint(x: to.x * w, y: to.y * h))
                    }
                    .stroke(amber.opacity(lineOpacities[i] * 0.4), lineWidth: 1.5)
                }

                // Nodes
                ForEach(0..<nodes.count, id: \.self) { i in
                    let node = nodes[i]
                    ZStack {
                        // Glow
                        Circle()
                            .fill(amber.opacity(0.15))
                            .frame(width: 32, height: 32)

                        // Core
                        Circle()
                            .fill(amber)
                            .frame(width: 12, height: 12)

                        // Pulse ring
                        Circle()
                            .stroke(amber.opacity(0.3), lineWidth: 1)
                            .frame(width: 12 + pulsePhase * 20, height: 12 + pulsePhase * 20)
                            .opacity(1 - pulsePhase)
                    }
                    .scaleEffect(nodeScales[i])
                    .position(x: node.x * w, y: node.y * h)
                }
            }
        }
        .onAppear {
            // Stagger node appearance
            for i in 0..<nodes.count {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(i) * 0.12)) {
                    nodeScales[i] = 1.0
                }
            }
            // Stagger line appearance
            for i in 0..<connections.count {
                withAnimation(.easeOut(duration: 0.5).delay(0.3 + Double(i) * 0.1)) {
                    lineOpacities[i] = 1.0
                }
            }
            // Pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(1.0)) {
                pulsePhase = 1.0
            }
        }
    }
}

// MARK: - Tower Down Illustration

private struct TowerDownIllustration: View {
    @State private var towerOpacity: Double = 1.0
    @State private var slashOpacity: Double = 0.0
    @State private var phoneGlow: Double = 0.0

    var body: some View {
        let amber = Constants.Colors.amber
        let red = Constants.Colors.hotRed

        ZStack {
            // Cell tower (fading out)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(red.opacity(towerOpacity * 0.5))
                .overlay(
                    // Red X over tower
                    Image(systemName: "xmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(red)
                        .opacity(slashOpacity)
                )

            // Phones lighting up around the dead tower
            ForEach(0..<4, id: \.self) { i in
                let angle = Double(i) * 90.0 + 45.0
                let rad = angle * .pi / 180
                let dist: CGFloat = 80
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(amber)
                    .opacity(phoneGlow)
                    .offset(x: cos(rad) * dist, y: sin(rad) * dist)
            }
        }
        .onAppear {
            // Tower fades and gets X
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                towerOpacity = 0.3
                slashOpacity = 1.0
            }
            // Phones light up
            withAnimation(.easeIn(duration: 0.8).delay(1.0)) {
                phoneGlow = 1.0
            }
        }
    }
}

// MARK: - Onboarding V2 Page

private struct OnboardingV2Page: View {
    let title: String
    let subtitle: String
    let accentColor: Color
    let illustration: AnyView

    @State private var textOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Illustration
            illustration
                .frame(width: 260, height: 180)

            // Title
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .opacity(textOpacity)

            // Subtitle
            Text(subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .opacity(textOpacity)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Shimmer Button

private struct ShimmerGetStartedButton: View {
    let action: () -> Void
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        Button(action: action) {
            Text("Get Started")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: 0xFFB800),
                                        Color(hex: 0xFFC830),
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
                                        .white.opacity(0.35),
                                        .white.opacity(0.0),
                                    ],
                                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                                )
                            )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color(hex: 0xFFB800).opacity(0.4), radius: 20, y: 8)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.5)
            ) {
                shimmerOffset = 2.0
            }
        }
        .accessibilityLabel("Get Started")
    }
}

// MARK: - Lock Shield Illustration

private struct EncryptionIllustration: View {
    @State private var shieldScale: CGFloat = 0.5
    @State private var lockOpacity: Double = 0.0
    @State private var ringRotation: Double = 0

    var body: some View {
        let green = Constants.Colors.electricGreen

        ZStack {
            // Rotating ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [green.opacity(0.4), green.opacity(0.05), green.opacity(0.4)],
                        center: .center
                    ),
                    lineWidth: 2
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(ringRotation))

            // Inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [green.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)

            // Shield with lock
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(green)
                .symbolRenderingMode(.hierarchical)
                .scaleEffect(shieldScale)
                .opacity(lockOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.2)) {
                shieldScale = 1.0
                lockOpacity = 1.0
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

// MARK: - Use Cases Illustration

private struct UseCasesIllustration: View {
    @State private var visibleCount = 0

    private let useCases: [(icon: String, label: String)] = [
        ("tornado", "Disasters"),
        ("music.note.house.fill", "Concerts"),
        ("figure.hiking", "Off-Grid"),
        ("hand.raised.fill", "Protests"),
        ("mountain.2.fill", "Adventures"),
        ("building.2.fill", "Emergencies"),
    ]

    var body: some View {
        let amber = Constants.Colors.amber

        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            ForEach(0..<useCases.count, id: \.self) { i in
                VStack(spacing: 6) {
                    Image(systemName: useCases[i].icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(amber)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(amber.opacity(0.1))
                        )

                    Text(useCases[i].label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .scaleEffect(i < visibleCount ? 1.0 : 0.5)
                .opacity(i < visibleCount ? 1.0 : 0.0)
            }
        }
        .padding(.horizontal, 20)
        .onAppear {
            for i in 0..<useCases.count {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.1)) {
                    visibleCount = i + 1
                }
            }
        }
    }
}

// MARK: - Talk + Chat Illustration

private struct TalkChatIllustration: View {
    @State private var talkVisible = false
    @State private var chatVisible = false

    var body: some View {
        let amber = Constants.Colors.amber

        HStack(spacing: 24) {
            // Talk side
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(amber.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(amber)
                        .frame(width: 56, height: 56)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.black)
                }
                Text("Voice")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .scaleEffect(talkVisible ? 1.0 : 0.6)
            .opacity(talkVisible ? 1.0 : 0.0)

            // Divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 80)

            // Chat side
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(amber)
                }
                Text("Text")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Stealth")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .scaleEffect(chatVisible ? 1.0 : 0.6)
            .opacity(chatVisible ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                talkVisible = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5)) {
                chatVisible = true
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var currentPage = 0
    @State private var taglineOpacity: Double = 0.0
    @State private var pagesVisible = false

    private let amber = Color(hex: 0xFFB800)

    private var pages: [(title: String, subtitle: String, color: Color, illustration: AnyView)] {
        [
            (
                "No towers. No internet.\nNo problem.",
                "ChirpChirp works when nothing else does. Your phone connects directly to nearby devices.",
                Constants.Colors.hotRed,
                AnyView(TowerDownIllustration())
            ),
            (
                "Every phone extends\nthe network.",
                "Your phone helps others communicate, and theirs helps you. The mesh grows with every user.",
                Constants.Colors.amber,
                AnyView(MeshNetworkIllustration())
            ),
            (
                "Talk or text.",
                "Voice for speed. Text for stealth and efficiency. Both work across the mesh.",
                Constants.Colors.amber,
                AnyView(TalkChatIllustration())
            ),
            (
                "Private by default.",
                "End-to-end encrypted. No servers. No accounts. No data collection. Ever.",
                Constants.Colors.electricGreen,
                AnyView(EncryptionIllustration())
            ),
            (
                "Built for when\nit matters most.",
                "Natural disasters. Concerts. Protests. Off-grid adventures. Anywhere communication fails.",
                Constants.Colors.amber,
                AnyView(UseCasesIllustration())
            ),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MeshGradientBackground()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 50)

                // Animated perch birds mascot
                PerchBirdsView(size: 200, isAnimating: true)
                    .frame(height: 130)
                    .padding(.bottom, 12)

                // Spring letter wordmark
                SpringWordmark()
                    .padding(.bottom, 4)

                // Tagline
                Text("Infrastructure-free communication.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .opacity(taglineOpacity)

                Spacer()
                    .frame(height: 24)

                // Swipeable pages
                if pagesVisible {
                    TabView(selection: $currentPage) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingV2Page(
                                title: page.title,
                                subtitle: page.subtitle,
                                accentColor: page.color,
                                illustration: page.illustration
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 360)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    // Custom page dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == currentPage
                                        ? amber
                                        : amber.opacity(0.25)
                                )
                                .frame(
                                    width: index == currentPage ? 22 : 7,
                                    height: 7
                                )
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer()

                // Get Started button (last page)
                if currentPage == pages.count - 1 {
                    ShimmerGetStartedButton {
                        appState.isOnboardingComplete = true
                    }
                    .padding(.horizontal, 32)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                // No internet badge
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .semibold))
                    Text("No internet required")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(amber.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(amber.opacity(0.08))
                        .overlay(
                            Capsule()
                                .stroke(amber.opacity(0.15), lineWidth: 0.5)
                        )
                )
                .padding(.top, 16)
                .opacity(taglineOpacity)

                Spacer()
                    .frame(height: 30)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
        }
        .onAppear {
            startAnimations()
        }
        .accessibilityElement(children: .contain)
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.8).delay(0.9)) {
            taglineOpacity = 1.0
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.3)) {
            pagesVisible = true
        }
    }
}
